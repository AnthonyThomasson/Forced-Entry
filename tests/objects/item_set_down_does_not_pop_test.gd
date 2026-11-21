extends GameTest
## An item set on a top is set down, not dropped or thrown (#194 stack-a, D20,
## `docs/stacked-items.md` SI2): from the first frame it stands a hair (under a px) over its top,
## its fall is slow (it lands at well under 40 px/s), and it never rises above where it started.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const TABLE_AT := Vector2(300, 250)
const TABLE_TOP := 31.0
const FRAMES := 40
## The most a set-down item may stand over its top at the first frame (px), the fastest it may fall
## (px/s), and the most it may bounce back over where it started (px).
const MAX_GAP := 1.0
const MAX_SPEED := 40.0
const MAX_RISE := 0.2


func describe() -> Dictionary:
	return {
		"name": "A set-down item does not pop",
		"description": "A plate set on a table starts under a px over its top, never falls faster "
			+ "than 40 px/s and never bounces up over its start while it settles asleep.",
		"tags": ["furniture", "3d", "items", "stacking", "twins"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"table", "table", TABLE_AT)
	s.object(&"plate", "plate", Vector2(-10, 0), { "on": &"table" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var plate: Node2D = t.object(&"plate")
	var body: RigidBody3D = null
	var first := -1.0
	var start := -1.0
	var fastest := 0.0
	var highest := -INF
	for i in FRAMES:
		await t.frames(1)
		body = Probe.body(plate)
		if body == null:
			continue
		var height := body.global_position.y / RenderConfig.unit
		if first < 0.0:
			first = height
			start = height
		fastest = maxf(fastest, absf(body.linear_velocity.y) / RenderConfig.unit)
		highest = maxf(highest, height)
	t.require(body != null, "the plate has a body")
	t.check(
		absf(first - TABLE_TOP) < MAX_GAP,
		"the plate first stands %.2f px up, over its top of %.0f px" % [first, TABLE_TOP],
	)
	t.check(fastest < MAX_SPEED, "it falls at %.1f px/s at most" % fastest)
	t.check(
		highest <= start + MAX_RISE, "it never rises over where it started (%.2f px)" % highest
	)
	t.check(await Probe.settle(t, plate, 4.0), "and it ends asleep")
