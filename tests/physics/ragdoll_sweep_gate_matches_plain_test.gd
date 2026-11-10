extends GameTest
## The humanoid ragdoll's whole-body broadphase may skip point sweeps only when one substep query
## covers every point's start, predicted end and radius and finds no wall. Real character deaths in
## the open, beside a wall, touching furniture and under a later blast are replayed from fixed seeds
## against the ungated solver; every point must match on every frame. Query and sweep counters prove
## both the open-space skip and the exact fallback were exercised.

const CharacterScene := preload("res://scenes/character/character_base.tscn")
const FRAMES := 150
const BLAST_FRAME := 55
const SCENARIOS := [
	{ "name": "open", "at": Vector2(300, 230), "blast": false, "blow": Vector2.RIGHT },
	{ "name": "wall", "at": Vector2(24, 250), "blast": false, "blow": Vector2.LEFT },
	{ "name": "touching", "at": Vector2(480, 250), "blast": false, "blow": Vector2.RIGHT },
	{ "name": "blast", "at": Vector2(300, 400), "blast": true, "blow": Vector2.RIGHT },
]


func describe() -> Dictionary:
	return {
		"name": "The ragdoll sweep gate matches the plain solver",
		"description": "Seeded humanoid deaths through Character.take_hit keep every ragdoll point "
			+ "identical with the whole-substep broadphase, including a blast-woken fall.",
		"tags": ["ragdoll", "death", "broadphase"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 550))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.switch(&"audio.sound", false)
	s.object(&"chair", "chair", Vector2(480, 250))


## The fall's chance (the world's stream) and the blood's (the global one) both start from `at`'s
## seed.
func _reseed(t: TestContext, at: Vector2) -> void:
	var seeded := 192_015 + int(at.x) * 10 + int(at.y)
	seed(seeded)
	WorldRng.of(t.world).seed = seeded


func run(t: TestContext) -> void:
	for scenario in SCENARIOS:
		var at: Vector2 = scenario["at"]
		_reseed(t, at)
		var fast: Dictionary = await _fall(t, at, true, scenario["blast"], scenario["blow"])
		_reseed(t, at)
		var plain: Dictionary = await _fall(t, at, false, scenario["blast"], scenario["blow"])
		if not t.require(
				not fast["samples"].is_empty() and not plain["samples"].is_empty(),
				"%s: both characters died and built humanoid ragdolls" % scenario["name"],
		):
			continue
		t.check(
			fast["samples"] == plain["samples"],
			"%s: every point matches the ungated fall on every frame" % scenario["name"],
		)
		if scenario["name"] == "open":
			t.check(
				fast["queries"] != null and fast["queries"] > 0,
				"open: the whole-substep broadphase ran",
			)
			t.check(fast["sweeps"] == 0, "open: every per-point wall sweep was skipped")
		elif scenario["name"] in ["wall", "touching"]:
			t.check(
				fast["sweeps"] != null and fast["sweeps"] > 0,
				"%s: possible geometry kept the exact point sweeps" % scenario["name"],
			)
		if scenario["name"] == "blast":
			t.check(fast["blast_queries"] > 0, "the blast-woken substep ran the broadphase")
			t.check(fast["blast_sweeps"] == 0, "the clear blast-woken substep skipped point sweeps")


## Kill a real unarmed humanoid at `at`, optionally blast it during the fall, and sample every
## point. With `gated` false, disable only the new fast path when the solver exposes it; on the old
## solver this naturally leaves the plain path and fails the observable query assertions above.
func _fall(
	t: TestContext, at: Vector2, gated: bool, blast: bool, blow: Vector2
) -> Dictionary:
	var character := CharacterScene.instantiate()
	character.start_slot = ItemRegistry.UNARMED_SLOT
	t.world.add_child(character)
	character.global_position = at
	await t.frames(2)
	var hit := HitInfo.new()
	hit.position = at
	hit.normal = Vector2.LEFT
	hit.direction = blow
	hit.damage = 1000.0
	hit.height = 50.0
	character.take_hit(hit)
	if not character.is_dead or character.anatomy.ragdoll == null:
		character.free()
		return { "samples": [], "queries": null, "sweeps": null }
	var body: Ragdoll = character.anatomy.ragdoll.body
	var scratch: Object = body.get(&"_scratch")
	if not gated and scratch != null and scratch.get(&"sweep_gate") != null:
		scratch.set(&"sweep_gate", false)
	var samples: Array[PackedVector3Array] = []
	var blast_counts: Array = []
	for frame in FRAMES:
		var points := PackedVector3Array()
		for i in body.point_count():
			points.append(body.point(i))
		samples.append(points)
		if blast and frame == BLAST_FRAME:
			blast_counts = [scratch.get(&"broadphase_queries"), scratch.get(&"point_sweeps")]
			character.blast_push(at - Vector2(100.0, 0.0), 500.0)
		await t.frames(1)
		if blast and frame == BLAST_FRAME + 1:
			blast_counts = [
				scratch.get(&"broadphase_queries") - blast_counts[0],
				scratch.get(&"point_sweeps") - blast_counts[1],
			]
	var result := {
		"samples": samples,
		"queries": scratch.get(&"broadphase_queries") if scratch != null else null,
		"sweeps": scratch.get(&"point_sweeps") if scratch != null else null,
		"blast_queries": blast_counts[0] if not blast_counts.is_empty() else 0,
		"blast_sweeps": blast_counts[1] if not blast_counts.is_empty() else 0,
	}
	character.free()
	return result
