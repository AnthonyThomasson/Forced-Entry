extends GameTest
## An overhang whose definition says `fade_under` (the tower's awning and hanging glyph sign) fades
## to a quarter of its opacity over 0.15 s while a character stands under it, so the character can
## be seen, and comes back to opaque over the same time when the character leaves. One that does not
## say it (the street lamp's arm) never fades. The opacity read is the overhang's own and its
## ancestors' alpha up to the piece, so what fades includes its glowing edge.
##
## The reads it takes the build to publish: the catalogue rows `awning` and `glyph_sign`, each with
## an `overhang` carrying `fade_under`, non-solid, and a CanvasItem named `Overhang` under the
## spawned piece with `get_rect()` (as `objects/overhang`).

const OverhangVisuals = preload("res://scenes/objects/overhang_visuals.gd")
const KEYS := ["awning", "glyph_sign"]
const LAMP := "streetlight"
## Where the pieces stand: a row, far enough apart that one character is under only one.
const AT := {
	"awning": Vector2(200, 150),
	"glyph_sign": Vector2(500, 150),
	"streetlight": Vector2(800, 150),
}
## Where the character waits, clear of every overhang.
const AWAY := Vector2(500, 600)
## The spec's numbers: the opacity under it, and how long the fade takes.
const FADED_ALPHA := 0.25
const FADE_SECONDS := 0.15
const ALPHA_SLACK := 0.03


func describe() -> Dictionary:
	return {
		"name": "An awning fades while a character stands under it and comes back after",
		"description": "A puppet walked under an awning and a glyph sign: each fades to about a "
			+ "quarter alpha over about 0.15 s, and is opaque again after the puppet leaves. A "
			+ "street lamp's overhang does not fade.",
		"tags": ["objects", "overhang", "awning", "fade"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	for key: String in KEYS + [LAMP]:
		s.object(StringName(key), key, AT[key])
	s.actor(&"walker", &"puppet", AWAY)


## The opacity `overhang` is drawn at: its own alpha times its ancestors' up to the world root.
func _alpha(overhang: CanvasItem) -> float:
	var alpha := 1.0
	var node: Node = overhang
	while node is CanvasItem:
		alpha *= (node as CanvasItem).modulate.a * (node as CanvasItem).self_modulate.a
		node = node.get_parent()
	return alpha


## The overhang of the piece `key`, or null.
func _overhang(t: TestContext, key: String) -> CanvasItem:
	return t.object(StringName(key)).find_child("Overhang", true, false) as CanvasItem


## The world point at the middle of `overhang`'s drawn area.
func _under(overhang: CanvasItem) -> Vector2:
	return (overhang.get_global_transform() * overhang.get_rect() as Rect2).get_center()


func _check_fades(t: TestContext, key: String, walker: Node2D) -> void:
	var overhang := _overhang(t, key)
	if not t.require(overhang != null, "%s has an Overhang" % key):
		return
	var def := WorldGen.object_definition(key)
	t.check(def["overhang"].get("fade_under", false), "%s's overhang says fade_under" % key)
	t.check(not def.get("solid", true), "%s is non-solid" % key)
	t.check(is_equal_approx(_alpha(overhang), 1.0), "%s is opaque with nobody under it" % key)
	walker.global_position = _under(overhang)
	await t.seconds(FADE_SECONDS * 0.4)
	var partway := _alpha(overhang)
	t.check(
		partway < 0.95 and partway > FADED_ALPHA + ALPHA_SLACK,
		"%s is part way through fading after 0.4 of the time (alpha %.2f)" % [key, partway],
	)
	await t.seconds(0.5)
	t.check(
		absf(_alpha(overhang) - FADED_ALPHA) <= ALPHA_SLACK,
		"%s fades to %.2f with a character under it (alpha %.2f)"
			% [key, FADED_ALPHA, _alpha(overhang)],
	)
	var glow := overhang.find_child("Emissive", true, false) as CanvasItem
	if t.check(glow != null, "%s has a glowing Emissive layer" % key):
		t.check(
			absf(_alpha(glow) - FADED_ALPHA) <= ALPHA_SLACK,
			"%s's glow fades with it (alpha %.2f)" % [key, _alpha(glow)],
		)
	walker.global_position = AWAY
	await t.seconds(0.5)
	t.check(
		is_equal_approx(_alpha(overhang), 1.0),
		"%s is opaque again after the character leaves (alpha %.2f)" % [key, _alpha(overhang)],
	)
	# Opaque with nobody near: the watcher has gone back to sleep.
	await t.frames(3)
	var reads: int = OverhangVisuals.FadeWatcher.group_reads
	await t.frames(10)
	t.expect_eq(
		OverhangVisuals.FadeWatcher.group_reads,
		reads,
		"%s: no character-group read once it is opaque again" % key,
	)


func run(t: TestContext) -> void:
	var walker: Node2D = t.actor(&"walker")
	for key: String in KEYS:
		await _check_fades(t, key, walker)
	var lamp := _overhang(t, LAMP)
	if t.require(lamp != null, "the street lamp has an Overhang"):
		walker.global_position = _under(lamp)
		await t.seconds(0.5)
		t.check(
			is_equal_approx(_alpha(lamp), 1.0),
			"the street lamp's overhang stays opaque over a character (alpha %.2f)" % _alpha(lamp),
		)
