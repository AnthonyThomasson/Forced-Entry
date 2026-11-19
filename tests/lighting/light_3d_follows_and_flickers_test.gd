extends GameTest
## #193 phase 3 (L5, L8 in 3D): a light moves with its piece and flickers in its seeded rhythm. A
## lamp shoved across the room carries its 3D light to the same place in its own frame, while it
## slides and at rest; and one room lit twice with the same seed gives every light the same energy
## in every frame (a light that changes does so in a rhythm the seed picks), two different lights
## never in step.
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `lights()`, `lights_of`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const LAMP_AT := Vector2(300, 300)
const SHOVE := Vector2(900, 120)
const MOVED := 40.0
const KEEP := 0.5
## While it slides, a light may be a frame's travel behind (the check runs before the lighting).
const LAG := 8.0


func describe() -> Dictionary:
	return {
		"name": "A 3D light follows its shoved piece and flickers in its seeded rhythm",
		"description": "A shoved lamp keeps its 3D light at the same place in its own frame; one "
			+ "room lit twice from one seed flickers the same, and no two flickering lights alike.",
		"tags": ["lighting", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.object(&"lamp", "lamp", LAMP_AT, { "neon": "" })
	for i in 4:
		s.object(StringName("tube_%d" % i), "neon_tube", Vector2(120.0 + 200.0 * i, 500.0))


func run(t: TestContext) -> void:
	var lamp: RigidBody2D = t.object(&"lamp")
	var lighting := Probe.light(t)
	var twin := Probe.light(t)
	if lighting == null or twin == null:
		return
	var own := Probe.lights_of(lighting, lamp)
	if not t.require(not own.is_empty(), "the lamp has its 3D light"):
		return
	var offsets := {}
	for l: OmniLight3D in own:
		offsets[l] = lamp.global_transform.affine_inverse() * Probe.ground_of(l)
	Knockback.push(lamp, SHOVE)
	for _i in 30:
		await t.frames(2)
		_check_follow(t, lamp, offsets, "while it slides", LAG)
	await t.seconds(1.0)
	t.check(
		lamp.global_position.distance_to(LAMP_AT) >= MOVED,
		"the shove carries the lamp at least %.0f px" % MOVED,
	)
	_check_follow(t, lamp, offsets, "at rest", KEEP)
	_check_rhythms(t, lighting, twin)
	await _check_freed(t)


## Each light in `offsets` stands over its place in the lamp's frame.
func _check_follow(
	t: TestContext, lamp: Node2D, offsets: Dictionary, when: String, keep: float
) -> void:
	for l: OmniLight3D in offsets:
		var want: Vector2 = lamp.global_transform * (offsets[l] as Vector2)
		var off := Probe.ground_of(l).distance_to(want)
		if off > keep:
			t.check(
				false,
				"%s is %.2f px from its place in the lamp's frame %s" % [l.name, off, when],
			)
			return
	t.check(true, "the lamp's lights stay at their place in its frame %s" % when)


## The two lightings of one world with one seed flicker alike frame by frame; the lights that
## flicker each flicker their own way.
func _check_rhythms(t: TestContext, one: WorldLighting3D, two: WorldLighting3D) -> void:
	var a := one.lights()
	var b := two.lights()
	t.expect_eq(a.size(), b.size(), "the same world lit twice keeps the same lights")
	var traces: Dictionary = {}
	for _frame in 120:
		await t.frames(1)
		for k in mini(a.size(), b.size()):
			var x: float = (a[k] as OmniLight3D).light_energy
			var y: float = (b[k] as OmniLight3D).light_energy
			if absf(x - y) > 0.0001:
				t.check(false, "light %d flickers differently in its twin (%.3f, %.3f)" % [k, x, y])
				return
			traces[k] = traces.get(k, []) + [x]
	t.check(true, "every light is the same energy as its twin in every frame")
	var changing := traces.values().filter(
		func(v: Array) -> bool: return v.any(func(e: float) -> bool: return e != v[0])
	)
	t.check(not changing.is_empty(), "some light changes with its rhythm (%d)" % changing.size())
	for i in changing.size():
		for j in range(i + 1, changing.size()):
			t.check(changing[i] != changing[j], "no two changing lights are alike")


## A piece that is freed takes its light with it: a plain node that declares one light, lit in a 3D
## viewport of its own, is freed.
func _check_freed(t: TestContext) -> void:
	var world := Node2D.new()
	t.world.add_child(world)
	var piece := Source.new()
	world.add_child(piece)
	var lighting := Probe.light(t, [], Callable(), 0.0, world)
	var made := lighting.lights().duplicate()
	t.expect_eq(made.size(), 1, "the piece's one light is built")
	piece.free()
	await t.frames(3)
	t.check(lighting.lights().is_empty(), "the freed piece's light is gone from the lighting")
	t.check(not is_instance_valid(made[0]), "and freed")


## A piece with one light.
class Source:
	extends Node2D

	func get_lights() -> Array:
		return [
			{
				"offset": Vector2.ZERO,
				"colour": Color.WHITE,
				"energy": 1.0,
				"radius": 80.0,
				"rhythm": [],
				"room_light": false,
				"street": false,
				"height": &"low",
			},
		]
