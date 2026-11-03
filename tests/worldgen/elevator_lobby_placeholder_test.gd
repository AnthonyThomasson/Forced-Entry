extends GameTest
## Every tower's elevator lobby is an empty placeholder for the stairs and elevators to come: no
## furniture, clutter or neon, one interior doorway (never an exterior door), and a floor stencil,
## "WIP ELEVATOR LOBBY" in pixel stencil letters inside a yellow and black hazard-stripe border,
## centred in the room and upright however the tower turns. `WorldGen.get_lobbies` reports what was
## laid: `{ room, rect, node, text }`, one per lobby. Nothing else in the building carries a
## stencil.

const FAR_AWAY := Vector2(5000, 5000)
const SEEDS := [1, 2]
const TEXT := "WIP ELEVATOR LOBBY"
## The hazard border's thickness in px (the spec's pick), and how far inside it the text is looked
## for.
const BORDER := 12
const INSIDE := 16
## The most the stencil may fall short of the room's rect (walls are 12 px thick, centred on it).
const WALL_FACES := 14.0
## How far the text's centre may be from the room's.
const CENTRE_SLACK := 8.0


func describe() -> Dictionary:
	return {
		"name": "The elevator lobby is an empty room with a floor stencil",
		"description": "In every tower plan, over seeds and all four turns: one lobby, empty of "
			+ "pieces, with one interior doorway and a hazard-border stencil reading WIP "
			+ "ELEVATOR LOBBY, centred and upright; no other room is stencilled.",
		"tags": ["worldgen", "tower", "lobby", "decal"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func _build(t: TestContext, plan: String, house_seed: int, turn: int) -> Node2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = house_seed
	return HouseSpawner.spawn(plan, FAR_AWAY, rng, t.world, { "turn": turn, "street": false })


## The ink in `image` inside the border: the pixels with any alpha left from `INSIDE` in, as the
## rect they span (position and size zero when there are none).
func _text_box(image: Image) -> Rect2i:
	var box := Rect2i()
	var seen := false
	for y in range(INSIDE, image.get_height() - INSIDE):
		for x in range(INSIDE, image.get_width() - INSIDE):
			if image.get_pixel(x, y).a > 0.0:
				var p := Rect2i(x, y, 1, 1)
				box = p if not seen else box.merge(p)
				seen = true
	return box


## The border band: yellow and dark pixels both appear in its outer `BORDER` px.
func _check_hazard_border(t: TestContext, label: String, image: Image) -> void:
	var yellow := 0
	var dark := 0
	for y in image.get_height():
		for x in image.get_width():
			if x >= BORDER and x < image.get_width() - BORDER:
				if y >= BORDER and y < image.get_height() - BORDER:
					continue
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			if c.r > 0.7 and c.g > 0.5 and c.b < 0.4:
				yellow += 1
			elif c.v < 0.25:
				dark += 1
	t.check(yellow > 100 and dark > 100, "%s: the border is not hazard stripes (%d yellow, %d dark)"
			% [label, yellow, dark])


func _check_stencil(t: TestContext, label: String, lobby: Dictionary) -> void:
	t.check(lobby["text"] == TEXT, "%s: the stencil says '%s'" % [label, lobby["text"]])
	var sprite := lobby["node"] as Sprite2D
	if not t.require(
		sprite != null and sprite.texture != null,
		"%s: the stencil is a sprite" % label,
	):
		return
	var rect: Rect2 = lobby["rect"]
	t.check(sprite.is_inside_tree() and is_zero_approx(sprite.global_rotation),
			"%s: the stencil is in the tree and unrotated" % label)
	var covered := Rect2(sprite.global_position, sprite.texture.get_size())
	t.check(
		covered.get_center().is_equal_approx(rect.get_center())
			and rect.encloses(covered)
			and covered.size.x >= rect.size.x - WALL_FACES
			and covered.size.y >= rect.size.y - WALL_FACES,
		"%s: the stencil covers %s of the room %s" % [label, covered, rect],
	)
	var image := sprite.texture.get_image()
	_check_hazard_border(t, label, image)
	var box := _text_box(image)
	t.check(box.size.x > box.size.y * 1.5 and box.size.y > 0,
		"%s: the text is %s px, not upright lines" % [label, box.size])
	var centre := Vector2(box.get_center()) - Vector2(image.get_size()) * 0.5
	t.check(
		centre.length() <= CENTRE_SLACK,
		"%s: the text is %s off the room's centre" % [label, centre],
	)


## No piece of furniture, clutter or neon lies in `rect`: every body under the house, bar the
## doors' leaves, is outside it.
func _check_empty(t: TestContext, label: String, house: Node2D, lobby: Dictionary) -> void:
	var holder_name := (lobby["room"] as String).capitalize() + " Furniture"
	var holder := house.get_node_or_null(NodePath(holder_name))
	t.check(holder != null and holder.get_child_count() == 0, "%s: the lobby holds pieces" % label)
	t.check(
		WorldGen.get_clutter(house).all(
			func(c: Dictionary) -> bool: return c["room"] != lobby["room"],
		),
		"%s: the lobby has clutter" % label,
	)
	for body in house.find_children("*", "RigidBody2D", true, false):
		t.check(not (lobby["rect"] as Rect2).has_point((body as Node2D).global_position),
			"%s: %s stands in the lobby" % [label, body.name])


## Build `plan` from `house_seed` turned `turn` quarter turns and check it; the stencil's image
## (`null` when there is none).
func _check_house(t: TestContext, plan: String, house_seed: int, turn: int) -> Image:
	var image: Image = null
	var label := "%s seed %d turned %d" % [plan, house_seed, turn]
	var house := _build(t, plan, house_seed, turn)
	var lobbies := WorldGen.get_lobbies(house)
	if t.check(lobbies.size() == 1, "%s lays %d lobby stencils" % [label, lobbies.size()]):
		var lobby: Dictionary = lobbies[0]
		var rooms := WorldGen.get_rooms(house).filter(
			func(r: Dictionary) -> bool: return r["type"] == "elevator_lobby",
		)
		var in_lobby: bool = rooms.size() == 1 and rooms[0]["key"] == lobby["room"]
		in_lobby = in_lobby and rooms[0]["rect"] == lobby["rect"]
		t.check(in_lobby, "%s: the stencil is not in the lobby" % label)
		_check_stencil(t, label, lobby)
		image = (lobby["node"] as Sprite2D).texture.get_image()
		_check_empty(t, label, house, lobby)
		var doorways := WorldGen.get_openings(house).filter(
			func(o: Dictionary) -> bool: return (o["rooms"] as Array).has(lobby["room"]),
		)
		t.check(doorways.size() == 1 and doorways[0]["rooms"].size() == 2
				and not doorways[0]["front"] and not doorways[0]["exit"],
			"%s: the lobby's doorways are %s" % [label, doorways])
	house.queue_free()
	return image


## The text stays upright however the tower turns: a half turn gives the same room, so the same
## stencil pixels (text rotated with the tower would stand upside down), and a three quarter turn
## the same as one.
func _check_upright(t: TestContext, plan: String, house_seed: int, images: Array) -> void:
	var label := "%s seed %d" % [plan, house_seed]
	if not t.require(
		images.all(func(i: Image) -> bool: return i != null),
		"%s: four stencils" % label,
	):
		return
	t.check(
		images[0].get_data() == images[2].get_data(),
		"%s: a half turn changes the stencil (text turned with the tower?)" % label,
	)
	t.check(
		images[1].get_data() == images[3].get_data(),
		"%s: the stencil of a three quarter turn is not the one of a quarter turn" % label,
	)
	var unturned: Vector2i = images[0].get_size()
	t.check(
		images[1].get_size() == Vector2i(unturned.y, unturned.x),
		"%s: a quarter turn does not swap the stencil's canvas" % label,
	)


## Nothing but the lobby is stencilled: a house plan has no lobby, and a tower's only stencil is
## its lobby's.
func _check_only_lobbies(t: TestContext) -> void:
	for plan in HouseDefinitions.get_all():
		var house := _build(t, plan, 1, 0)
		t.check(WorldGen.get_lobbies(house).is_empty(), "%s lays no lobby stencil" % plan)
		t.check(house.find_children("* Stencil", "Sprite2D", true, false).is_empty(),
			"%s has a stencil sprite" % plan)
		house.queue_free()
	for plan in TowerDefinitions.get_all():
		var house := _build(t, plan, 1, 0)
		var stencils := house.find_children("* Stencil", "Sprite2D", true, false)
		t.check(stencils.size() == 1, "%s has %d stencil sprites, not 1" % [plan, stencils.size()])
		house.queue_free()


func run(t: TestContext) -> void:
	_check_only_lobbies(t)
	for plan in TowerDefinitions.get_all():
		for house_seed in SEEDS:
			var images: Array = []
			for turn in 4:
				images.append(_check_house(t, plan, house_seed, turn))
			_check_upright(t, plan, house_seed, images)
	await t.frames(2)
