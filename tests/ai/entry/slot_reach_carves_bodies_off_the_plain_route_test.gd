extends GameTest
## A hold's verdict on its slot (`AgentEntry.slot_reach`) carves the bodies near the plain route
## first (`AgentEntry.BODY_CORRIDOR`), and then, when the way round leaves that corridor, the
## bodies it passes (#194 perf-ai2). Two rooms are joined by two doorways: the walk's plain route
## goes through the near one; a body stands in the far one, more than the corridor from the plain
## route. A body in the near doorway alone leaves the far one, and the slot is reached (1); one in
## each shuts both ways, and the slot is not (0), which a verdict that never carved the far body
## answers wrongly.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const WEST := Rect2(0, 0, 600, 400)
const EAST := Rect2(600, 0, 300, 400)
const NEAR_DOOR := Vector2(600, 150)
const FAR_DOOR := Vector2(600, 350)
const FROM := Vector2(100, 200)
const SLOT := Vector2(700, 200)


func describe() -> Dictionary:
	return {
		"name": "A hold's verdict carves a body in the other doorway, off the plain route",
		"description": "Two doorways between two rooms, a body in each: the verdict on a slot "
			+ "beyond them is that it cannot be reached, though the far body stands further than "
			+ "the corridor from the plain route; with a body in the near doorway only it is.",
		"tags": ["ai", "entry", "navigation", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "kitchen", "rect": EAST },
	], [{ "pos": NEAR_DOOR, "width": 60.0 }, { "pos": FAR_DOOR, "width": 60.0 }])
	s.von_down()


func run(t: TestContext) -> void:
	var map := NavWorld.map_of(t.world)
	await t.until(func() -> bool: return NavBuilder.ready(map), 20.0)
	if not t.require(
		NavBuilder.planning_region(map) != null, "premise: the map has a planning region to carve",
	):
		return
	var to := NavBuilder.snap(map, SLOT)
	var plain := NavBuilder.route(map, FROM, to)
	if not t.require(plain.size() >= 2, "premise: a plain route runs from the start to the slot"):
		return
	var far_off := true
	for i in range(1, plain.size()):
		far_off = far_off and Geometry2D.get_closest_point_to_segment(
			FAR_DOOR, plain[i - 1], plain[i],
		).distance_to(FAR_DOOR) > AgentEntry.BODY_CORRIDOR
	t.require(far_off, "premise: the far doorway lies further than the corridor from the plain way")
	var entry := AgentEntry.new()
	var one := await _verdict(t, entry, map, to, [NEAR_DOOR])
	t.check(one == 1, "a body in the near doorway leaves the far one: reached (%d)" % one)
	var both := await _verdict(t, entry, map, to, [NEAR_DOOR, FAR_DOOR])
	t.check(both == 0, "a body in each doorway shuts both ways: not reached (%d)" % both)


## The verdict `entry` gives on bodies `bodies`, asked every frame until its map is up.
func _verdict(
	t: TestContext, entry: RefCounted, map: RID, to: Vector2, bodies: Array,
) -> int:
	var verdict := -1
	var waited := 0
	while verdict == -1 and waited < 240:
		verdict = entry.slot_reach(FROM, to, map, bodies)
		if verdict == -1:
			await t.frames(1)
			waited += 1
	return verdict
