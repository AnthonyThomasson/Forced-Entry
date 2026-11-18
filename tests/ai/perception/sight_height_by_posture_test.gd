extends GameTest
## Sight is a 3D eye ray from the viewer's eye (its posture's height) to a few points on the target
## (head, chest, hips at its posture), seen if any one is clear (#194 D9, `docs/gaze-and-fire.md`
## G1, `docs/cover-and-stance.md`): a standing NPC looks over a table and sees a standing body close
## behind a sofa, but not a ducked one (the sofa's back, 38 px, hides a body ducked right behind it
## from an eye 69 px up, 400 px away); a ducked NPC cannot look over a kitchen counter (38 px) at
## the standing body beyond it, and sees it once it stands. Von is down: the NPCs hold their posts.
##
## The numbers are the spec's (`BodyHeights`' metres at 42.3 px a metre, the 3D meshes' tops), kept
## here on their own.

const VIEWER_AT := Vector2(150, 250)
## A dining table (31 px) 150 px along, a standing target 60 px behind it.
const TABLE_AT := Vector2(350, 130)
const BEHIND_TABLE := Vector2(470, 100)
## A sofa whose back faces the viewer, centred 450 px along, 50 px deep: a target 20 px past its far
## face (the east face at x 625).
const SOFA_AT := Vector2(600, 250)
const BEHIND_SOFA := Vector2(645, 250)
## A kitchen counter (38 px, 100 by 50) and the ducked viewer 25 px before it, the target 300 px on.
const COUNTER_AT := Vector2(335, 250)
const DUCKED_AT := Vector2(255, 250)
const BEYOND_COUNTER := Vector2(560, 250)
const IN_VIEW_FRAMES := 12


func describe() -> Dictionary:
	return {
		"name": "Sight follows the posture of the viewer and of the viewed",
		"description": "A standing NPC sees a standing hostile behind a table and one standing "
			+ "behind a sofa but not a ducked one; a ducked NPC cannot see over a counter at a "
			+ "standing hostile and sees it once it stands.",
		"tags": ["ai", "vision", "posture", "3d", "heights", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 500))
	s.von_down()
	# The test sets the postures itself: an NPC holding with a hostile known ducks on its own (A1).
	s.switch(&"ai.posture", false)
	s.object(&"table", "table", TABLE_AT)
	s.object(&"sofa", "sofa", SOFA_AT, { "facing": Vector2.RIGHT, "rotated": true })
	s.object(&"counter", "kitchen_counter", COUNTER_AT)
	# Unarmed (no rounds, no magazines): an NPC with a gun that knows a hostile fires by rising over
	# the counter (docs/cover-and-stance.md P6) and so would see over it; this tests the ducked eye.
	s.actor(
		&"inv",
		&"invader",
		VIEWER_AT,
		{
			"movement:speed": 0.0,
			"facing": Vector2.RIGHT,
			"start_slot": 2,
			"inventory:start_rounds": 0,
			"ammo:spare_magazine_types": [],
		},
	)
	s.actor(&"over_table", &"puppet", BEHIND_TABLE, { "max_health": 100_000.0 })
	s.actor(&"over_sofa", &"puppet", BEHIND_SOFA, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var brain := t.controller(&"inv", &"known_contacts_for_display")
	if not t.require(
			await t.until(
				func(): return _sees(brain, "over_table") and _sees(brain, "over_sofa"),
				3.0,
			),
			"premise: a standing NPC sees a standing body behind a table and one behind a sofa",
	):
		return
	var ducked := t.actor(&"over_sofa")
	t.require(ducked.movement.set_posture(&"crouch"), "premise: the hostile can duck")
	var lost := await _frames_until(t, func(): return not _sees(brain, "over_sofa"))
	t.check(
		lost <= IN_VIEW_FRAMES,
		"a body ducked right behind the sofa is lost from sight (took %d frames)" % lost,
	)
	t.check(_sees(brain, "over_table"), "the standing body behind the table is still seen")
	await t.frames(30)
	await t.until(func(): return ducked.movement.set_posture(&"stand"), 3.0)
	var back := await _frames_until(t, func(): return _sees(brain, "over_sofa"))
	t.check(back <= IN_VIEW_FRAMES, "it is seen again as it stands up (took %d frames)" % back)
	await _ducked_viewer(t, brain)


## The NPC ducks next to a counter, with a standing hostile beyond it: it cannot look over the
## counter; standing it can.
func _ducked_viewer(t: TestContext, brain: Node) -> void:
	var npc := t.actor(&"inv")
	var target := t.actor(&"over_table")
	target.global_position = BEYOND_COUNTER
	npc.global_position = DUCKED_AT
	await t.frames(5)
	t.require(
		await t.until(func(): return _sees(brain, "over_table"), 3.0),
		"premise: standing at the counter the NPC sees the hostile beyond it",
	)
	t.require(npc.movement.set_posture(&"crouch"), "premise: the NPC can duck")
	var lost := await _frames_until(t, func(): return not _sees(brain, "over_table"))
	t.check(
		lost <= IN_VIEW_FRAMES,
		"ducked at the counter the NPC cannot see over it (took %d frames)" % lost,
	)
	t.check(npc.movement.posture() == &"crouch", "premise: it stayed ducked")
	await t.until(func(): return npc.movement.set_posture(&"stand"), 3.0)
	var back := await _frames_until(t, func(): return _sees(brain, "over_table"))
	t.check(back <= IN_VIEW_FRAMES, "standing up it sees over the counter (took %d frames)" % back)


## Physics frames until `cond` holds (one more than the limit when it never does).
func _frames_until(t: TestContext, cond: Callable) -> int:
	for frames in range(1, IN_VIEW_FRAMES + 1):
		await t.frames(1)
		if cond.call():
			return frames
	return IN_VIEW_FRAMES + 1


## Whether the NPC sees `who` on this tick.
func _sees(brain: Node, who: String) -> bool:
	for c in brain.known_contacts_for_display():
		if str(c["name"]) == who:
			return c["visible"]
	return false
