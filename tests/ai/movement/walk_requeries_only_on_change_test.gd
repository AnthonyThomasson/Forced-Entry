extends GameTest
## Desired: a walking NPC asks the navigation server for a path every few frames
## (`tuning.pace.reask_frames`), not every frame. The server scans every polygon of the map to place
## the start and the end of a path, so on a district's map (ten times a house's polygons) a query
## per walker per frame is the frame's biggest nav cost (perf/match_5v5_stress). A walk to a goal
## that stands keeps its path between asks; a long wait lets a walker that cuts a corner press into
## the wall (`ai/entry/stack_reach_garage_home_garage_exit`), so the wait is short. Premise: a
## defender sent across a bare arena by a scripted combat, advance, rush walk.

## Frames of straight walking counted.
const WALK_FRAMES := 120
## The most paths the agent may compute over them: one in three frames (it computed one every frame,
## 120).
const MOST_PATHS := 40


func describe() -> Dictionary:
	return {
		"name": "A walking NPC asks for a path every few frames",
		"description": "A defender walks a straight stretch of an arena: its navigation agent "
			+ "computes a path every few frames, not one a frame.",
		"tags": ["ai", "move", "navigation", "perf", "scripted"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3000, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "advance" }, { "pick": "rush" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"nav.rebake", false)
	s.actor(&"walker", &"defender", Vector2(200, 300))
	s.actor(&"far", &"puppet", Vector2(1500, 300), { "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var agent: NavigationAgent2D = walker.get_node("NavigationAgent2D")
	var brain := t.controller(&"walker", &"current_act")
	if not t.require(
			await t.until(func(): return String(brain.current_act()).contains("advance"), 10.0),
			"premise: the walker advances (%s)" % brain.current_act(),
	):
		return
	var paths := [0]
	agent.path_changed.connect(func(): paths[0] += 1)
	var from_x: float = walker.global_position.x
	await t.frames(WALK_FRAMES)
	t.require(walker.global_position.x > from_x + 100.0, "premise: it walks on (x %d to %d)"
			% [from_x, walker.global_position.x])
	t.check(paths[0] <= MOST_PATHS, "%d paths computed in %d frames of walking (at most %d)"
			% [paths[0], WALK_FRAMES, MOST_PATHS])
