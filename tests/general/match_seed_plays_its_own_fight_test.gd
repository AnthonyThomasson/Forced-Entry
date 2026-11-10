extends GameTest
## A match's seed (`WorldRng`, interface 11) is what its fight plays by. Matches built from seed A
## twice and from seed B once, each in a world of its own (`MainProbe.viewport`) one after the other
## in one process: the two of seed A start their world's random stream alike (neither is the
## continuation of the other, nor of the global stream) and the seed B's starts otherwise, and the
## fight of seed B (where every NPC stands and how hurt it is after a second) is not the fight of
## seed A.
## (That one seed replays its fight exactly is the perf guards' fingerprint, not asserted here: the
## planning re-bake lands on a worker thread's own time.)

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SEED_A := 31
const SEED_B := 32
const PLAN := "garage_home"
## Physics frames each fight runs.
const FRAMES := 60
## Frames a freed world is given to settle before the next is built.
const SETTLE := 30


func describe() -> Dictionary:
	return {
		"name": "A match's seed gives its world's stream and its fight",
		"description": "Worlds built from one seed start their random stream alike, a world of "
			+ "another seed starts another and plays another fight.",
		"tags": ["general", "match", "worldrng", "determinism"],
		"timeout": 120.0,
		"allowed_logs": [
			"Navigation map synchronization error",
			"NavigationPolygon polygon convex partition failed",
		],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 300, 300))
	s.von_down()
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var streams: Array = []
	var fights: Array = []
	for seed_value in [SEED_A, SEED_A, SEED_B]:
		var played: Variant = await _play(t, seed_value)
		if not t.require(played != null, "the seed %d match is built" % seed_value):
			return
		streams.append(played["draws"])
		fights.append(played["fight"])
	t.expect_eq(streams[0], streams[1], "two worlds of one seed start their stream alike")
	t.check(streams[0] != streams[2], "a world of another seed starts another stream")
	t.check(fights[0] != fights[2], "a match of another seed plays another fight")


## The match of `seed_value`, built in a world of its own: `{ draws, fight }`, the first draws of
## its world's stream and where every combatant stands after `FRAMES` frames. Null when the world
## was torn down while building.
func _play(t: TestContext, seed_value: int) -> Variant:
	var viewport := MainProbe.viewport(t)
	var world := Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	var spec := MatchBuilder.spec({
		"seed": seed_value,
		"plan": PLAN,
		"defenders": { "count": 3 },
		"invaders": { "count": 3 },
	})
	var handle: Dictionary = await MatchBuilder.build(spec, world)
	if handle.is_empty():
		return null
	var rng := WorldRng.of(world)
	var draws := [rng.randi(), rng.randi(), rng.randi()]
	await t.frames(FRAMES)
	var fight: Array = []
	for c: Node2D in handle["combatants"]:
		if is_instance_valid(c):
			fight.append([c.global_position.round(), snappedf(float(c.get("health")), 0.1)])
	viewport.queue_free()
	await t.frames(SETTLE)
	return { "draws": draws, "fight": fight }
