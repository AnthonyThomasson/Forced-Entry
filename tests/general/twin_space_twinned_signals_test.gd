extends GameTest
## `TwinSpace` says what it did with each body (#194, interface 27 and 29): `twinned(body,
## twin)` when a body got a twin, `untwinned(body)` when no builder made one (a non-solid piece),
## and `bodies()` / `bodies_without_twin()` list the same for a listener that starts late. A body
## that leaves the tree is dropped from the untwinned ones at once (an endless run spawns litter
## that is freed again and again).

const ProbeTwins := preload("res://tests/_art/art_probe_twins.gd")


func describe() -> Dictionary:
	return {
		"name": "The twin space says twinned and untwinned and lists both",
		"description": "A body no builder twins is said untwinned and listed without a twin; one a "
			+ "builder twins is said twinned with its twin and listed; a freed untwinned body "
			+ "leaves the list at once.",
		"tags": ["twins", "signals", "carriers"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	await t.frames(3)
	var space := TwinSpace.of_world(t.world)
	var said := { "twinned": [], "untwinned": [] }
	space.twinned.connect(func(b: Node2D, w: Node3D) -> void: said["twinned"].append([b, w]))
	space.untwinned.connect(func(body: Node2D) -> void: said["untwinned"].append(body))
	var bare := _body(t, Vector2(100, 100))
	await t.frames(3)
	t.check(said["untwinned"].has(bare), "a body no builder twins is said untwinned")
	t.check(bare in space.bodies_without_twin(), "and listed without a twin")
	t.check(not bare in space.bodies(), "and not listed with one")
	t.check(TwinSpace.twin_for(bare) == null, "it has no twin")
	ProbeTwins.install(t.world)
	var made := _body(t, Vector2(200, 100))
	await t.frames(3)
	var twin := TwinSpace.twin_for(made)
	t.check(twin != null, "premise: a builder twins the second body")
	var pairs: Array = said["twinned"].filter(func(p: Array) -> bool: return p[0] == made)
	t.expect_eq(pairs.size(), 1, "it is said twinned once")
	if pairs.size() == 1:
		t.check(pairs[0][1] == twin, "with its twin")
	t.check(made in space.bodies(), "and listed with one")
	t.check(not made in space.bodies_without_twin(), "and not listed without")
	var held: int = space._bare.size()
	bare.free()
	await t.frames(1)
	t.expect_eq(space._bare.size(), held - 1, "a freed untwinned body is forgotten at once")


## A bare plan handle under the world, no builder of the space twins it until the probe's does.
func _body(t: TestContext, at: Vector2) -> Node2D:
	var body := Node2D.new()
	body.add_to_group(TwinSpace.BODIES)
	body.position = at
	t.world.add_child(body)
	return body
