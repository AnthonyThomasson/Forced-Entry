extends GameTest
## O12 (docs/outfits.md): every garment changes how the body looks, standing, crouched and fallen.
## The look is read off the character's 3D body (`OutfitProbe.art`: its visible parts, each by the
## art it wears and its colour; pixel art is cached by what it depicts, so the same dress gives the
## same textures and a changed part a new one).
## - Standing: from plain clothes, putting on a hat, a helmet instead, a shirt instead of the
##   t-shirt, a tactical vest, a plate carrier, tactical pants and boots each paint something the
##   plain body never painted (sampled before and after each one).
## - A worn plate repaints: rifle rounds into a ceramic front plate paint a drawing the new plate
##   never had (its cracks).
## - Crouched: a shirt, tactical pants and a vest each paint something the crouched plain body never
##   painted, and a plate carrier shows: a texture painted in the carrier's colour is worn.
## - Fallen: a body that died in a plate carrier shows it where it lies.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
## Frames each drawing is sampled over (the standing body breathes, so its textures are gathered
## over a while).
const SAMPLE_FRAMES := 20
## The garments a crouched body is checked in (its legs, sleeves and folded back).
const CROUCHED_CHANGES := [
	["a shirt", { "body": &"shirt" }],
	["a tactical vest", { "vest": &"tactical_vest" }],
	["tactical pants", { "pants": &"tactical_pants" }],
]
## Pixels of a garment's colour a texture needs before it counts as painting that garment (the
## default style's carrier on the shoulders' art holds about 13, between its edge sheen, stencil
## and pouches).
const GARMENT_PIXELS := 8
const CHANGES := [
	["a hat", { "head": &"hat" }],
	["a helmet", { "head": &"helmet" }],
	["a shirt", { "body": &"shirt" }],
	["a tactical vest", { "vest": &"tactical_vest" }],
	["a plate carrier", { "vest": &"plate_carrier" }],
	["tactical pants", { "pants": &"tactical_pants" }],
	["boots", { "feet": &"boots" }],
]


func describe() -> Dictionary:
	return {
		"name": "Each garment changes the drawing",
		"description": "Every garment paints something plain clothes never do; a ceramic plate "
			+ "worn by rifle rounds repaints; a body fallen in a plate carrier shows it, "
			+ "and differently without it.",
		"tags": ["outfit", "art", "character", "fallen"],
		"timeout": 24.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	OutfitProbe.pin_height(s)
	s.actor(
		&"model",
		&"puppet",
		Vector2(250, 200),
		{ "facing": Vector2.DOWN, "movement:aim_point": Vector2(250, 900) },
	)
	s.actor(
		&"plated",
		&"puppet",
		Vector2(OutfitProbe.TARGET_X, 120),
		{ "max_health": 10_000.0, "facing": Vector2.LEFT, "movement:aim_point": Vector2(0, 120) },
	)
	s.actor(&"fallen", &"puppet", Vector2(450, 280), { "max_health": 10.0 })
	s.actor(
		&"crouched",
		&"puppet",
		Vector2(380, 380),
		{ "facing": Vector2.RIGHT, "movement:aim_point": Vector2(900, 380) },
	)
	s.camera_follow([&"model", &"plated", &"fallen", &"crouched"])


func run(t: TestContext) -> void:
	var model := t.actor(&"model")
	if not OutfitProbe.require_api(t, model):
		return
	if not t.require(
			OutfitProbe.can_read_art(model),
			"the character's 3D body can be read",
	):
		return
	t.puppet(&"model").aim_at(Vector2(250, 900))
	t.puppet(&"plated").aim_at(Vector2(0, 120))
	await _check_standing(t, model)
	await _check_crouched(t, model)
	await _check_crouched_carrier(t)
	await _check_worn_plate(t)
	await _check_fallen(t)


## Standing: each garment against plain clothes, on `model`.
func _check_standing(t: TestContext, model: Node) -> void:
	OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES)
	await t.seconds(0.5)
	var plain := await _sample(t, model)
	t.require(not plain.is_empty(), "the plain body is drawn")
	for change: Array in CHANGES:
		OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES.merged(change[1], true))
		var worn := await _sample(t, model)
		OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES)
		var back := await _sample(t, model)
		plain.merge(back)  # the plain body as it breathes, drawn before and after
		t.check(
			not _new_in(worn, plain).is_empty(),
			"%s paints something plain clothes never do" % change[0],
		)


## Crouched: the folded trunk and the limbs of `model` carry the outfit too.
func _check_crouched(t: TestContext, model: Node) -> void:
	t.puppet(&"model").set_posture(&"crouch")
	OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES)
	await t.seconds(1.0)
	var crouched_plain := await _sample(t, model)
	for change: Array in CROUCHED_CHANGES:
		OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES.merged(change[1], true))
		var worn := await _sample(t, model)
		OutfitProbe.wear(model, OutfitProbe.PLAIN_CLOTHES)
		crouched_plain.merge(await _sample(t, model))
		t.check(
			not _new_in(worn, crouched_plain).is_empty(),
			"crouched, %s paints something plain clothes never do" % change[0],
		)


## Crouched in a plate carrier, the body shows it.
func _check_crouched_carrier(t: TestContext) -> void:
	var crouched := t.actor(&"crouched")
	t.puppet(&"crouched").aim_at(Vector2(900, 380))
	t.puppet(&"crouched").set_posture(&"crouch")
	OutfitProbe.wear(
		crouched,
		OutfitProbe.PLAIN_CLOTHES.merged(
			{ "vest": &"plate_carrier", "front_plate": &"steel_iii", "back_plate": &"steel_iii" },
			true,
		),
	)
	await t.seconds(1.0)
	# Its look in the body's style.
	var carrier_color: Color = OutfitConfig.garment(
		&"plate_carrier",
	)["looks"][crouched.wardrobe.style]["color"]
	var in_carrier := _painted_in(crouched, carrier_color)
	t.check(
		in_carrier >= 1,
		"crouched, the plate carrier shows (textures in its colour: %d)" % in_carrier,
	)
	var with_carrier := OutfitProbe.art(crouched)
	OutfitProbe.wear(crouched, OutfitProbe.PLAIN_CLOTHES)
	await t.seconds(0.5)
	t.check(
		OutfitProbe.art(crouched) != with_carrier
			and _painted_in(crouched, carrier_color) < in_carrier,
		"without its plate carrier the crouched body looks different",
	)


## A worn plate repaints.
func _check_worn_plate(t: TestContext) -> void:
	var plated := t.actor(&"plated")
	OutfitProbe.wear(
		plated,
		{ "vest": &"plate_carrier", "front_plate": &"ceramic_iv", "back_plate": &"ceramic_iv" },
	)
	await t.seconds(0.5)
	var new_plate := await _sample(t, plated)
	for i in 3:
		OutfitProbe.fire(
			t,
			Vector2(OutfitProbe.FROM_X, plated.global_position.y),
			Vector2.RIGHT,
			&"rifle",
			40.0,
		)
		await t.seconds(0.3)
	t.check(
		OutfitProbe.condition(plated, "front_plate") < 1.0,
		"three rifle rounds wear the ceramic front plate (%.2f)"
			% OutfitProbe.condition(plated, "front_plate"),
	)
	await t.seconds(0.5)
	var worn_plate := await _sample(t, plated)
	t.check(
		not _new_in(worn_plate, new_plate).is_empty(),
		"the worn plate repaints: its drawing has something the new plate's never had",
	)


## Fallen: the vest shows on the body where it lies.
func _check_fallen(t: TestContext) -> void:
	var fallen := t.actor(&"fallen")
	var carrier := OutfitProbe.PLAIN_CLOTHES.merged(
		{ "vest": &"plate_carrier", "front_plate": &"steel_iii", "back_plate": &"steel_iii" },
		true,
	)
	OutfitProbe.wear(fallen, OutfitProbe.PLAIN_CLOTHES)
	await t.seconds(0.3)
	var vest_part := OutfitProbe.body_of(fallen).get_child(BodyMesh.VEST) as MeshInstance3D
	t.require(not vest_part.visible, "before the fall the body wears no vest")
	OutfitProbe.wear(fallen, carrier)
	fallen.take_damage(100.0)  # the same frame: the look must be resolved as it dies
	if not t.require(
			await t.until(
				func():
					return fallen.anatomy.ragdoll != null and fallen.anatomy.ragdoll.is_settled(),
				6.0,
			),
			"the body falls and comes to rest",
	):
		return
	await t.seconds(0.3)
	var lying := OutfitProbe.art(fallen)
	t.require(not lying.is_empty(), "the fallen body is shown")
	var vest := OutfitProbe.body_of(fallen).get_child(BodyMesh.VEST) as MeshInstance3D
	t.check(vest.visible, "the body that died in a plate carrier shows it where it lies")
	var plain := OutfitProbe.art(t.actor(&"model"))
	t.check(lying != plain, "and it looks different from a body in plain clothes")


## Every texture `c`'s body paints over `SAMPLE_FRAMES` frames, as a set (instance id -> true).
func _sample(t: TestContext, c: Node) -> Dictionary:
	var seen := {}
	for i in SAMPLE_FRAMES:
		await t.frames(1)
		for id in OutfitProbe.art(c):
			seen[id] = true
	return seen


## The textures in `drawn` that are not in `before`.
func _new_in(drawn: Dictionary, before: Dictionary) -> Array:
	return drawn.keys().filter(func(id): return not before.has(id))


## How many of the textures `c`'s body wears hold at least `GARMENT_PIXELS` pixels of `color`
## (a garment's base colour, as the painters fill it before shading and weave).
func _painted_in(c: Node, color: Color) -> int:
	var count := 0
	for tex in OutfitProbe.textures(c):
		var img: Image = tex.get_image()
		if img == null:
			continue
		if _pixels_in(img, color) >= GARMENT_PIXELS:
			count += 1
	return count


## How many of `img`'s opaque pixels are `color`.
func _pixels_in(img: Image, color: Color) -> int:
	var hits := 0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if (p.a > 0.5
					and absf(p.r - color.r) < 0.01
					and absf(p.g - color.g) < 0.01
					and absf(p.b - color.b) < 0.01):
				hits += 1
	return hits
