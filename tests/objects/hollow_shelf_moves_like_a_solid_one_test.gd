extends GameTest
## An emptied bookshelf moves as the solid one did (#194 unbake-b, D21, `docs/stacked-items.md`
## SI13): its thin parts (sides, back, boards) have the centre of mass and the moment of inertia of
## the solid box of their extent (`PieceBody`), so the same shove lays it on its side, slides it as
## far and turns it as little as the same bookshelf built solid, and a low shove leaves them alike.

const Probe := preload("res://tests/_objects/piece_probe.gd")
## How far apart the two may end (a share of the solid one's slide, degrees of yaw).
const SLIDE_SHARE := 0.1
const YAW_MAX := 2.0
const PUSH := 5000.0


func describe() -> Dictionary:
	return {
		"name": "A hollow bookshelf moves like a solid one",
		"description": "The same shove lays the emptied bookshelf and the solid one on their "
			+ "sides, slides them alike and turns neither; the two have the same moment of "
			+ "inertia and centre of mass; a low shove leaves both alike.",
		"tags": ["furniture", "3d", "tipping", "unbake"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	var solid := WorldGen.object_definition("bookshelf").duplicate(true)
	var opts: Dictionary = solid.get("art_opts", {})
	opts["loose"] = false
	solid["art_opts"] = opts
	for row in 2:
		s.object(StringName("solid_%d" % row), solid, Vector2(200, 150 + 250.0 * row))
		s.object(StringName("hollow_%d" % row), "bookshelf", Vector2(550, 150 + 250.0 * row))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(5)
	var solid := Probe.body(t.object(&"solid_0"))
	var hollow := Probe.body(t.object(&"hollow_0"))
	t.check(
		is_equal_approx(hollow.inverse_yaw_inertia(), solid.inverse_yaw_inertia()),
		"the same yaw inertia (%.6f, %.6f)" % [
			hollow.inverse_yaw_inertia(),
			solid.inverse_yaw_inertia(),
		],
	)
	t.check(
		is_equal_approx(hollow.center_of_mass.y, solid.center_of_mass.y),
		"the same centre of mass (%.2f, %.2f)" % [hollow.center_of_mass.y, solid.center_of_mass.y],
	)
	var high := {}
	var low := {}
	for kind in ["solid", "hollow"]:
		high[kind] = await _shove(t, t.object(StringName("%s_0" % kind)), -4.0)
		low[kind] = await _shove(t, t.object(StringName("%s_1" % kind)), -70.0)
	t.check(high["solid"]["lean"] > 60.0, "premise: the solid one lies on its side")
	t.check(
		high["hollow"]["lean"] > 60.0 and high["hollow"]["lean"] < 120.0,
		"the hollow one lies on its side, not over (%.0f degrees)" % high["hollow"]["lean"],
	)
	t.check(
		absf(high["hollow"]["slid"] - high["solid"]["slid"]) <= high["solid"]["slid"] * SLIDE_SHARE,
		"it slid as far (%.1f px, solid %.1f)" % [high["hollow"]["slid"], high["solid"]["slid"]],
	)
	for kind in ["solid", "hollow"]:
		t.check(
			absf(high[kind]["yaw"]) < YAW_MAX,
			"%s: it did not yaw (%.2f)" % [kind, high[kind]["yaw"]],
		)

	t.check(
		absf(low["hollow"]["lean"] - low["solid"]["lean"]) < 10.0,
		"a low shove leaves them alike (%.0f, %.0f degrees)" % [
			low["hollow"]["lean"],
			low["solid"]["lean"],
		],
	)


## `piece` shoved along +x at `from_top` px from its top; how it lay, how far it slid, its yaw.
func _shove(t: TestContext, piece: Node2D, from_top: float) -> Dictionary:
	var from: Vector2 = piece.global_position
	var height := Probe.top(piece) + from_top if from_top < 0.0 else from_top
	Knockback.push(piece, Vector2(PUSH, 0.0), Vector2.ZERO, maxf(height, 4.0))
	await t.seconds(0.3)
	await Probe.settle(t, piece, 8.0)
	return {
		"lean": Probe.lean(piece),
		"slid": (Probe.middle(piece) - from).length(),
		"yaw": rad_to_deg(Probe.body(piece).rotation.y),
	}
