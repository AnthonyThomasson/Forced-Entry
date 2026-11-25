extends GameTest
## An NPC senses and acts one frame in two (`npc_pace.gd`, `docs/gaze-and-fire.md` "The beat"): over
## a stretch of frames with nothing to wake it, it runs half of them as beats and coasts the rest,
## the decision job and the queued events running on every frame; a hit on it runs its beat that
## very frame, off its turn, and so does each other wake: a hit near it on another victim, a
## grenade or an explosion event, an order through the squad. What does not wake it (a hit out of
## earshot's reach, nothing at all) leaves the next frame a coast; a flash-blinding keeps it on
## every frame while it lasts and for one beat after (its sight returning re-decides it).
## `Behavior.gait.needs_every_frame` clause by clause is `ai/gait_every_frame_suite`.

const AT := Vector2(300, 200)
## Frames the quiet case counts.
const QUIET := 20
const HALF := 10
const Order := preload("res://tests/_ai/order_probe.gd")


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
	s.actor(&"mate", &"puppet", Vector2(120, 330), { "faction": &"invader" })
	s.actor(&"lead", &"puppet", Vector2(120, 80), { "faction": &"invader" })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var pace: RefCounted = t.controller(&"npc", &"debug_state").get("_reflexes").pace
	await t.frames(4)
	var beats: int = pace.beats
	var coasts: int = pace.coasts
	await t.frames(QUIET)
	t.expect_eq(pace.beats - beats, HALF, "quiet, it beats on every second frame")
	t.expect_eq(pace.coasts - coasts, HALF, "and coasts on the others")
	# Control: the frame after a beat is a coast when nothing wakes it.
	await _after_a_beat(t, pace)
	var quiet: int = pace.coasts
	await t.frames(1)
	t.expect_eq(pace.coasts - quiet, 1, "after a beat, nothing waking it, the next is a coast")
	# A hit far off, on another, is no wake.
	await _after_a_beat(t, pace)
	var far: int = pace.coasts
	_hit(AT + Vector2(600, 0), t.actor(&"mate"))
	await t.frames(1)
	t.expect_eq(pace.coasts - far, 1, "a hit far off on another is no wake: the next is a coast")
	await _wakes(t, pace, "a hit on it", func(): _hit(AT, npc))
	var mate := t.actor(&"mate")
	await _wakes(
		t,
		pace,
		"a hit near it on another victim",
		func(): _hit(AT + Vector2(60, 0), mate),
	)
	await _wakes(
		t, pace, "a grenade coming down",
		func(): EventBus.post(
			&"grenade", { "position": AT + Vector2(80, 0), "kind": &"frag", "stage": &"rest" },
		),
	)
	await _wakes(
		t, pace, "an explosion",
		func(): EventBus.post(
			&"explosion", { "position": AT + Vector2(200, 0), "kind": &"frag", "attacker": null },
		),
	)
	await _blinded(t, pace, npc)
	await _ordered(t, pace, npc)


## An order through the squad reaches it whatever its turn.
func _ordered(t: TestContext, pace: RefCounted, npc: Node) -> void:
	var squad: Node = t.world.squad(&"invader")
	var request := { "kind": Order.DEFEND, "to": [npc], "pos": AT + Vector2(100, 0) }
	await _wakes(
		t,
		pace,
		"an order through the squad",
		func(): t.require(not Order.issue(squad, request).is_empty(), "the squad posts the order"),
	)


## A shot landing at `at`, from nobody it knows, on `victim`.
func _hit(at: Vector2, victim: Node) -> void:
	EventBus.post(
		&"hit",
		{
			"position": at, "direction": Vector2.LEFT, "damage": 1.0,
			"attacker": null, "victim": victim,
		},
	)


## Waits until the frame that has just run was a beat, so the next is the NPC's coast.
func _after_a_beat(t: TestContext, pace: RefCounted) -> void:
	var before: int = pace.beats
	await t.frames(1)
	while pace.beats == before:
		await t.frames(1)


## `wake` posted on a frame off the NPC's turn runs its beat on the very next frame: one more beat
## and no coast.
func _wakes(t: TestContext, pace: RefCounted, what: String, wake: Callable) -> void:
	await _after_a_beat(t, pace)
	var beats: int = pace.beats
	var coasts: int = pace.coasts
	wake.call()
	await t.frames(1)
	t.expect_eq(pace.beats - beats, 1, "%s runs its beat on the frame it comes, off turn" % what)
	t.expect_eq(pace.coasts - coasts, 0, "%s: that frame is no coast" % what)


## A flash-blinding, begun on each of the NPC's two phases: every frame a beat while it lasts, and
## the frame its sight returns too (the blindness ends before the NPC's tick of that frame, which
## the loop below counts as its last), whichever phase that falls on; then it coasts again.
func _blinded(t: TestContext, pace: RefCounted, npc: Node) -> void:
	for late in [0, 1]:
		await _after_a_beat(t, pace)
		await t.frames(late)
		npc.stun.take(0.3, 0.0)
		var beats: int = pace.beats
		var frames := 0
		while npc.stun.is_blind():
			await t.frames(1)
			frames += 1
		t.expect_eq(
			pace.beats - beats,
			frames,
			"blind, every frame a beat, and as its sight returns",
		)
		var coasts: int = pace.coasts
		await t.frames(QUIET)
		t.expect_eq(pace.coasts - coasts, HALF, "then it is on its turns again")
