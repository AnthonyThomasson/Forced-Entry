extends GameTest
## #193 phase 3, L9 in 3D (ticket #56's stun, `docs/lighting.md`): a stun's burst is its flash's
## whole look. At the burst one of the pooled flash lights is lit where it went off, white, far
## brighter than a frag's (a peak of 4.8 or more), held at its peak for an instant, still lit after
## 0.45 s and dark within 1.1 s; and it is a white-out to the toon light (`Probe.flash_kind` 2: an
## additive white in two flat bands, apart from the dusk's cap, which nothing global changes).
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `flashes()`; Art's
## `ToonLight`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const Grenade := preload("res://tests/_ai/grenade_probe.gd")
const THROWER_AT := Vector2(200, 300)
const LOB := Vector2(600, 300)
const LIT_WITHIN := 3
const MIN_PEAK := 4.8
const HELD_FRAMES := 3
const STILL_LIT := 0.45
const DARK_BY := 1.1


func describe() -> Dictionary:
	return {
		"name": "A stun bursts as a bright white 3D flash that whites out, holds, then fades",
		"description": "At a stun's burst a white unshadowed flash is lit there, peaking at 4.8 or "
			+ "more, held a few frames, still lit after 0.45 s and dark within 1.1 s, coded as a "
			+ "white-out for the toon light.",
		"tags": ["lighting", "3d", "grenade", "stun", "flash"],
		"timeout": 14.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.actor(&"thrower", &"puppet", THROWER_AT, { "start_slot": 3, "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var lighting := Probe.light(t)
	if lighting == null:
		return
	Grenade.arm(t.actor(&"thrower"), 1, 0)
	await Grenade.throw_at(t, &"thrower", Grenade.STUN, LOB)
	if not t.require(
		await t.until(func() -> bool: return t.happened(&"explosion"), Grenade.FUSE_STUN + 3.0),
		"the stun goes off",
	):
		return
	var at: Vector2 = t.events_of(&"explosion")[0]["position"]
	var burst := t.time
	var flash: OmniLight3D = null
	for _i in LIT_WITHIN:
		flash = Probe.flash_at(lighting, at)
		if flash != null:
			break
		await t.frames(1)
	if not t.require(flash != null, "a flash is lit within %d frames of the stun" % LIT_WITHIN):
		return
	t.check(
		flash.light_color.r >= 0.9 and flash.light_color.g >= 0.9 and flash.light_color.b >= 0.9,
		"the flash is white (%s)" % str(flash.light_color),
	)
	t.check(not flash.shadow_enabled, "and casts no shadow")
	t.expect_eq(Probe.flash_kind(flash), 2, "it is a white-out to the toon light")
	var trace := await _trace(t, flash, burst)
	var peak: float = trace["peak"]
	t.check(peak >= MIN_PEAK, "it is bright, well over a frag's (peak %.2f)" % peak)
	t.check(trace["held"] >= HELD_FRAMES, "it holds its peak (%d frames)" % trace["held"])
	t.check(trace["lit_at_still"], "it is still lit %.2f s after the burst" % STILL_LIT)
	t.check(
		trace["dark_at"] >= 0.0 and trace["dark_at"] <= DARK_BY,
		"and dark within about a second (%.2f s)" % trace["dark_at"],
	)


## `flash`'s energy each frame until it is dark: `{ peak, held, lit_at_still,
## dark_at }`.
func _trace(t: TestContext, flash: OmniLight3D, burst: float) -> Dictionary:
	var peak := 0.0
	var held := 0
	var run_ended := false
	var lit_at_still := false
	var dark_at := -1.0
	while t.time - burst <= DARK_BY + 0.5:
		var e := flash.light_energy if Probe.lit(flash) else 0.0
		if e > peak:
			peak = e
		if e >= peak * 0.95 and not run_ended:
			held += 1
		elif held > 0:
			run_ended = true
		if t.time - burst >= STILL_LIT and t.time - burst < STILL_LIT + 0.05 and e > 0.0:
			lit_at_still = true
		if e <= 0.0 and dark_at < 0.0:
			dark_at = t.time - burst
			break
		await t.frames(1)
	return {
		"peak": peak, "held": held, "lit_at_still": lit_at_still, "dark_at": dark_at,
	}
