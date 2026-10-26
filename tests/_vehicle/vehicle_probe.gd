extends RefCounted
## Shared bits for the vehicle tests (ticket #54, rules V1 to V9; not a test).
## `const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")`.
## The vehicle's frame is in `vehicle_frame_probe.gd` (`const VehicleFrame`); placing, the ride
## and driving in `vehicle_ride_probe.gd` (`const VehicleRide`).
##
## Everything is read through the drivable contract: the character's `use.try_use_vehicle()`,
## `use.vehicle()`, `use.is_in_vehicle()` (true only while seated) and `movement.posture_folded()`
## (the ride fold while in a vehicle); the vehicle's `doors()` (`{ id, kind, seat, handle, open,
## hinge, angle, offset }` per door, world space), `seats()` (`{ id, occupant }`), `driver()`,
## `speed()` (unsigned px/s), `engine_state()` (`{ running, rpm, load }`), `slip()` (the slide
## amount, 0 while gripping), `wheel_angle()`, `brake_lights()`, its `Chassis` / `Roof` draw layers,
## and the Vehicles holders' tuning. Nothing here knows how a vehicle is built, and a read that does
## not exist yet fails a `require` instead of a script error.

## The plan's numbers: the spec, not the code.
## E picks a door whose handle is within this of the character.
const DOOR_REACH := 60.0
## Boarding only below this speed (px/s).
const BOARD_MAX_SPEED := 20.0
## Above this, E brakes to a stop first.
const EXIT_MAX_SPEED := 20.0
## A character struck slower than this is shoved, not hurt.
const HARM_MIN_SPEED := 90.0
## A door eases open in about this long.
const DOOR_OPEN_TIME := 0.35
## The fold into the seat takes about this long.
const FOLD_TIME := 0.5
## Each kind's doors: id -> [kind, the seat behind it].
const CAR_DOORS := {
	&"front_left": [&"swing", &"driver"],
	&"front_right": [&"swing", &"passenger"],
	&"rear_left": [&"swing", &"rear_left"],
	&"rear_right": [&"swing", &"rear_right"],
}
const VAN_DOORS := {
	&"front_left": [&"swing", &"driver"],
	&"front_right": [&"swing", &"passenger"],
	&"side": [&"slide", &"cargo_right"],
	&"rear_left": [&"rear", &"cargo_left"],
	&"rear_right": [&"rear", &"cargo_right"],
}
const CAR_SEATS := [&"driver", &"passenger", &"rear_left", &"rear_right"]
const VAN_SEATS := [&"driver", &"passenger", &"cargo_left", &"cargo_right"]
## What a character needs to use a vehicle, and what every vehicle reads out.
const CHARACTER_READS := [&"try_use_vehicle", &"vehicle", &"is_in_vehicle"]
const VEHICLE_READS := [
	&"doors", &"seats", &"driver", &"speed", &"engine_state", &"slip", &"get_surface",
]
## The sound categories the vehicles add (V7).
const SOUND_CATEGORIES := [&"engine", &"vehicle", &"skid"]


# --- Premises -------------------------------------------------------------------------------


## Require that vehicle `id` was placed (its scene exists), that it has the contract's reads (plus
## `extra`), and that every actor in `characters` can use a vehicle. False (the test has ended) at
## the first that does not hold.
static func ready(
	t: TestContext,
	id: StringName,
	characters: Array = [],
	extra: Array = [],
) -> bool:
	var v := t.vehicle(id)
	if not t.require(
			v != null,
			"the vehicle %s exists (TestSetup.vehicle placed res://scenes/vehicle/<kind>.tscn)"
				% id,
	):
		return false
	if not has_reads(t, v, VEHICLE_READS + extra, "the %s" % id):
		return false
	for c in characters:
		var who := t.actor(c)
		if not t.require(who != null, "actor %s exists" % c):
			return false
		if not has_reads(t, who.use, CHARACTER_READS, "character %s's use" % c):
			return false
	return true


## Require that `node` has every method in `methods`, naming the missing ones.
static func has_reads(t: TestContext, node: Object, methods: Array, what: String) -> bool:
	var missing: Array = methods.filter(func(m): return not node.has_method(m))
	return t.require(
		missing.is_empty(),
		"%s has %s (missing: %s)"
			% [what, ", ".join(methods.map(func(m): return String(m) + "()")), missing],
	)


## The Vehicles domain's static holder `holder` (`VehicleConfig`, `VehicleCollisionConfig` ...),
## looked up by class name, so a test naming one still parses before it exists. A missing holder is
## an error, and null.
static func _config(holder: StringName) -> Script:
	for c in ProjectSettings.get_global_class_list():
		if c["class"] == holder:
			return load(c["path"])
	push_error("vehicle_probe: no class named %s" % holder)
	return null


## A number of a Vehicles holder by name (`VehicleConfig`'s `kinds` ...). A missing holder or a name
## the holder has no static var by is an error, and null: never a stand-in value.
static func config_value(holder: StringName, prop: StringName) -> Variant:
	var c := _config(holder)
	if c == null:
		return null
	if not prop in c:
		push_error("vehicle_probe: %s has no static var '%s'" % [holder, prop])
		return null
	return c.get(prop)


## A per-kind `VehicleConfig.kinds[kind][key]` (`top_speed` ...), or `fallback` without one.
static func kind_value(kind: StringName, key: StringName, fallback: Variant = null) -> Variant:
	var kinds: Variant = config_value(&"VehicleConfig", &"kinds")
	if not kinds is Dictionary:
		return fallback
	var row: Variant = kinds.get(kind, kinds.get(String(kind)))
	if not row is Dictionary:
		return fallback
	return row.get(key, row.get(String(key), fallback))


# --- Doors and seats ------------------------------------------------------------------------


## Door `id` of `v` as `doors()` reports it now, or {}.
static func door(v: Node, id: StringName) -> Dictionary:
	for d: Dictionary in v.doors():
		if d.get("id") == id:
			return d
	return {}


## The ids of `v`'s doors.
static func _door_ids(v: Node) -> Array:
	return v.doors().map(func(d): return d.get("id"))


## How far door `id` is open (0..1), 0 for an unknown door.
static func open_of(v: Node, id: StringName) -> float:
	return float(door(v, id).get("open", 0.0))


## The seat `character` sits in (or is boarding into), &"" when none.
static func seat_of(v: Node, character: Node) -> StringName:
	for s: Dictionary in v.seats():
		if s.get("occupant") == character:
			return s.get("id", &"")
	return &""


## Who sits in seat `id` (null when empty or unknown).
static func occupant(v: Node, id: StringName) -> Node:
	for s: Dictionary in v.seats():
		if s.get("id") == id:
			var who: Variant = s.get("occupant")
			return who if is_instance_valid(who) else null
	return null


## `ids` as Strings, sorted (to compare sets of ids whatever order they are listed in).
static func sorted(ids: Array) -> Array:
	var out: Array = ids.map(func(x): return String(x))
	out.sort()
	return out


## Every door's largest open amount while `condition` stays false (sampled each frame, at most
## `timeout` s). Returns `{ done: bool (condition came true), max: { door id: open } }`.
static func watch_doors(t: TestContext, v: Node, condition: Callable, timeout: float) -> Dictionary:
	var most := {}
	for id in _door_ids(v):
		most[id] = 0.0
	var deadline := t.time + timeout
	var done := false
	while t.time < deadline:
		for d: Dictionary in v.doors():
			most[d.get("id")] = maxf(most.get(d.get("id"), 0.0), float(d.get("open", 0.0)))
		if condition.call():
			done = true
			break
		await t.frames(1)
	return { "done": done, "max": most }


## The doors in a `watch_doors` result that opened past `threshold`.
static func opened(watched: Dictionary, threshold := 0.5) -> Array:
	var out: Array = []
	for id in watched["max"]:
		if watched["max"][id] > threshold:
			out.append(id)
	return out


# --- Drawing --------------------------------------------------------------------------------


## The vehicle's draw layer `layer_name` (`Chassis` under the occupants, `Roof` over them), or null.
static func layer(v: Node, layer_name: String) -> CanvasItem:
	return v.find_child(layer_name, true, false) as CanvasItem


## The z index `item` is drawn at, its relative parents' added in.
static func absolute_z(item: CanvasItem) -> int:
	var z := item.z_index
	var node: Node = item
	while (node as CanvasItem).z_as_relative:
		node = node.get_parent()
		if not node is CanvasItem:
			break
		z += (node as CanvasItem).z_index
	return z


## Whether `a` is drawn over `b`: a higher absolute z, or the same z and later in the tree.
static func draws_above(a: CanvasItem, b: CanvasItem) -> bool:
	var za := absolute_z(a)
	var zb := absolute_z(b)
	if za != zb:
		return za > zb
	return a.is_greater_than(b)


# --- Sound ----------------------------------------------------------------------------------


## A sound range table with nothing out of earshot, the vehicle categories included.
static func everywhere() -> Dictionary:
	var out: Dictionary = SoundConfig.category_range.duplicate()
	for k in out:
		out[k] = 1.0e9
	for k in SOUND_CATEGORIES:
		out[k] = 1.0e9
	return out
