extends GameTest
## LD27 (`docs/leadership.md`) and E18 (`docs/tactical-entry.md`), ticket #95: a match's invader
## team never starts in the view of the house's exterior doorways. No invader stands in the view of
## an exterior doorway (the front entrance or an exit): inside its wedge seen from the room
## behind it, 450 px deep, nor within 200 px of the doorway's centre. And no defender knows a
## hostile on the first physics frame after placement.
##
## The wedge is the test's own copy of the rule (`tests/_ai/door_view_probe.gd`, `View.polygon`, a
## doorway framed by `tests/_ai/slots_probe.gd`), so the spec is not read back from the code under
## test. Swept over every generated floorplan (`HouseDefinitions.get_all()`) with fixed seeds, each
## match built whole as Main builds one (`MatchBuilder.build`) in a world of its own
## (`MainProbe.viewport`: its own physics space and navigation maps). Von is down,
## so the NPCs hold steady.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const View := preload("res://tests/_ai/door_view_probe.gd")
const Slots := preload("res://tests/_ai/slots_probe.gd")
## How many seeds (1, 2, ...) each floorplan is built with (the seed pins the plan's layout and the
## group's point): enough that some group's drawn point lies deep in a wedge, past the doorway's
## 200 px, as well as beside it.
const SEEDS := 20
## How deep (px) an exterior doorway's wedge reaches out of it.
const DEPTH := 450.0
## How close (px) to an exterior doorway's centre no invader may start.
const DOOR_CLEAR := 200.0
const INVADERS := 4
const DEFENDERS := 3


func describe() -> Dictionary:
	return {
		"name": "A match's invader team starts out of the exterior doorways' views",
		"description": "Over every floorplan and several seeds, no invader starts in an exterior "
			+ "doorway's wedge (450 px deep) or within 200 px of its centre, and no defender knows "
			+ "a hostile on the first frame after placement.",
		"tags": ["setup", "match", "spawn", "squad", "door_view", "sweep"],
		"timeout": 400.0,
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
			_check(t, label, handle)
			viewport.queue_free()
			await t.frames(1)
	t.check(matches > 0, "the sweep built some matches (%d)" % matches)


## Every invader of match `handle` out of every exterior doorway's view, and no defender knowing a
## hostile.
func _check(t: TestContext, label: String, handle: Dictionary) -> void:
	var rooms: Array = handle["rooms"]
	var doors: Array = []
	for o: Dictionary in handle["openings"]:
		if o.get("front", false) or o.get("exit", false):
			doors.append(Slots.frame(o, String(o["rooms"][0]), rooms))
	var invaders: Array = []
	var defenders: Array = []
	for c: Node2D in handle["combatants"]:
		(invaders if c.get("faction") == &"invader" else defenders).append(c)
	t.check(
		invaders.size() == INVADERS and defenders.size() == DEFENDERS,
		"%s: premise: %d invaders and %d defenders placed (%d, %d)"
			% [label, INVADERS, DEFENDERS, invaders.size(), defenders.size()],
	)
	for c: Node2D in invaders:
		var p := c.global_position
		for f: Dictionary in doors:
			var where := "%s: %s at %s" % [label, c.name, str(p.round())]
			t.check(
				not Geometry2D.is_point_in_polygon(p, View.polygon(f, DEPTH)),
				"%s starts out of the view of the exterior doorway %s" % [where, f["id"]],
			)
			t.check(
				p.distance_to(f["pos"]) >= DOOR_CLEAR,
				"%s starts %.0f px or more from the exterior doorway %s (%.0f px)"
					% [where, DOOR_CLEAR, f["id"], p.distance_to(f["pos"])],
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
