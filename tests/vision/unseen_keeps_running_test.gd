extends GameTest
## V11 (`docs/player-vision.md`): the view never touches what the world does. A character wholly
## outside the cone and bubble keeps its pose, aim, hands, footsteps and ragdoll running (gameplay
## reads those, never what is drawn), so a hit lands on it as it would unviewed. (What is drawn of
## it, hidden outside the cone and shown the frame the cone reaches it, is the 3D mirror's:
## `art/mirror_hides_unseen_movers`; the area itself, `general/seen_area_suite` and
## `general/seen_area_rect_suite`.)
##
## Two worlds built from one declaration, one with the view on the viewer and one without: the
## viewer looks east, away from a walker that walks about behind its left shoulder and a shooter
## that shoots it three times. The walker is wholly outside the viewed cone, and the shots land at
## the same places, for the same damage, against the shoulders turned the same way.
##
## It reads (tests/_vision/vision_probe.gd) the `PlayerView`: `sees(point)`; the 3D view is the
## one built (`GroundLayer.enabled`).

const Probe := preload("res://tests/_vision/vision_probe.gd")
const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
## A disc this far (px) round the walker is surely wholly outside the cone (its drawn reach is 60).
const SURELY_OUT := 70.0
## A disc is sampled by `RING` points on its rim (a gap of under 0.01 px at 60).
const RING := 360
## Twin worlds: the viewer, the walker and the shooter, away from the session's arena.
const TWIN_EYE := Vector2(3700, 350)
const TWIN_WALKER := Vector2(3580, 210)
const TWIN_SHOOTER := Vector2(3600, 520)
## The test camera frames the session's world; a twin world is framed by a camera of its own.
const TWIN_ZOOM := 0.4


func describe() -> Dictionary:
	return {
		"name": "A character out of the cone runs on as if unviewed",
		"description": "The same walker shot three times in two worlds, one viewed by an eye "
			+ "looking away from it and one not: the hits land at the same places, cost the "
			+ "same health and find the shoulders turned the same way.",
		"tags": ["vision", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	# Out of the way of the worlds the test builds; they build the 3D view.
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(GroundLayer, &"enabled", true)


func run(t: TestContext) -> void:
	var plain := await _twin(t, false)
	var viewed := await _twin(t, true)
	for i in mini(plain["shots"].size(), viewed["shots"].size()):
		var a: Dictionary = plain["shots"][i]
		var b: Dictionary = viewed["shots"][i]
		t.require(not a["hit"].is_empty(), "premise: shot %d hits the unviewed walker" % i)
		t.check(not b["hit"].is_empty(), "shot %d hits the viewed walker too" % i)
		if a["hit"].is_empty() or b["hit"].is_empty():
			continue
		t.check(
			(a["hit"]["position"] as Vector2).distance_to(b["hit"]["position"]) < 3.0,
			"shot %d lands at the same place (%s unviewed, %s viewed)"
			% [i, a["hit"]["position"], b["hit"]["position"]],
		)
		t.check(
			absf(a["lost"] - b["lost"]) < 0.01,
			"shot %d costs the same health (%.2f, %.2f)" % [i, a["lost"], b["lost"]],
		)
		t.check(
			absf(angle_difference(a["torso"], b["torso"])) < 0.02,
			"shot %d finds the shoulders turned the same way (%.3f, %.3f)"
			% [i, a["torso"], b["torso"]],
		)
	t.check(plain["shots"].size() == 3 and viewed["shots"].size() == 3, "both worlds took 3 shots")


## One world, the view of the viewer or none: the walker walks out of the cone and is shot at; what
## the hits were.
func _twin(t: TestContext, viewed: bool) -> Dictionary:
	var s := TestSetup.new()
	s.arena(Rect2(3000, 0, 1400, 700))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.switch(&"vision.enabled", viewed)
	s.switch(&"projectile.flyover", false)
	# A round strikes at one height, so the zone it strikes is the same every run.
	OutfitProbe.pin_height(s)
	s.actor(&"eye", &"puppet", TWIN_EYE, { "start_slot": 1 })
	s.actor(&"walker", &"puppet", TWIN_WALKER, { "start_slot": 1, "max_health": 100_000.0 })
	s.actor(&"shooter", &"puppet", TWIN_SHOOTER, { "start_slot": 3 })
	s.view(&"eye")
	var world: Node2D = await Probe.build_world(t, s)
	var camera := Camera2D.new()
	camera.zoom = Vector2.ONE * TWIN_ZOOM
	camera.position = TWIN_EYE
	world.add_child(camera)
	camera.make_current()
	var out := { "shots": [] }
	var walker: Node2D = world.actors[&"walker"]
	await t.seconds(0.5)
	# The viewer looks east, away from both.
	_puppet_of(world, &"eye").aim_at(TWIN_EYE + Vector2(300, 0))
	await t.seconds(0.5)
	var views := Probe.views_under(world)
	if not t.require(
		views.size() == (1 if viewed else 0),
		"premise: the %s world has %d view(s)" % ["viewed" if viewed else "unviewed", views.size()],
	):
		await Probe.drop_world(t, world)
		return out
	_puppet_of(world, &"walker").walk_to(TWIN_WALKER + Vector2(40, 30))
	await t.seconds(2.0)
	_puppet_of(world, &"shooter").aim_at(walker)
	await t.seconds(0.5)
	if viewed:
		t.check(
			not _reaches(views[0], walker.global_position, SURELY_OUT),
			"premise: the walker is wholly outside the viewer's cone",
		)
	out["shots"] = await _shoot(t, world)
	await Probe.drop_world(t, world)
	return out


## Three shots from the shooter at the walker. For each: the `hit` that struck the walker (its place
## and damage, empty when none did), the health it cost and the angle its shoulders were turned to
## (which sets the side a round strikes).
func _shoot(t: TestContext, world: Node2D) -> Array:
	var walker: Node2D = world.actors[&"walker"]
	var shots: Array = []
	var struck: Array = []
	var listener := func(topic: StringName, data: Dictionary) -> void:
		if topic == &"hit" and data.get("victim") == walker:
			struck.append({ "position": data["position"], "damage": data["damage"] })
	EventBus.posted.connect(listener)
	for _shot in 3:
		var health: float = walker.health
		struck.clear()
		_puppet_of(world, &"shooter").shoot()
		await t.seconds(0.6)
		shots.append(
			{
				"hit": struck[0] if not struck.is_empty() else {},
				"lost": health - walker.health,
				"torso": walker.anatomy.pose.torso_angle,
			},
		)
	EventBus.posted.disconnect(listener)
	return shots


func _puppet_of(world: Node2D, id: StringName) -> Node:
	return TestContext.controller_of(world.actors[id], &"walk_to")


## Whether any part of a disc of `radius` round `at` is seen: the centre or one of `RING` points.
func _reaches(view: PlayerView, at: Vector2, radius: float) -> bool:
	if _sees(view, at):
		return true
	for i in RING:
		if _sees(view, at + Vector2.from_angle(float(i) / RING * TAU) * radius):
			return true
	return false


## Whether `point` is in the view's cone or bubble, by the even-odd rule on the polygons: the test's
## own copy of the rule, so it does not judge `SeenArea` by itself.
func _sees(view: PlayerView, point: Vector2) -> bool:
	for polygon: PackedVector2Array in [view.cone(), view.bubble()]:
		if polygon.size() < 3:
			continue
		var inside := false
		var previous := polygon[polygon.size() - 1]
		for corner in polygon:
			if (corner.y > point.y) != (previous.y > point.y):
				var slope := (point.y - previous.y) / (corner.y - previous.y)
				if point.x < previous.x + slope * (corner.x - previous.x):
					inside = not inside
			previous = corner
		if inside:
			return true
	return false
