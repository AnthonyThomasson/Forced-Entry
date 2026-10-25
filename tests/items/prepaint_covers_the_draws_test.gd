extends GameTest
## Every gun and grenade an inventory makes paints its art ahead of time (`ItemArt.prepaint`, from
## `ItemRegistry.inventory_for`): a gun held at every raise step and lying either side up, a grenade
## with its lever held and gone, each at every lighting step. It only fills PixelArt's cache with
## what the draws would paint. This makes each weapon style's guns and grenades, then draws them
## every way a match does (held at random facings and raises, lying at random angles and sides): no
## draw paints anything new, and every texture prepainted is the one a fresh paint of the same
## inputs gives (when the renderer hands images back).

const DRAWS := 400
const STYLES: Array[StringName] = [&"police", &"scrap", &"pipe"]


func describe() -> Dictionary:
	return {
		"name": "Prepainted weapon art covers every draw",
		"description": "After ItemRegistry makes guns and grenades in each style, drawing them "
			+ "held, raised and lying at any angle paints no new texture.",
		"tags": ["art", "gun", "grenade", "cache"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var items := _make_items(t)
	await _check_no_new_paint(t, items)
	_check_fresh_paints(t, items)


## Every style's guns and grenades, made by `ItemRegistry.inventory_for` (which prepaints them).
func _make_items(t: TestContext) -> Array:
	var slots := ItemRegistry.gun_slots() + [ItemRegistry.STUN_SLOT, ItemRegistry.FRAG_SLOT]
	var items: Array = []
	for style in STYLES:
		var inv := ItemRegistry.inventory_for(
			slots,
			-1,
			&"",
			{ ItemRegistry.STUN_SLOT: 1, ItemRegistry.FRAG_SLOT: 1 },
			style,
		)
		for item in inv.values():
			items.append(item)
	var guns := items.filter(func(item: Item) -> bool: return item is GunItem).size()
	var grenades := items.filter(func(item: Item) -> bool: return item is GrenadeItem).size()
	t.check(
		guns >= 3 * STYLES.size() and grenades == 2 * STYLES.size(),
		"every style's guns and grenades were made (%d guns, %d grenades)" % [guns, grenades],
	)
	return items


## Drawing `items` every way a match does paints no new texture.
func _check_no_new_paint(t: TestContext, items: Array) -> void:
	var painted := PixelArt._cache.size()
	var drawer := Drawer.new()
	drawer.items = items
	t.world.add_child(drawer)
	await t.until(func() -> bool: return drawer.drawn, 2.0)
	t.check(drawer.drawn, "the items were drawn")
	t.check(
		PixelArt._cache.size() == painted,
		"no draw painted a new texture (%d new)" % (PixelArt._cache.size() - painted),
	)


## A prepainted texture is the one a fresh paint of its inputs gives.
func _check_fresh_paints(t: TestContext, items: Array) -> void:
	var compared := 0
	var differing := 0
	for item: Item in items:
		var same := _same_as_fresh(item)
		if same == -1:
			continue
		compared += 1
		if same == 0:
			differing += 1
	if DisplayServer.get_name() != "headless":
		t.check(
			compared == items.size(),
			"every item's texture was compared (%d of %d)" % [compared, items.size()],
		)
	if compared > 0:
		t.check(
			differing == 0,
			"%d of %d prepainted textures differ from a fresh paint" % [differing, compared],
		)


## Whether `item`'s prepainted texture (lying flat, flipped, at one lighting step) is the image a
## fresh paint of the same inputs gives: 1 the same, 0 different, -1 when the renderer hands no
## image back.
func _same_as_fresh(item: Item) -> int:
	var drawn: Dictionary = item.art.look()
	var size: Vector2 = (GunConfig.row(item.gun)["flat_size"] if item is GunItem
			else GrenadeConfig.row(item.kind)["art_size"])
	var colour: Color = drawn["body"] if item is GunItem else drawn["shell"]
	var opts := ({
		"gun": item.gun,
		"look": item.art._look_handle(drawn),
		"flat": true,
		"flip": true,
	}
			if item is GunItem
			else { "kind": item.kind, "look": item.art._look_handle(drawn), "spoon": false })
	opts["material"] = drawn["finish"]
	var angle := PixelArt.snap_angle(TAU * 5.0 / ArtCanvasConfig.turn_steps)
	var image := PixelArt.render_turned(drawn["painter"], size, colour, angle, opts).get_image()
	if image == null:
		return -1
	var base_key := PixelArt._key(drawn["painter"], size, colour, opts)
	var canvas := PixelArt._canvas(PixelArt._resolution(size), -angle, base_key)
	var fresh := PixelArt._paint(drawn["painter"], canvas, colour, opts).img
	return 1 if image.get_data() == fresh.get_data() else 0


## Stands in for the character a held item asks where and how to draw.
class FakeUser:
	extends RefCounted

	var weapon := FakeWeapon.new()
	var anatomy := FakeAnatomy.new()


## Stands in for the character's body: its hands.
class FakeAnatomy:
	extends RefCounted

	var hands := FakeHands.new()


## Stands in for the character's hands: where they hold the item and how far they punch.
class FakeHands:
	extends RefCounted

	## How far a hand is thrown in a punch: 0, no punch.
	func punch_amount(_hand: int) -> float:
		return 0.0

	## Where a hand holds the item (local px): one fixed point.
	func hand_position(_hand: int) -> Vector2:
		return Vector2(10.0, 4.0)


## Stands in for the character's use of the held item: the way it is drawn pointing (`aim`) and how
## far a long gun is raised off a wall (`lift`).
class FakeWeapon:
	extends RefCounted

	var aim := Vector2.DOWN
	var lift := 0.0

	## The way the held item is drawn pointing.
	func facing() -> Vector2:
		return aim

	## How far a long gun is raised off a wall (0..1).
	func raise() -> float:
		return lift


## Draws the items every way, from a seeded RNG.
class Drawer:
	extends Node2D

	var items: Array = []
	var drawn := false

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		var user := FakeUser.new()
		for i in DRAWS:
			for item: Item in items:
				user.weapon.aim = Vector2.from_angle(rng.randf() * TAU)
				user.weapon.lift = rng.randf() if i % 2 == 0 else float(rng.randi_range(0, 1))
				item.art.draw_weapon(self, user)
				item.art.draw_dropped(
					self,
					Vector2.ZERO,
					rng.randf_range(-TAU, TAU),
					Color.WHITE,
					{ "flip": rng.randf() < 0.5 },
				)
		drawn = true
