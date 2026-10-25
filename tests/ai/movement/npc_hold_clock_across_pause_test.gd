extends GameTest
## Issue #53 / ticket #65, `docs/leadership.md` LD1: the hold clock runs on game time. A teammate
## standing in the only doorway holds the walker's walk (the map of
## `npc_waits_at_doorway_held_by_teammate`). The teammate is nudged `NUDGE_PX` px on, so it reads as
## moving for a few frames and the hold ends; the tree is then paused (as the human leader's command
## menu pauses it) for `PAUSE_S` s of wall time, longer than `HOLD_GAP`, and once it runs again the
## teammate is at rest and the same hold begins again, the walker within a stride of where it stood.
## No game time passed in the pause, so the hold is the one it was: its clock (`held_for`, what
## `held_time` reads) carries on from where it was, and does not start over.
##
## Scripted Von (SEARCH, the east room). Switches and props: the teammate is a puppet that stands
## still and cannot die; nothing else is changed. A defender, so the walk is a plain move and not an
## invader's tactical entry.

const Order := preload("res://tests/_ai/order_probe.gd")
const WEST := Rect2(0, 0, 400, 500)
const EAST := Rect2(400, 0, 400, 500)
const DOOR := Vector2(400, 250)
## The walker starts where a walk held by the teammate stands (`Locomotion.STOP_GAP`, 56 px short of
## it), so its hold begins where it stands and it stands still through it.
const START := Vector2(345, 250)
## Locomotion's same-hold rule (the spec's numbers, so the test checks them and not the code): a
## hold that begins again within `HOLD_GAP` s of game time of the last ending, the walker within
## `HOLD_MOVED` px of where that one began, keeps its clocks.
const HOLD_GAP := 0.5
const HOLD_MOVED := 16.0
## How long (s held) the walk stands before the nudge: well short of its first re-plan (0.75 s),
## which would start a new walk.
const HELD_BEFORE := 0.3
## How far (px) the teammate is moved on along the walk, in one frame: it reads as moving (40 px/s
## or faster) for a few frames.
const NUDGE_PX := 6.0
## Wall seconds the tree stays paused: longer than `HOLD_GAP`.
const PAUSE_S := 1.0


func describe() -> Dictionary:
	return {
		"name": "A hold's clock is not restarted by a pause",
		"description": "A walk held by a teammate in a doorway stops being held a moment, the game "
			+ "is paused longer than the same-hold gap, and the same hold begins again: its clock "
			+ "carries on (LD1).",
		"tags": ["ai", "navigation", "character", "doorway", "leadership", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "kitchen", "rect": EAST },
	], [{ "pos": DOOR, "width": 70.0 }])
	s.von_script([{ "pick": "search" }, { "pick": "room_east" }])
	s.actor(&"walker", &"defender", START)
	s.actor(&"mate", &"puppet", DOOR, { "faction": &"household", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var mate := t.actor(&"mate")
	var brain := t.controller(&"walker", &"current_act")
	var loco := func() -> Dictionary: return brain.debug_state().get("loco", {})
	var held := func(): return String(loco.call().get("way", "")) == "held"
	var hold_from := await _stands_held(t, walker, brain, loco, held)
	if hold_from == Vector2.INF:
		return
	var walks := int(brain.debug_state().get("decisions", 0))
	var before := await _nudge(t, mate, loco, held)
	if before < 0.0:
		return
	var left_at := t.time
	await Order.pause_for(t, PAUSE_S)
	if not t.require(
			await t.until(held, 0.4),
			"premise: the same hold begins again once the game runs (%s)" % loco.call(),
	):
		return
	if not _same_hold(
			t,
			t.time - left_at,
			walker.global_position.distance_to(hold_from),
			int(brain.debug_state().get("decisions", 0)) == walks,
	):
		return
	var now := float(loco.call().get("held_for", 0.0))
	t.check(
		now >= before,
		("its clock carries on through the pause (%.2f s held before the hold ended, %.2f s once "
				+ "it began again; %.0f wall s paused)") % [before, now, PAUSE_S],
	)


# Waits for the walk to be held short of the teammate and the walker to stand still in it; where
# the hold began, or Vector2.INF when a premise fails.
func _stands_held(
		t: TestContext,
		walker: Node,
		brain: Node,
		loco: Callable,
		held: Callable,
) -> Vector2:
	if not t.require(
			await t.until(held, 8.0),
			"premise: the walker's walk is held short of the teammate in the doorway (%s, %s)"
				% [loco.call(), brain.current_act()],
	):
		return Vector2.INF
	var hold_from: Vector2 = walker.global_position
	var st := { "last": walker.global_position, "speed": INF }
	var standing_held := func():
		st["speed"] = (walker.global_position.distance_to(st["last"])
				* Engine.physics_ticks_per_second)
		st["last"] = walker.global_position
		return (held.call()
				and float(loco.call().get("held_for", 0.0)) >= HELD_BEFORE
				and float(st["speed"]) < 1.0)
	if not t.require(
			await t.until(standing_held, 12.0),
			("premise: the walker stands still, its walk held short of the teammate in the doorway "
					+ "(%s, %s)") % [loco.call(), brain.current_act()],
	):
		return Vector2.INF
	return hold_from


# Nudges the teammate on along the walk until the hold ends; how long the walk had been held then,
# or -1 when the hold does not end.
func _nudge(t: TestContext, mate: Node, loco: Callable, held: Callable) -> float:
	var before := float(loco.call().get("held_for", 0.0))
	mate.global_position += Vector2(NUDGE_PX, 0)
	var ended := false
	for i in 10:
		await t.frames(1)
		if not held.call():
			ended = true
			break
		before = float(loco.call().get("held_for", 0.0))
	if not t.require(
			ended,
			"premise: the nudged teammate reads as moving and the hold ends (%s)" % loco.call(),
	):
		return -1.0
	return before


# Whether the hold begun again is the same one: `again` s of game time after it ended, `moved` px
# from where it began, on the same walk (`same_walk`).
func _same_hold(t: TestContext, again: float, moved: float, same_walk: bool) -> bool:
	return t.require(
		again <= HOLD_GAP
			and moved <= HOLD_MOVED
			and same_walk,
		("premise: it is the same hold, begun again %.2f s of game time after it ended, %.1f "
				+ "px from where it began, on the same walk") % [again, moved],
	)
