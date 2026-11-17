extends GameTest
## #193 phase 3, L9 in 3D: the flash pool is the light budget of a firefight. A dozen shots in one
## frame light no more than `Lighting3DConfig.flash_lights` flashes, the one with the least left to
## run dropped for the newest (the last shots are the lit ones, each at its own muzzle, and a stun's
## long white-out keeps its light through any number of shots); a flash whose pool the view
## cannot reach lights nothing (it takes no slot); with no view every flash lights.
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `flashes()`, `flash_count()`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const SHOTS := 12
## Muzzles this far apart (px), inside the view.
const SPACING := 30.0
## The camera: 600 px tall, over (200, 300).
const VIEW := 600.0
const FOCUS := Vector2(200, 300)


func describe() -> Dictionary:
	return {
		"name": "The 3D flash pool never passes its size and drops the oldest",
		"description": "Twelve shots in one frame light at most the pool's flashes, the last "
			+ "shots' muzzles lit; a shot far out of the view lights nothing; with no view a "
			+ "shot is lit.",
		"tags": ["lighting", "3d", "flash"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3000, 600))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var lighting := Probe.light(t, [], func() -> Vector2: return FOCUS, VIEW)
	if lighting == null:
		return
	for k in SHOTS:
		EventBus.post(&"shot", { "position": FOCUS + Vector2(SPACING * k, 0) })
	t.expect_eq(
		lighting.flash_count(), Lighting3DConfig.flash_lights, "the pool is full and no more"
	)
	for k in range(SHOTS - Lighting3DConfig.flash_lights, SHOTS):
		var at := FOCUS + Vector2(SPACING * k, 0)
		t.check(_lit_at(lighting, at), "the muzzle of shot %d is lit" % k)
	t.check(not _lit_at(lighting, FOCUS), "the oldest shot's flash was dropped")
	await t.seconds(0.4)
	t.check(not Probe.any_lit(lighting), "every flash is dark again")
	_check_stun_kept(t, lighting)
	await t.seconds(1.0)
	EventBus.post(&"shot", { "position": FOCUS + Vector2(2500, 0) })
	t.expect_eq(lighting.flash_count(), 0, "a shot far out of the view lights no flash")
	var all := Probe.light(t)
	EventBus.post(&"shot", { "position": FOCUS + Vector2(2500, 0) })
	t.expect_eq(all.flash_count(), 1, "with no view a flash is lit wherever it is")


## Whether a flash of `lighting` is lit exactly over `at`.
func _lit_at(lighting: WorldLighting3D, at: Vector2) -> bool:
	for l: OmniLight3D in lighting.flashes():
		if Probe.lit(l) and Probe.ground_of(l).distance_to(at) < 0.5:
			return true
	return false


## A stun is lit, then twice the pool's shots: the stun's white-out is still the light at its
## place, white, and the shots took the other slots.
func _check_stun_kept(t: TestContext, lighting: WorldLighting3D) -> void:
	var at := FOCUS + Vector2(0, 100)
	EventBus.post(&"explosion", { "position": at, "kind": &"stun", "radius": 200.0 })
	for k in Lighting3DConfig.flash_lights * 2:
		EventBus.post(&"shot", { "position": FOCUS + Vector2(SPACING * k, -100) })
	var kept: OmniLight3D = null
	for l: OmniLight3D in lighting.flashes():
		if Probe.lit(l) and Probe.ground_of(l).distance_to(at) < 0.5:
			kept = l
	t.require(
		kept != null,
		"the stun keeps its light through %d shots" % (Lighting3DConfig.flash_lights * 2),
	)
	if kept != null:
		t.expect_eq(Probe.flash_kind(kept), 2, "and is still a white-out")
