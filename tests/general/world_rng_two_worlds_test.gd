extends GameTest
## `WorldRng` (interface 11, ticket #203): each world has its own random stream, seeded from the
## match seed, and hands its characters a spawn order from 0. Two worlds in one process never share
## either: the same seed in two worlds, drawn alternately, plays the same stream in both, another
## seed another stream; two worlds enrolling alternately each count their own 0, 1, 2, ...; and what
## a fight's chance (a shot's spread, a casing, debris, a fall, a stun, a dropped item's toss) draws
## from is the world's stream, never the global one. A character reparented into a world takes that
## world's next order.

const Fall := preload("res://scenes/character/body/character_ragdoll.gd")
const DRAWS := 12
const SEED_A := 4242
const SEED_B := 4243
## Characters enrolled in each world.
const PER_WORLD := 5


func describe() -> Dictionary:
	return {
		"name": "Two worlds in one process keep their own random stream and spawn order",
		"description": "Worlds seeded alike draw the same stream even when asked alternately, a "
			+ "different seed draws another, spawn orders count from 0 in each world, and the "
			+ "fight's random draws leave the global stream alone.",
		"tags": ["general", "worldrng", "determinism"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 5 })
	s.actor(&"target", &"puppet", Vector2(600, 250))


func run(t: TestContext) -> void:
	_streams(t)
	_orders(t)
	await _clocks(t)
	await _clock_stands_still_paused(t)
	await _global_stream_untouched(t)
	_adopted(t)


## Worlds A1 and A2 (one seed) and B (another), drawn in turn.
func _streams(t: TestContext) -> void:
	var roots: Array[Node] = []
	for seed_value in [SEED_A, SEED_A, SEED_B]:
		var root := Node2D.new()
		t.world.add_child(root)
		var child := Node2D.new()
		root.add_child(child)
		WorldRng.register(root, seed_value)
		roots.append(child)
	var drawn: Array = [[], [], []]
	for i in DRAWS:
		for w in 3:
			drawn[w].append(WorldRng.of(roots[w]).randf())
	t.expect_eq(drawn[0], drawn[1], "two worlds with one seed draw the same stream, asked in turn")
	t.check(drawn[0] != drawn[2], "another seed draws another stream")
	t.check(drawn[0].size() == DRAWS and drawn[0][0] != drawn[0][1], "the stream moves on")


## Characters of two worlds enrolled in turn: each world counts its own.
func _orders(t: TestContext) -> void:
	var roots: Array[Node] = []
	for i in 2:
		var root := Node2D.new()
		t.world.add_child(root)
		WorldRng.register(root, i)
		roots.append(root)
	var made: Array = [[], []]
	for i in PER_WORLD:
		for w in 2:
			var node := Node2D.new()
			roots[w].add_child(node)
			WorldRng.enrol(node)
			made[w].append(node)
	for w in 2:
		var orders: Array = made[w].map(func(n: Node) -> int:
			return WorldRng.order_of(n.get_instance_id()))
		t.expect_eq(orders, range(PER_WORLD), "world %d hands out 0, 1, 2, ... in turn" % w)
	# Enrolling again keeps the place, and the first comes before the second.
	WorldRng.enrol(made[0][2])
	t.expect_eq(WorldRng.order_of(made[0][2].get_instance_id()), 2, "a node keeps its place")
	t.check(
		WorldRng.before(made[1][0].get_instance_id(), made[1][1].get_instance_id()),
		"the one spawned first comes before the one spawned next",
	)


## Two worlds started some frames apart each count their own frames from their first character: the
## later one is not ahead by what the process ran before it, so an AI cadence keyed on it lands on
## the same frame of its world's life.
func _clocks(t: TestContext) -> void:
	var roots: Array[Node] = []
	for w in 2:
		var root := Node2D.new()
		t.world.add_child(root)
		WorldRng.register(root, w)
		var first := Node2D.new()
		root.add_child(first)
		WorldRng.enrol(first)
		roots.append(first)
		await t.frames(5 if w == 0 else 1)
	t.expect_eq(WorldRng.frame_of(roots[0]), 6, "the first world has run 6 frames")
	t.expect_eq(WorldRng.frame_of(roots[1]), 1, "the second, started 5 frames later, has run 1")
	await t.frames(2)
	t.expect_eq(WorldRng.frame_of(roots[0]) - WorldRng.frame_of(roots[1]), 5, "both go on alike")
	var late := Node2D.new()
	roots[0].get_parent().add_child(late)
	WorldRng.enrol(late)
	t.expect_eq(WorldRng.frame_of(late), 8, "a character joining later reads its world's frame")


## A world's frame is `GameClock`'s: it stands still while the tree is paused, as every AI timer
## does, though the engine goes on counting physics frames, and goes on from there once unpaused.
func _clock_stands_still_paused(t: TestContext) -> void:
	var root := Node2D.new()
	t.world.add_child(root)
	WorldRng.register(root, 9)
	var body := Node2D.new()
	root.add_child(body)
	WorldRng.enrol(body)
	await t.frames(3)
	var before := WorldRng.frame_of(body)
	var engine_before := Engine.get_physics_frames()
	var tree := t.world.get_tree()
	tree.paused = true
	await t.frames(5)
	var held := WorldRng.frame_of(body)
	var engine_run := Engine.get_physics_frames() - engine_before
	tree.paused = false
	t.require(engine_run >= 5, "premise: the engine ran %d physics frames paused" % engine_run)
	t.expect_eq(held, before, "the world's frame stood still through the pause")
	await t.frames(4)
	t.check(
		WorldRng.frame_of(body) >= before + 3 and WorldRng.frame_of(body) <= before + 4,
		"it goes on once unpaused (%d from %d)" % [WorldRng.frame_of(body), before],
	)


## A character spawned under one world and reparented into another (`MatchBuilder` joins the scene's
## own player into the match so): it drops the place it took and takes the next of the world it is
## in, whatever the process counted before; the world's counting goes on from it.
func _adopted(t: TestContext) -> void:
	var mover := t.actor(&"target")
	var old_order := WorldRng.order_of(mover.get_instance_id())
	var world := Node2D.new()
	t.world.add_child(world)
	WorldRng.register(world, 5)
	for i in old_order + 3:
		var earlier := Node2D.new()
		world.add_child(earlier)
		WorldRng.enrol(earlier)
	mover.reparent(world)
	var taken := old_order + 3
	t.expect_eq(WorldRng.order_of(mover.get_instance_id()), taken, "the world's next place")
	var later := Node2D.new()
	world.add_child(later)
	t.expect_eq(WorldRng.enrol(later), taken + 1, "the world's counting goes on from it")
	t.check(WorldRng.of(mover) == WorldRng.of(later), "and it draws from that world's stream")


## Each consumer of chance draws from the world's stream: with the global stream seeded, the act
## leaves its next draw as it was and moves the world's stream on. (A hit's blood and sparks, the
## painters and a dropped item's spin keep the global stream; the acts stop short of them.)
func _global_stream_untouched(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var target := t.actor(&"target")
	var world: Node = target.world_root()
	shooter.aim_at(target)
	await t.seconds(0.3)
	var acts := {
		"a spent casing": func() -> void:
			CasingSpawner.spawn(Vector2(300, 300), Vector2.RIGHT, world),
		"a chip of debris": func() -> void:
			DebrisSpawner.spawn(Vector2(400, 300), Vector2.RIGHT, world, Color.GRAY, "metal"),
		"a bullet's height": func() -> void:
			ProjectileSpawner.spawn(Vector2(300, 100), Vector2.RIGHT, world),
		"a blast's fragments": func() -> void:
			Explosion._fragments(Vector2(500, 100), world, null, { "fragments": 8 }),
		"a stun's sway": func() -> void:
			target.stun.take(1.0, 1.0),
		"a fall": func() -> void:
			Fall.new(target, Vector2.ZERO, Vector2.ZERO),
	}
	for what: String in acts:
		await _draws_from_world(t, what, world, acts[what])
	await _draws_from_world(t, "a gun's spread", world, func() -> void:
		shooter.shoot()
		await t.frames(1))


## `act` run with the global stream seeded: its next draw is as it was, the world's has moved.
func _draws_from_world(t: TestContext, what: String, world: Node, act: Callable) -> void:
	var rng := WorldRng.of(world)
	var before := rng.state
	seed(77)
	var expected := randf()
	seed(77)
	await act.call()
	t.expect_eq(randf(), expected, "%s leaves the global stream alone" % what)
	t.check(rng.state != before, "%s draws from the world's stream" % what)
