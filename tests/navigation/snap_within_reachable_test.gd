extends GameTest
## Interface 9 (`NavBuilder.snap_within`, issue #183): a point snapped within a room is on floor of
## that room a route from the given point reaches. Where furniture walls the room's corner off into
## a pocket of its own, the snap is not in the pocket but on the doorway's side of it; where no
## point of the rectangle is reached at all, it is the given point's own snap.
##
## Generated house seed 10: the great room behind the front doorway (0, 0), furniture by its
## south-east corner shutting a pocket of floor there off from the doorway (a route from the doorway
## into it ends on the street outside the wall). The given point is the room's floor just in from
## the front doorway.

const SEED := 10
const ROOM := Rect2(-330, -440, 660, 440)
## In the walled-off pocket by the great room's south-east corner (on the map, unreached).
const POCKET := Vector2(290, -40)
## Just in from the front doorway, on the great room's floor.
const THRESHOLD := Vector2(0, -24)
## A rectangle round the pocket alone: none of its floor is reached from the threshold.
const POCKET_ONLY := Rect2(276, -54, 28, 28)


func describe() -> Dictionary:
	return {
		"name": "A point snapped within a room is on floor its doorway reaches",
		"description": "In a generated house whose room has a corner walled off by furniture, "
			+ "snap_within keeps the corner out of the pocket, and falls back to the given point.",
		"tags": ["navigation", "entry"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.house(SEED)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var map: RID = t.world.get_world_2d().navigation_map
	var from := NavBuilder.snap(map, THRESHOLD)
	var pocket_on_map := NavBuilder.snap(map, POCKET).distance_to(POCKET) < 2.0
	var into_pocket := NavBuilder.route(map, from, POCKET)
	if not t.require(
			ROOM.has_point(from) and pocket_on_map
				and into_pocket[into_pocket.size() - 1].distance_to(POCKET) > 30.0,
			"premise: the pocket is on the map but unreached from the doorway (route ends %s)"
				% into_pocket[into_pocket.size() - 1].round(),
	):
		return
	var p := NavBuilder.snap_within(map, POCKET, ROOM, from)
	var to_p := NavBuilder.route(map, from, p)
	t.check(
		ROOM.has_point(p) and to_p[to_p.size() - 1].distance_to(p) <= 2.0,
		"the pocket's corner snaps to floor in the room the doorway reaches (%s, route ends %s)"
			% [p.round(), to_p[to_p.size() - 1].round()],
	)
	var fallback := NavBuilder.snap_within(map, POCKET, POCKET_ONLY, from)
	t.check(
		fallback.distance_to(from) <= 2.0,
		"with no reached floor in the rectangle it is the given point's own snap (%s, not %s)"
			% [fallback.round(), from.round()],
	)
