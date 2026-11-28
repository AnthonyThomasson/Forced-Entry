extends GameTest
## A carried push (a walk into a piece, a leg press: `CharacterPush.shove`) slides a piece and never
## turns it over (#194, interface 5): it is held to the piece's centre of mass, the
## height read in the world (the 3D body's centre of mass is an offset from its origin, which stands
## off the floor for a piece that lies on its side). A bookshelf lying on its side is walked into
## and stays lying; an upright wardrobe pressed at the knee for seconds (below its centre of mass,
## which pitches it the other way) stays upright, and both are carried along the push.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const CharacterPush := preload("res://scenes/character/character_push.gd")
const SHELF_AT := Vector2(200, 150)
const WARDROBE_AT := Vector2(200, 300)
const PRESS_SECONDS := 2.0
## The pusher's pace (px/s) and the impulse it adds a frame: a walk, as the character gives.
const PACE := 120.0
const IMPULSE := 2000.0


func describe() -> Dictionary:
	return {
		"name": "A walk into a lying bookshelf or a leg press on a wardrobe turns neither over",
		"description": "A bookshelf struck high lies on its side and is then pushed at the hip for "
			+ "two seconds: it is still lying and slid along the push; a wardrobe pressed at the "
			+ "knee for two seconds stays under its tipping lean and slid.",
		"tags": ["furniture", "3d", "tipping", "pushable", "character"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.object(&"shelf", "bookshelf", SHELF_AT)
	s.object(&"wardrobe", "wardrobe", WARDROBE_AT)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var shelf := t.object(&"shelf")
	var wardrobe := t.object(&"wardrobe")
	Knockback.push(shelf, Vector2(5000.0, 0.0), Vector2.ZERO, Probe.top(shelf) - 4.0)
	await t.seconds(0.3)
	await Probe.settle(t, shelf, 10.0)
	if not t.require(Probe.lean(shelf) > 60.0, "premise: the bookshelf lies on its side"):
		return
	var lead := Probe.body(shelf)
	var world_centre := (lead.global_transform * lead.center_of_mass).y / RenderConfig.unit
	t.check(
		absf(lead.centre_height() - world_centre) < 0.5,
		"the lying shelf's centre height (%.1f px) is its centre of mass in the world (%.1f px)"
			% [lead.centre_height(), world_centre],
	)
	var from: Vector2 = shelf.global_position
	await _press(t, shelf, BodyHeights.contact(&"hip"))
	t.check(
		Probe.lean(shelf) > 60.0,
		"the walk leaves the bookshelf lying (%.0f degrees)" % Probe.lean(shelf),
	)
	t.check(
		shelf.global_position.x - from.x > 3.0,
		"and slid it along the push (%.1f px)" % (shelf.global_position.x - from.x),
	)
	var wardrobe_from: Vector2 = wardrobe.global_position
	await _press(t, wardrobe, BodyHeights.contact(&"leg"))
	t.check(
		Probe.lean(wardrobe) < PieceBodyConfig.tipped_degrees,
		"the leg press leaves the wardrobe standing (%.0f degrees)" % Probe.lean(wardrobe),
	)
	t.check(
		wardrobe.global_position.x - wardrobe_from.x > 3.0,
		"and slid it (%.1f px)" % (wardrobe.global_position.x - wardrobe_from.x),
	)


## Push `piece` along +x at `height` (px) every frame for `PRESS_SECONDS`, as a walker does.
func _press(t: TestContext, piece: Node2D, height: float) -> void:
	var until := t.time + PRESS_SECONDS
	while t.time < until:
		var contact := Vector3(piece.global_position.x - 20.0, piece.global_position.y, height)
		CharacterPush.shove(piece, Vector2.RIGHT, IMPULSE, contact, PACE)
		await t.frames(1)
