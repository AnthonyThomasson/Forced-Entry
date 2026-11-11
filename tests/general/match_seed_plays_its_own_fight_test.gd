extends GameTest
## A match's world stream (`WorldRng`, interface 11) is what steers its fight, apart from the
## layout. One match seed (so one house, one placement, one loadout) is built three times, each in a
## world of its own (`MainProbe.viewport`) one after the other in one process, and each time the
## world's stream is registered afresh from a seed the test names: A, A, then B. The two of A start
## the stream alike and seed their NPCs' reflex rolls alike; B starts another stream and seeds
## another roll; and the fight of B (where every NPC stands, how hurt it is and how its aim sways a
## moment after a flash blinds them all alike, the sway drawn from the stream) is not the fight of
## A, which the two of A play alike for
## as long as this runs.
## (That one seed replays its fight exactly for long is the perf guards' fingerprint, not asserted
## here: the planning re-bake lands on a worker thread's own time.)

const NpcReflexes := preload("res://scenes/ai/npc_reflexes.gd")
const MainProbe := preload("res://tests/_main/main_probe.gd")
## The match seed every build shares: the layout.
const LAYOUT := 31
## Seconds of flash-blindness every NPC takes a moment in.
const FLASH := 2.0
## The world's stream seeds the three builds take, `[A, A, B]`.
const WORLD_SEEDS := [41, 41, 42]
const PLAN := "garage_home"
## Physics frames each fight runs: short of where one seed's replays start to part (the re-bake's
## time), so a difference is the stream's.
const FRAMES := 25
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
	var played: Array = []
	for world_seed: int in WORLD_SEEDS:
		var one: Variant = await _play(t, world_seed)
		if not t.require(one != null, "the match of world seed %d is built" % world_seed):
			return
		played.append(one)
	t.expect_eq(played[0]["draws"], played[1]["draws"], "one world seed starts its stream alike")
	t.check(played[0]["draws"] != played[2]["draws"], "another world seed starts another stream")
	t.expect_eq(
		played[0]["rolls"],
		played[1]["rolls"],
		"one world seed seeds its NPCs' rolls alike",
	)
	t.check(played[0]["rolls"] != played[2]["rolls"], "another world seed seeds other rolls")
	if not t.require(
			played[0]["fight"] == played[1]["fight"],
			"the layout of one match plays alike for %d frames under one world seed" % FRAMES,
	):
		return
	t.check(played[0]["fight"] != played[2]["fight"], "another world seed plays another fight")


## The match of `LAYOUT` built in a world of its own, the world's stream then registered from
## `world_seed`: `{ draws, rolls, fight }`, the first draws of the stream, the seed each NPC's
## reflexes take from it and where every combatant stands after `FRAMES` frames. Null when the
## world was torn down while building.
func _play(t: TestContext, world_seed: int) -> Variant:
	var viewport := MainProbe.viewport(t)
	var world := Node2D.new()
	world.name = "World"
	viewport.add_child(world)
	var spec := MatchBuilder.spec({
		"seed": LAYOUT,
		"plan": PLAN,
		"defenders": { "count": 3 },
		"invaders": { "count": 3 },
	})
	var handle: Dictionary = await MatchBuilder.build(spec, world)
	if handle.is_empty():
		return null
	WorldRng.register(world, world_seed)
	var rng := WorldRng.of(world)
	var draws := [rng.randi(), rng.randi(), rng.randi()]
	var rolls: Array = []
	for c: Node2D in handle["combatants"]:
		var reflexes := NpcReflexes.new(null)
		reflexes.bind(c)
		rolls.append(reflexes._rng.seed)
	# The same flash for every NPC in each world: its sway is drawn from the world's stream.
	for c: Node2D in handle["combatants"]:
		c.stun.take(FLASH, 0.0)
	await t.frames(FRAMES)
	var fight: Array = []
	for c: Node2D in handle["combatants"]:
		if is_instance_valid(c):
			fight.append([
				c.global_position.round(),
				snappedf(float(c.get("health")), 0.1),
				snappedf(c.stun.wander(0.0), 0.001),
			])
	viewport.queue_free()
	await t.frames(SETTLE)
	return { "draws": draws, "rolls": rolls, "fight": fight }
