extends GameTest
## LD27 (`docs/leadership.md`), ticket #95: a match's invader team starts beside the front door,
## against the house's outside wall on one side of the doorway, where the wall hides it from inside.
## Its group point (the point its members pack round) stands 120 px along the wall from the front
## door's centre, past the jamb, and `spawn_clearance` (20 px) out from the wall: within 150 px of
## the door's centre and out of the doorway's straight strip. Every member stands out of that strip
## and within two of the rings the team packs in of that point (a street lamp beside the door, which
## world-gen keeps 140 px or more from it, can push a member out to the second), outside the house's
## rooms and within 150 px of the door's centre plus those rings. Across the sweep the team starts
## on both sides of the door (the side is drawn from the house seed). And no defender knows a
## hostile on the first physics frame after placement.
##
## The doorway's frame (its centre, width, the wall's axis and the way out) is the test's own
## (`tests/_ai/slots_probe.gd`, read off the house's rooms and openings), and the group point is
## laid from the rule's own numbers on the side of the door the members stand on, so the rule is not
## read back from the code under test. Swept over every generated floorplan
## (`HouseDefinitions.get_all()`) with fixed seeds, each match built whole as Main builds one
## (`MatchBuilder.build`) in a world of its own (`MainProbe.viewport`: its own physics space and
## navigation maps). Von is down, so the NPCs hold steady.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
## How many seeds (1, 2, ...) each floorplan is built with (the seed pins the plan's layout and the
## side of the door the team takes).
const SEEDS := 8
## How far (px) along the wall from the front door's centre the group point stands, and how far
## out from the wall (the match's `spawn_clearance`).
const SIDE_OFFSET := 120.0
const CLEARANCE := 20.0
## How near (px) the front door's centre the group point stands.
const NEAR_DOOR := 150.0
## How far apart (px) the rings a team packs in lie (twice the match's `spawn_clearance`), and how
## many of them a member may stand out in: four bodies fill the first ring beside the wall, a second
## allows for a street lamp or a piece in the way.
const RING := 40.0
const RINGS := 2
## Rounding slack (px) for a member placed exactly on its ring.
const ROUNDING := 0.01
const INVADERS := 4
const DEFENDERS := 3


func describe() -> Dictionary:
	return {
		"name": "A match's invader team starts beside the front door",
		"description": "Over every floorplan and several seeds, the invader team starts against "
			+ "the outside wall beside the front door, out of the doorway's straight line, on "
			+ "either side across the seeds, and no defender knows a hostile on the first frame.",
		"tags": ["setup", "match", "spawn", "squad", "sweep"],
		"timeout": 300.0,
		"allowed_logs": [
			"Navigation map synchronization error",
			"NavigationPolygon polygon convex partition failed",
		],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 300))
	s.von_down()


func run(t: TestContext) -> void:
	var matches := 0
	var sides := {}
	for plan in HouseDefinitions.get_all():
		for house_seed in range(1, SEEDS + 1):
			var label := "%s#%d" % [plan, house_seed]
			var viewport := MainProbe.viewport(t)
			var world := Node2D.new()
			world.name = "World"
			viewport.add_child(world)
			var spec := MatchBuilder.spec({
				"seed": house_seed,
				"plan": String(plan),
				"defenders": { "count": DEFENDERS },
				"invaders": { "count": INVADERS },
			})
			var handle: Dictionary = await MatchBuilder.build(spec, world)
			if not t.require(not handle.is_empty(), "the %s match is built" % label):
				return
			await t.frames(1)
			matches += 1
			var side := _check(t, label, handle)
			if side != 0:
				sides[side] = true
			viewport.queue_free()
			await t.frames(1)
	t.check(matches > 0, "the sweep built some matches (%d)" % matches)
	t.check(
		sides.has(1) and sides.has(-1),
		"across the sweep the team starts on both sides of the front door (%s)" % str(sides.keys()),
	)


## The invader team of match `handle` beside its front door, and no defender knowing a hostile.
## Returns the side of the door (1 / -1 along the wall) the members stand on (their mean), 0 when
## the premise fails.
func _check(t: TestContext, label: String, handle: Dictionary) -> int:
	var rooms: Array = handle["rooms"]
	var front := {}
	for o: Dictionary in handle["openings"]:
		if o.get("front", false):
			front = Slots.frame(o, String(o["rooms"][0]), rooms)
	var invaders: Array = []
	var defenders: Array = []
	for c: Node2D in handle["combatants"]:
		(invaders if c.get("faction") == &"invader" else defenders).append(c)
	if not t.require(
			not front.is_empty()
				and invaders.size() == INVADERS
				and defenders.size() == DEFENDERS,
			"%s: premise: a front door, %d invaders and %d defenders placed (%d, %d)"
				% [label, INVADERS, DEFENDERS, invaders.size(), defenders.size()],
	):
		return 0
	var door: Vector2 = front["pos"]
	var along: Vector2 = front["along"]
	var mean := Vector2.ZERO
	for c: Node2D in invaders:
		mean += c.global_position
	mean /= invaders.size()
	var side := 1 if (mean - door).dot(along) >= 0.0 else -1
	var point := door + along * side * SIDE_OFFSET + (front["out"] as Vector2) * CLEARANCE
	var members := str(invaders.map(func(c): return (c as Node2D).global_position.round()))
	var where := "%s: the group point %s (door %s, members at %s)" % [
		label,
		str(point.round()),
		str(door),
		members,
	]
	for c: Node2D in invaders:
		var p := c.global_position
		var at := "%s: %s at %s" % [where, c.name, str(p.round())]
		t.check(
			absf((p - door).dot(along)) > float(front["width"]) / 2.0,
			("%s is out of the doorway's straight strip: %.0f px along the wall, past the jamb "
					+ "at %.0f")
				% [at, absf((p - door).dot(along)), float(front["width"]) / 2.0],
		)
		t.check(
			p.distance_to(point) <= RING * RINGS + ROUNDING,
			"%s packs within %.0f px of the group point %s (%.0f px)"
				% [at, RING * RINGS, str(point.round()), p.distance_to(point)],
		)
		t.check(
			not rooms.any(func(r): return (r["rect"] as Rect2).has_point(p)),
			"%s starts outside the house's rooms" % at,
		)
		t.check(
			p.distance_to(door) <= NEAR_DOOR + RING * RINGS + ROUNDING,
			"%s starts within %.0f px of the front door's centre (%.0f px)"
				% [at, NEAR_DOOR + RING * RINGS, p.distance_to(door)],
		)
	for c: Node2D in defenders:
		var brain := TestContext.controller_of(c)
		var known: Array = brain.debug_state().get("contacts", []).filter(
			func(k): return k["hostile"],
		)
		t.check(
			known.is_empty(),
			"%s: %s knows no hostile on the first frame (knows %s)" % [label, c.name, known],
		)
	return side
