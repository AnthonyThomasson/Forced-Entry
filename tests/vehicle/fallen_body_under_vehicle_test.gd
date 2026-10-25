extends GameTest
## V6 / F1 (ticket #54, feedback round 1): a fallen body lies under the vehicle. A driver runs a
## standing character down past harm_kill_speed, brakes, and then creeps the car forward until it
## stands over the body. Every frame from the death on, while the body lies under the car or beside
## it, the body (the character and everything it draws) is drawn under both of the car's layers, the
## Chassis and the Roof, and over the floor and any blood on it (its own bleed-out included); the
## seated driver stays drawn over the Chassis and under the Roof all the while. Draw order is the
## effective one: absolute z first, then tree order (`Probe.draws_above`).

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## How far ahead of the car's nose (px) the victim stands: room to get past harm_kill_speed.
const RUN_UP := 900.0
## A body this close to the car's outline (px) counts as beside it.
const BESIDE := 40.0
## The creep forward over the body: throttle, and how near the car's centre line (px, along it) the
## body must come.
const CREEP_THROTTLE := 0.3
const OVER_MIDDLE := 30.0


func describe() -> Dictionary:
	return {
		"name": "A fallen body lies under the vehicle",
		"description": "A character run down by a car: every frame the car is over or beside the "
			+ "body, the body is drawn under the car's Chassis and Roof and over the floor and "
			+ "blood, and the seated driver stays between the Chassis and the Roof.",
		"tags": ["vehicle", "car", "draw", "death", "character"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2600, 700), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(300, 350))
	s.actor(&"driver", &"puppet", Vector2(150, 150))
	s.actor(&"victim", &"puppet", Vector2(2400, 600))


func run(t: TestContext) -> void:
	var scene := _set_up(t)
	if scene == null:
		return
	if not await _run_down(t, scene):
		return
	var samples := await _sample_after_death(t, scene)
	var car := scene.car
	var victim := scene.victim
	t.trace("frames near the body", samples["near"])
	t.trace("frames over the body", samples["over"])
	if not t.require(
			samples["over"] > 0,
			("the car stands over the body at some point (%d frames near it, the body ends at %s "
					+ "in the car's frame)") % [samples["near"], car.to_local(_body_point(victim))],
	):
		return
	t.check(
		not _blood(t.world, victim).is_empty(),
		"the body has bled onto the floor (blood to compare against)",
	)
	t.check(
		samples["bad_body"] == 0,
		("the body lies under the Chassis and the Roof and over the floor and blood every frame "
				+ "the car is over or beside it (wrong on %d of %d frames; first: %s)")
			% [samples["bad_body"], samples["near"], samples["first_body"]],
	)
	t.check(
		samples["bad_seated"] == 0,
		("the seated driver stays over the Chassis and under the Roof (wrong on %d frames; first: "
				+ "%s)") % [samples["bad_seated"], samples["first_seated"]],
	)


## The car, its layers and measures, the two characters and the floors a sample reads, or null
## when one is missing (the test has ended).
func _set_up(t: TestContext) -> Scene:
	if not Probe.ready(t, &"car", [&"driver"]):
		return null
	var scene := Scene.new()
	scene.car = t.vehicle(&"car") as Node2D
	scene.driver = t.actor(&"driver") as Node2D
	scene.victim = t.actor(&"victim") as Node2D
	scene.chassis = Probe.layer(scene.car, "Chassis")
	scene.roof = Probe.layer(scene.car, "Roof")
	if not t.require(
			scene.chassis != null and scene.roof != null,
			"the car has its Chassis and Roof draw layers",
	):
		return null
	var kill: Variant = Probe.config_value(&"VehicleCollisionConfig", &"harm_kill_speed")
	if not t.require(kill != null, "VehicleCollisionConfig.harm_kill_speed exists"):
		return null
	scene.kill_speed = float(kill)
	var car := scene.car
	scene.half_length = car.global_position.distance_to(Probe.edge(car, Probe.forward(car)))
	scene.half_width = car.global_position.distance_to(Probe.edge(car, Probe.right(car)))
	scene.floors = _floors(t.world)
	if not t.require(not scene.floors.is_empty(), "the arena has a floor to compare against"):
		return null
	return scene


## The driver gets in and runs the victim down at full throttle (false: it did not, the test has
## ended).
func _run_down(t: TestContext, scene: Scene) -> bool:
	var car := scene.car
	if not t.require(await Probe.board_by(t, &"driver", car, &"front_left"), "the driver gets in"):
		return false
	await t.seconds(0.5)
	var nose := Probe.edge(car, Probe.forward(car))
	await Probe.place(t, &"victim", nose + Probe.forward(car) * RUN_UP)

	# Full throttle at the victim until it is struck down.
	t.puppet(&"driver").drive(1.0, 0.0, false)
	var struck := 0.0
	var deadline := t.time + 8.0
	while t.time < deadline and not scene.victim.is_dead:
		struck = car.speed()
		await t.frames(1)
	return t.require(
		scene.victim.is_dead,
		"the car runs the victim down (at %.0f px/s, harm_kill_speed %.0f)"
			% [struck, scene.kill_speed],
	)


## From the death on: brake to a stop, let the body come to rest, then creep forward until the
## car stands over it. Samples the draw order every frame; returns the tally `_sample` keeps.
func _sample_after_death(t: TestContext, scene: Scene) -> Dictionary:
	var car := scene.car
	var victim := scene.victim
	var p := t.puppet(&"driver")
	var samples := {
		"near": 0, "over": 0, "bad_body": 0, "bad_seated": 0, "first_body": "", "first_seated": "",
	}
	p.drive(-1.0, 0.0, false)
	var deadline := t.time + 3.0
	while t.time < deadline and (Probe.along(car) > 2.0 or not victim.ragdoll.is_settled()):
		await t.frames(1)
		_sample(t, scene, samples)
	p.drive(0.0, 0.0, false)
	await t.until(func(): return not _blood(t.world, victim).is_empty(), 3.0)
	deadline = t.time + 6.0
	while t.time < deadline and car.to_local(_body_point(victim)).x > OVER_MIDDLE:
		p.drive(CREEP_THROTTLE, 0.0, false)
		await t.frames(1)
		_sample(t, scene, samples)
	p.drive(-1.0, 0.0, false)
	for i in 30:
		await t.frames(1)
		_sample(t, scene, samples)
	p.drive(0.0, 0.0, false)
	return samples


## One frame's draw-order checks, counted into `out` (only while the body is under or beside the
## car).
func _sample(t: TestContext, scene: Scene, out: Dictionary) -> void:
	var local := scene.car.to_local(_body_point(scene.victim))
	if (absf(local.x) > scene.half_length + BESIDE
			or absf(local.y) > scene.half_width + BESIDE):
		return
	out["near"] += 1
	if absf(local.x) <= scene.half_length and absf(local.y) <= scene.half_width:
		out["over"] += 1
	var wrong := _wrong_body(t, scene)
	if wrong != "":
		out["bad_body"] += 1
		if out["first_body"] == "":
			out["first_body"] = "t=%.2f %s" % [t.time, wrong]
	_sample_seated(t, scene, out)


## The first of the body's drawn items out of place this frame (over the Chassis or the Roof, or
## under the floor or blood), said, or "" when all are in place.
func _wrong_body(t: TestContext, scene: Scene) -> String:
	var under := scene.floors + _blood(t.world, scene.victim)
	for item in _drawn(scene.victim):
		var wrong := _wrong_item(item, scene, under)
		if wrong != "":
			return wrong
	return ""


## Whether the drawn `item` is out of place: over the Chassis or the Roof, or under one of `under`
## (the floors and blood), said; "" when it is in place.
func _wrong_item(item: CanvasItem, scene: Scene, under: Array) -> String:
	if Probe.draws_above(item, scene.chassis):
		return ("%s (z %d) over the Chassis (z %d)"
				% [item.name, Probe.absolute_z(item), Probe.absolute_z(scene.chassis)])
	if Probe.draws_above(item, scene.roof):
		return ("%s (z %d) over the Roof (z %d)"
				% [item.name, Probe.absolute_z(item), Probe.absolute_z(scene.roof)])
	for low: CanvasItem in under:
		if not Probe.draws_above(item, low):
			return ("%s (z %d) under %s (z %d)"
					% [item.name, Probe.absolute_z(item), low.name, Probe.absolute_z(low)])
	return ""


## The seated driver's draw order this frame, counted into `out`: over the Chassis, under the Roof.
func _sample_seated(t: TestContext, scene: Scene, out: Dictionary) -> void:
	var driver := scene.driver
	var chassis := scene.chassis
	var roof := scene.roof
	if (driver.use.is_in_vehicle()
			and Probe.draws_above(driver, chassis)
			and Probe.draws_above(roof, driver)):
		return
	out["bad_seated"] += 1
	if out["first_seated"] == "":
		out["first_seated"] = "t=%.2f seated %s, driver z %d, Chassis z %d, Roof z %d" % [
			t.time,
			driver.use.is_in_vehicle(),
			Probe.absolute_z(driver),
			Probe.absolute_z(chassis),
			Probe.absolute_z(roof),
		]


## Where the fallen body lies (its blood origin, else its position).
func _body_point(victim: Node2D) -> Vector2:
	return victim.blood_origin() if victim.has_method("blood_origin") else victim.global_position


## The character and every visible canvas item it draws with.
func _drawn(character: CanvasItem) -> Array:
	var out: Array = [character]
	for n in character.find_children("*", "CanvasItem", true, false):
		if (n as CanvasItem).is_visible_in_tree():
			out.append(n)
	return out


## The world's floors (the Objects domain's floor nodes).
func _floors(world: Node) -> Array:
	return world.find_children("*", "Node2D", true, false).filter(func(n):
		return (n.get_script() != null
				and String(n.get_script().resource_path).ends_with("objects/floor/floor.gd")))


## The blood and scorch canvas items on the floor (splatters, pools, the decal layers), outside the
## character itself.
func _blood(world: Node, character: Node) -> Array:
	var out: Array = []
	for pattern in ["Blood*", "Scorch*"]:
		for n in world.find_children(pattern, "CanvasItem", true, false):
			if not character.is_ancestor_of(n):
				out.append(n)
	return out


## What each frame's sample reads: the car, its draw layers and half measures, the driver, the
## victim and the arena's floors, and the harm_kill_speed it runs the victim down past.
class Scene:
	## The car.
	var car: Node2D
	## Its Chassis draw layer.
	var chassis: CanvasItem
	## Its Roof draw layer.
	var roof: CanvasItem
	## The seated driver.
	var driver: Node2D
	## The character run down.
	var victim: Node2D
	## The world's floor nodes.
	var floors: Array = []
	## Half the car's length, centre to nose (px).
	var half_length: float = 0.0
	## Half the car's width, centre to side (px).
	var half_width: float = 0.0
	## VehicleCollisionConfig.harm_kill_speed (px/s).
	var kill_speed: float = 0.0
