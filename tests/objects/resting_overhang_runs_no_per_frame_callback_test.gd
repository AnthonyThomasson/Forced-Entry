extends GameTest
## A fading overhang left alone has no per-frame callback of its own, writes no unchanged alpha
## and costs no per-frame character-group read: the shared watcher that steps fading overhangs
## sleeps while none is fading. Its fade is driven by that watcher, proved by
## overhang_fades_under_character.

const OverhangVisuals = preload("res://scenes/objects/overhang_visuals.gd")
## Frames the watcher is watched at rest.
const REST_FRAMES := 30
const KEYS := [&"awning", &"glyph_sign", &"streetlight"]


func describe() -> Dictionary:
	return {
		"name": "An overhang at rest runs no per-frame callback",
		"description": "Fading awnings and signs, and the non-fading lamp, neither process nor "
			+ "write modulate while left at rest, and nothing reads the character group per "
			+ "frame for them.",
		"tags": ["overhang", "perf"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	for i in KEYS.size():
		s.object(KEYS[i], String(KEYS[i]), Vector2(200.0 + 250.0 * i, 200))


func run(t: TestContext) -> void:
	await t.frames(30)
	var reads_before: int = OverhangVisuals.FadeWatcher.group_reads
	await t.frames(REST_FRAMES)
	t.expect_eq(
		OverhangVisuals.FadeWatcher.group_reads - reads_before,
		0,
		"no character-group read in %d frames at rest" % REST_FRAMES,
	)
	for id in KEYS:
		var piece := t.object(id)
		var overhang := piece.find_child("Overhang", true, false)
		if not t.require(overhang != null, "%s has an overhang" % id):
			continue
		t.check(not overhang.is_processing(), "%s runs no process callback at rest" % id)
		t.check(not overhang.is_physics_processing(), "%s runs no physics callback at rest" % id)
		t.check(overhang.get("fade_writes") == 0, "%s writes no unchanged alpha" % id)
