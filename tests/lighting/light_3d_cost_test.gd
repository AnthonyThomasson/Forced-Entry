extends GameTest
## #193 phase 3 (L4 in 3D): the 3D lights are cheap. Ten rooms in a row, a lamp and a tube in each
## even one and a ceiling fixture in each odd one, are chosen by the view's focus: at most
## `LightingCostConfig.max_lights` are on, the ones whose pools come nearest the view (ranked by the
## distance less the pool's radius), and fade in and out; at most `shadow_lights` cast a shadow,
## only ceiling fixtures (a lamp stands inside its own mesh), a light that casts keeping its shadow
## against a rival that is not `keep_margin` times nearer; with no focus every light stays on and
## none casts a shadow.
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `lights()`, `fixtures()`,
## `shadowed_count()`, `on_count()`, `in_view_count()`, `choose(snap)`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const ROOMS := 10
const WIDTH := 400.0
const MOST := 8
const CASTERS := 2
## The camera: tall enough that the lights of several rooms reach the view.
const VIEW := 2400.0


func describe() -> Dictionary:
	return {
		"name": "The 3D lights are on near the view and only a few fixtures cast shadows",
		"description": "A row of rooms: the lights whose pools are nearest the view are on, the "
			+ "rest off, fading; at most the shadow cap cast shadows, only ceiling fixtures, a "
			+ "caster keeping its shadow against a rival not enough nearer; without a focus all "
			+ "are on and none casts.",
		"tags": ["lighting", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, WIDTH * ROOMS, 600))
	s.switch(&"nav.rebake", false)
	s.set_static(LightingCostConfig, &"max_lights", MOST)
	s.set_static(LightingCostConfig, &"shadow_lights", CASTERS)
	for k in range(0, ROOMS, 2):
		s.object(
			StringName("lamp_%d" % k),
			"lamp",
			Vector2(WIDTH * k + 200.0, 150.0),
			{ "neon": "" },
		)
		s.object(StringName("tube_%d" % k), "neon_tube", Vector2(WIDTH * k + 200.0, 450.0))


func run(t: TestContext) -> void:
	var rooms := _rooms()
	var lighting := Probe.light(t, rooms)
	if lighting == null:
		return
	var kept := lighting.lights().size()
	t.check(kept > MOST, "more lights are placed than the cap keeps on (%d)" % kept)
	t.expect_eq(lighting.fixtures().size(), ROOMS >> 1, "each odd room has a fixture")
	t.expect_eq(lighting.on_count(), kept, "with no focus every light is on")
	t.expect_eq(lighting.shadowed_count(), 0, "with no focus none casts a shadow")
	var focus := [Vector2(1000.0, 300.0)]
	var lit := Probe.light(t, rooms, func() -> Vector2: return focus[0], VIEW)
	lit.choose(true)
	_check_cap(t, lit)
	_check_keeps_its_shadow(t, lit, focus)
	await _check_fade(t, lit, focus)
	_check_no_cap(t, lit)


## The rooms: a row of `WIDTH` px rects.
func _rooms() -> Array:
	var out: Array = []
	for k in ROOMS:
		out.append({ "key": "r%d" % k, "rect": Rect2(WIDTH * k, 0.0, WIDTH, 600.0) })
	return out


func _on(lit: WorldLighting3D) -> Array:
	return lit.lights().filter(func(l: Node3D) -> bool: return l.visible)


## The cap: more lights reach the view than are kept on, and the shadows are the nearest fixtures'.
func _check_cap(t: TestContext, lit: WorldLighting3D) -> void:
	t.check(
		lit.in_view_count() > MOST,
		"more lights reach the view than the cap (%d)" % lit.in_view_count(),
	)
	t.expect_eq(lit.on_count(), MOST, "exactly the cap are on")
	t.expect_eq(_on(lit).size(), MOST, "and exactly the cap are shown")
	t.expect_eq(lit.shadowed_count(), CASTERS, "the shadow cap is spent")
	for l: OmniLight3D in lit.lights():
		if l.shadow_enabled:
			t.check(l.visible and l.get_meta(&"shadowable"), "%s is a shown fixture" % l.name)
	var casting := _casting(lit)
	t.check(
		casting == ["Fixture_r1", "Fixture_r3"],
		"the two fixtures nearest the focus cast (%s)" % [casting],
	)


## The names of the lights casting a shadow, sorted.
func _casting(lit: WorldLighting3D) -> Array:
	var out := []
	for l: OmniLight3D in lit.lights():
		if l.shadow_enabled:
			out.append(String(l.name))
	out.sort()
	return out


## A light keeps its shadow against a nearer rival within `keep_margin`: the focus moves from 1000
## to 1500, where fixture r5 (2200) is nearer than r1 (600) but not by the margin, so r1 and r3
## still cast, and a rival that is much nearer takes it.
func _check_keeps_its_shadow(t: TestContext, lit: WorldLighting3D, focus: Array) -> void:
	focus[0] = Vector2(1500.0, 300.0)
	lit.choose(true)
	var casting := _casting(lit)
	t.check(
		casting == ["Fixture_r1", "Fixture_r3"],
		"r1 keeps its shadow against the nearer r5 (%s)" % [casting],
	)
	focus[0] = Vector2(2200.0, 300.0)
	lit.choose(true)
	casting = _casting(lit)
	t.check(
		casting == ["Fixture_r3", "Fixture_r5"],
		"a rival well nearer takes it (%s)" % [casting],
	)


## Moving the focus the length of the room switches lights on and off by fading, not at once.
func _check_fade(t: TestContext, lit: WorldLighting3D, focus: Array) -> void:
	focus[0] = Vector2(3700.0, 300.0)
	lit.choose(true)
	var far_on := lit.fixtures().filter(
		func(f: Dictionary) -> bool: return (f["light"] as Node3D).visible
	)
	t.check(
		not far_on.is_empty() and (lit.fixtures()[0]["light"] as Node3D).visible == false,
		"the far fixtures are on and the first one is off",
	)
	focus[0] = Vector2(200.0, 300.0)
	lit.choose()
	var first: OmniLight3D = lit.fixtures()[0]["light"]
	var last: OmniLight3D = lit.fixtures()[lit.fixtures().size() - 1]["light"]
	t.check(last.visible, "a light about to go off is still shown a moment")
	t.check(not first.visible, "and one about to come on is not yet")
	await t.seconds(LightingCostConfig.fade_time * 2.0)
	t.check(first.visible and first.light_energy > 0.0, "it fades in (%.2f)" % first.light_energy)
	t.check(not last.visible, "and the other has faded out")


## A cap of none switches the shadows off, and does not trip the choice.
func _check_no_cap(t: TestContext, lit: WorldLighting3D) -> void:
	LightingCostConfig.shadow_lights = 0
	lit.choose(true)
	LightingCostConfig.shadow_lights = CASTERS
	t.expect_eq(lit.shadowed_count(), 0, "with a cap of none no light casts a shadow")
