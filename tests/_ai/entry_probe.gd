extends RefCounted
## Shared helpers for the tactical-entry tests (tests/ai/entry/; not a test itself). The behaviour
## they assert is `docs/tactical-entry.md` (E1 to E15). The doorway geometry here is the test's own
## copy (a door's axis, its outward side, the funnel), so the spec isn't read back from the code
## under test; the NPC is read only through its public observer API: `current_act()`,
## `debug_entry()`, `debug_room_zones()` and its radio callouts; a puppet teammate radios a claim
## with `radio_claim`. The per-frame sampler of a run and its reads are `entry_watch_probe.gd`
## (`EntryWatch`).

const Maps := preload("res://tests/_ai/flank_maps.gd")
## The Terrace house doorways the tests go through, each with the side the team stacks on (`out`, a
## unit normal pointing away from the room being entered) and the room behind it.
const BACK := {
	"id": "door_840_190",
	"pos": Maps.DOOR_BACK,
	"width": 90.0,
	"out": Vector2.RIGHT,
	"room": Maps.HOUSE_KITCHEN,
	"room_key": "kitchen",
}
const FRONT := {
	"id": "door_0_415",
	"pos": Maps.DOOR_FRONT,
	"width": 80.0,
	"out": Vector2.LEFT,
	"room": Maps.HOUSE_HALL,
	"room_key": "hall",
}
const KITCHEN_LIVING := {
	"id": "door_480_150",
	"pos": Maps.DOOR_LIVING_KITCHEN,
	"width": 90.0,
	"out": Vector2.RIGHT,
	"room": Maps.HOUSE_LIVING,
	"room_key": "living_room",
}
const HALL_LIVING := {
	"id": "door_150_360",
	"pos": Maps.DOOR_HALL_LIVING,
	"width": 80.0,
	"out": Vector2.DOWN,
	"room": Maps.HOUSE_LIVING,
	"room_key": "living_room",
}
## The doorways on out of a cleared room, framed from the side the team holds (`out` points into the
## cleared room): the kitchen's into the hall, and the living room's into the kitchen. With
## `KITCHEN_LIVING` (the kitchen's into the living room) they are what a team that has cleared the
## kitchen or the living room covers (E8).
const KITCHEN_HALL := {
	"id": "door_690_360",
	"pos": Maps.DOOR_HALL_KITCHEN,
	"width": 80.0,
	"out": Vector2.UP,
	"room": Maps.HOUSE_HALL,
	"room_key": "hall",
}
const LIVING_KITCHEN := {
	"id": "door_480_150",
	"pos": Maps.DOOR_LIVING_KITCHEN,
	"width": 90.0,
	"out": Vector2.LEFT,
	"room": Maps.HOUSE_KITCHEN,
	"room_key": "kitchen",
}
## The corridor spine's room doors, framed from the corridor (E15), and the box room's door, framed
## from its corridor (E13).
const SPINE_A := {
	"id": "door_150_200",
	"pos": Maps.DOOR_A,
	"width": 80.0,
	"out": Vector2.DOWN,
	"room": Maps.SPINE_ROOM_A,
	"room_key": "room_a",
}
const SPINE_B := {
	"id": "door_450_200",
	"pos": Maps.DOOR_B,
	"width": 80.0,
	"out": Vector2.DOWN,
	"room": Maps.SPINE_ROOM_B,
	"room_key": "room_b",
}
const SPINE_C := {
	"id": "door_750_200",
	"pos": Maps.DOOR_C,
	"width": 80.0,
	"out": Vector2.DOWN,
	"room": Maps.SPINE_ROOM_C,
	"room_key": "room_c",
}
const BOX := {
	"id": "door_290_200",
	"pos": Maps.DOOR_BOX,
	"width": 70.0,
	"out": Vector2.DOWN,
	"room": Maps.BOX_ROOM,
	"room_key": "box_room",
}
## How deep (px) the funnel reaches either side of the wall plane: the strip in the doorway where an
## entrant is exposed.
const FUNNEL_DEPTH := 40.0
## Half the wall thickness plus a body radius: past this far inside the wall plane a body is in the
## room.
const INSIDE_DEPTH := 22.0


## Scripted Von for an entry through `door`: whenever asked, SEARCH → ENTER → that doorway, and in a
## fight engage (the first firing spot offered). The switches every entry test shares: no trespass
## hostility, no bullets flying over cover. Call it after the map.
static func rules(s: TestSetup, door: Dictionary, extra: Array = []) -> void:
	var script: Array = [{ "pick": "enter" }, { "pick": door["id"] }, { "pick": "engage" }]
	script.append_array(extra)
	s.von_script(script)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)


## Scripted Von for a test of the entry guard (E9): whenever asked, the first of `picks` that is
## offered (ids, in order of preference; never ENTER, the point is a plain order that crosses a
## doorway), the same shared switches as `rules`. Call it after the map.
static func guard_rules(s: TestSetup, picks: Array) -> void:
	s.von_script(picks.map(func(p): return { "pick": p }))
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)


## An invader at `pos` that walks (unlike `flank_probe.npc`, which holds still), deciding every
## 0.4 s; `gc` overrides the NPC's tunables, by indexed path (a `tuning:decision:decide_interval`
## of its own offsets its decide timers so two invaders never decide on the same frame unless a
## test wants them to), `props` the character's.
static func npc(
	s: TestSetup,
	id: StringName,
	pos: Vector2,
	gc: Dictionary = {},
	props: Dictionary = {},
) -> void:
	var p := { "max_health": 1_000_000.0 }
	p.merge(props, true)
	s.actor(id, &"invader", pos, p)
	var g := {
		"tuning:decision:decide_interval": 0.4,
		"tuning:decision:tactic_interval": 3.0,
		"tuning:decision:max_commit_time": 30.0,
	}
	g.merge(gc, true)
	s.set_props(id, "GoalController", g)


## A household target puppet at `pos` facing `look_at`: hostile to an invader on sight, never
## killed.
static func target(
	s: TestSetup,
	id: StringName,
	pos: Vector2,
	look_at: Vector2,
	props: Dictionary = {},
) -> void:
	var p := {
		"faction": &"household",
		"max_health": 1_000_000.0,
		"movement:aim_point": look_at,
		"facing": (look_at - pos).normalized(),
	}
	p.merge(props, true)
	s.actor(id, &"puppet", pos, p)


# --- The doorway, in the test's own frame ------------------------------------------------------


## How far `p` lies out from the wall plane of `door` (positive = on the stacking side, negative =
## in the room).
static func outward(door: Dictionary, p: Vector2) -> float:
	return (p - (door["pos"] as Vector2)).dot(door["out"])


## How far `p` lies along the wall from the door's centre (signed; the sign tells the side of the
## door axis).
static func lateral(door: Dictionary, p: Vector2) -> float:
	return (p - (door["pos"] as Vector2)).dot((door["out"] as Vector2).orthogonal())


## Whether `p` is in the fatal funnel: inside the doorway's width and within `FUNNEL_DEPTH` of the
## wall plane.
static func in_funnel(door: Dictionary, p: Vector2) -> bool:
	return (absf(lateral(door, p)) < float(door["width"]) * 0.5
			and absf(outward(door, p)) < FUNNEL_DEPTH)


## Whether a body at `p` facing `facing` points its gun through `door` from the side the door is
## framed from: it stands on the `out` side and looks within about 30° of the doorway's centre.
static func faces_through(door: Dictionary, p: Vector2, facing: Vector2) -> bool:
	var to_door := (door["pos"] as Vector2) - p
	return (outward(door, p) > 0.0
			and to_door.length() > 1.0
			and facing.normalized().dot(to_door.normalized()) > 0.85)


## Whether `p` is in the room behind `door`.
static func in_room(door: Dictionary, p: Vector2) -> bool:
	return (door["room"] as Rect2).has_point(p) and outward(door, p) < -INSIDE_DEPTH


## Whether `p` is against the wall beside the door, out of the doorway's view into the room: on the
## stacking side, close to the wall plane, and clear of the door's width by a body.
static func beside_door(door: Dictionary, p: Vector2) -> bool:
	var o := outward(door, p)
	return o > 0.0 and o <= 48.0 and absf(lateral(door, p)) >= float(door["width"]) * 0.5 + 10.0


## The four corners of the room behind `door`, inset `inset` px: the two on the door's wall (unseen
## from outside: hard) first, then the two far ones.
static func corners(door: Dictionary, inset := 40.0) -> Dictionary:
	var r: Rect2 = (door["room"] as Rect2).grow(-inset)
	var all := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	all.sort_custom(func(a, b): return outward(door, a) > outward(door, b))
	return { "near": all.slice(0, 2), "far": all.slice(2, 4) }


# --- The radio and the brain ---------------------------------------------------------------------


## The NPC brain of actor `id` (its controller, found by `debug_entry`).
static func brain(t: TestContext, id: StringName) -> Node:
	return t.controller(id, &"debug_entry")


## What the brain reports of its running entry (`{}` when it isn't entering): `opening`, `slot`,
## `solo`, `phase`, `seen_fraction`, `hidden_corners`, `corner`, `stack_point`, `pie_sides`.
static func entry(b: Node) -> Dictionary:
	return b.debug_entry() if b != null else {}


## The entry callouts radioed so far, optionally only step `step` and / or only from actor `id`'s
## character.
static func calls(t: TestContext, step := "", id: StringName = &"") -> Array:
	var who := t.actor(id) if id != &"" else null
	return t.events_of(&"callout", func(d):
		if String(d.get("entry_step", "")) == "":
			return false
		if step != "" and String(d.get("entry_step", "")) != step:
			return false
		return who == null or d.get("speaker") == who)


## Radio puppet `c`'s claim on doorway `opening` into room `into` the way an AI member does:
## `place` its slot (x) on the side of the door (y, 1 / -1 along its wall), still on its way
## (`claim`), made on `frame` where it stands.
static func radio_claim(
	c: Node2D,
	opening: String,
	into: String,
	place: Vector2i,
	frame: int,
) -> void:
	EventBus.post(
		&"callout",
		{
			"speaker": c, "faction": c.faction, "position": c.global_position, "status": "",
			"path": "", "label": "", "target_id": 0, "point": Vector2.ZERO, "opening": opening,
			"into": into, "slot": place.x, "side": place.y, "entry_step": "claim",
			"claim_frame": frame, "claim_pos": c.global_position,
		},
	)


## The sim time of the first entry callout of step `step` from actor `id` (about doorway `opening`
## when given), or INF.
static func first_call_time(t: TestContext, step: String, id: StringName, opening := "") -> float:
	var who := t.actor(id)
	for e in t.events:
		if (e["topic"] != &"callout"
				or e["data"].get("speaker") != who
				or String(e["data"].get("entry_step", "")) != step):
			continue
		if opening == "" or String(e["data"].get("opening", "")) == opening:
			return e["time"]
	return INF


## Whether any Von question so far was answered with an option id starting with `prefix` (a script
## that picks by id falls back to the first option offered, so a test of a plain order checks the
## order was really the one chosen).
static func asked(prefix: String) -> bool:
	for r in DecisionStub.requests:
		if String(r["pick"]).begins_with(prefix):
			return true
	return false


## The status the brain of actor `id` gives the room with key `room_key` (`current` / `searched` /
## `unsearched` / `unknown`), matched by rect.
static func room_status(t: TestContext, id: StringName, rect: Rect2) -> String:
	for z in brain(t, id).debug_room_zones():
		if (z["rect"] as Rect2) == rect:
			return String(z["status"])
	return ""
