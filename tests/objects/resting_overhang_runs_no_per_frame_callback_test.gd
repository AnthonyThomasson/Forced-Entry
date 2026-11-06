extends GameTest
## A fading overhang left alone has no per-frame callback of its own and writes no unchanged alpha.
## Its fade is driven by the shared watcher, proved by overhang_fades_under_character.

const KEYS := [&"awning", &"glyph_sign", &"streetlight"]


func describe() -> Dictionary:
	return {
		"name": "An overhang at rest runs no per-frame callback",
		"description": "Fading awnings and signs, and the non-fading lamp, neither process nor "
			+ "write modulate while left at rest.",
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
	for id in KEYS:
		var piece := t.object(id)
		var overhang := piece.find_child("Overhang", true, false)
		if not t.require(overhang != null, "%s has an overhang" % id):
			continue
		t.check(not overhang.is_processing(), "%s runs no process callback at rest" % id)
		t.check(not overhang.is_physics_processing(), "%s runs no physics callback at rest" % id)
		t.check(overhang.get("fade_writes") == 0, "%s writes no unchanged alpha" % id)
