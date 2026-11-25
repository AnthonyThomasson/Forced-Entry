extends GameTest
## An NPC senses and acts one frame in two (`npc_pace.gd`, `docs/gaze-and-fire.md` "The beat"): over
## a stretch of frames with nothing to wake it, it runs half of them as beats and coasts the rest,
## the decision job and the queued events running on every frame; a hit on it runs its beat that
## very frame, off its turn; a flash-blinding keeps it on every frame until its sight returns.

const AT := Vector2(300, 200)
## Frames the quiet case counts.
const QUIET := 20
const HALF := 10


func describe() -> Dictionary:
	return {
		"name": "An NPC senses and acts one frame in two, and a hit wakes it at once",
		"description": "Quiet, an invader runs half its frames as beats and coasts the others; a "
			+ "hit on it runs its beat on the frame the hit lands, off its turn.",
		"tags": ["ai", "pace", "scripted"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 400))
	s.von_script([])
	s.switch(&"ai.callouts", false)
	s.actor(&"npc", &"invader", AT, { "movement:speed": 0.0, "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var pace: RefCounted = t.controller(&"npc", &"debug_state").get("_reflexes").pace
	await t.frames(4)
	var beats: int = pace.beats
	var coasts: int = pace.coasts
	await t.frames(QUIET)
	t.expect_eq(pace.beats - beats, HALF, "quiet, it beats on every second frame")
	t.expect_eq(pace.coasts - coasts, HALF, "and coasts on the others")
	# A frame off its turn: wait until the next frame is a coast, then hit it.
	await t.frames(1)
	var coasting: bool = pace.coasts > coasts + HALF
	while not coasting:
		var before: int = pace.coasts
		await t.frames(1)
		coasting = pace.coasts > before
	var woken: int = pace.beats
	EventBus.post(
		&"hit",
		{
			"position": AT, "direction": Vector2.LEFT, "damage": 1.0,
			"attacker": null, "victim": npc,
		},
	)
	await t.frames(1)
	t.expect_eq(pace.beats - woken, 1, "a hit on it runs its beat on the frame it lands, off turn")
	# A grenade coming down near it wakes it the same way, off its turn.
	await t.frames(2)
	coasting = false
	while not coasting:
		var cold: int = pace.coasts
		await t.frames(1)
		coasting = pace.coasts > cold
	var again: int = pace.beats
	EventBus.post(
		&"grenade",
		{ "position": AT + Vector2(80, 0), "kind": &"frag", "stage": &"rest" },
	)
	await t.frames(1)
	t.expect_eq(pace.beats - again, 1, "a grenade coming down runs its beat on the frame it lands")
