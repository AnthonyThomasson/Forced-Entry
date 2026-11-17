extends GameTest
## #193 phase 3, L9 in 3D (`docs/lighting.md`): a shot and an explosion each light a brief flash in
## the 3D render, then it goes. A puppet fires a pistol: within a few frames of the `shot` event one
## of the lighting's pooled flash lights is lit at the muzzle, in the shot's warm colour, and within
## 0.25 s every flash is dark again. It then throws a frag: within a few frames of the `explosion`
## event a flash is lit where it went off, a frag's orange, and within 1.5 s every flash is dark.
## A flash is not cast (no shadow, outside the shadow cap) and hangs at hand height.
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `flashes()`,
## `shadowed_count()`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const Grenade := preload("res://tests/_ai/grenade_probe.gd")
const GUNNER_AT := Vector2(200, 300)
const AIM := Vector2(880, 300)
const LOB := Vector2(560, 300)
## Frames after the event by which a flash is lit.
const LIT_WITHIN := 3
## s after a shot / an explosion by which every flash is dark.
const SHOT_GONE := 0.25
const BLAST_GONE := 1.5


func describe() -> Dictionary:
	return {
		"name": "A shot and an explosion each light a brief 3D flash",
		"description": "A pistol shot lights a pooled OmniLight3D at the muzzle, warm, gone within "
			+ "0.25 s; a frag lights one where it bursts, orange, gone within 1.5 s; a flash casts "
			+ "no shadow and hangs at hand height.",
		"tags": ["lighting", "3d", "flash", "grenade"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.actor(&"gunner", &"puppet", GUNNER_AT, { "start_slot": 3, "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var lighting := Probe.light(t)
	if lighting == null:
		return
	t.require(
		lighting.flashes().size() == Lighting3DConfig.flash_lights,
		"the lighting has its pool of %d flash lights" % Lighting3DConfig.flash_lights,
	)
	t.check(not Probe.any_lit(lighting), "no flash is lit before anything happens")
	var gunner := t.puppet(&"gunner")
	gunner.aim_at(AIM)
	await t.seconds(0.4)
	gunner.shoot()
	if not t.require(
		await t.until(func() -> bool: return t.happened(&"shot"), 1.0), "the pistol fires"
	):
		return
	var shot: Dictionary = LightingConfig.flashes[&"shot"]
	await _flash(t, lighting, t.events_of(&"shot")[0]["position"], shot, SHOT_GONE)

	Grenade.arm(t.actor(&"gunner"), 0, 1)
	await Grenade.throw_at(t, &"gunner", Grenade.FRAG, LOB)
	if not t.require(
		await t.until(func() -> bool: return t.happened(&"explosion"), Grenade.FUSE_FRAG + 3.0),
		"the frag goes off",
	):
		return
	var frag: Dictionary = LightingConfig.flashes[&"frag"]
	await _flash(t, lighting, t.events_of(&"explosion")[0]["position"], frag, BLAST_GONE)


## A flash is lit near `at` within `LIT_WITHIN` frames of the event, in `look`'s colour, uncast, at
## hand height; every flash is dark within `gone` s of it.
func _flash(
	t: TestContext, lighting: WorldLighting3D, at: Vector2, look: Dictionary, gone: float
) -> void:
	var start := t.time
	var found: OmniLight3D = null
	for _i in LIT_WITHIN:
		found = Probe.flash_at(lighting, at)
		if found != null:
			break
		await t.frames(1)
	t.require(found != null, "a flash is lit within %.0f px of the event" % Probe.FLASH_NEAR)
	if found == null:
		return
	t.check(found.light_color == look["color"], "the flash is in its look's colour")
	t.check(not found.shadow_enabled, "a flash casts no shadow")
	t.expect_near(
		found.position.y, Lighting3DConfig.flash_height * RenderConfig.unit, 0.01,
		"it hangs at hand height",
	)
	t.expect_eq(lighting.shadowed_count(), 0, "and takes no shadow slot")
	var dark := await t.until(func() -> bool: return not Probe.any_lit(lighting), gone + 1.0)
	t.check(
		dark and t.time - start <= gone,
		"every flash is gone within %.2f s (dark after %.2f s)" % [gone, t.time - start],
	)
