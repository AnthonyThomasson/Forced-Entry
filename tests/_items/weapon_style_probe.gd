extends RefCounted
## Shared by the weapon-style tests (ticket #61, R3): how a gun or grenade LOOKS in a weapon style,
## read off the art the 3D render shows: the mesh and the flat texture the item's `art` hands out
## held (`held_mesh`, `held_texture`) and lying (`dropped_mesh`, `dropped_texture`, either side up).
## Art is cached by what it depicts, so two items that look alike hand out the very same mesh and
## texture and a changed look new ones: a look is compared as the set of their instance ids. Not a
## test (`const StyleProbe := preload(...)`).

const STYLES: Array[StringName] = [&"police", &"scrap", &"pipe"]
## The weapon style an item never given one is drawn in.
const DEFAULT_STYLE := &"police"
## Each gun's and grenade's inventory slot, by name (`ItemRegistry`: the guns' `GunConfig` slots,
## `STUN_SLOT`, `FRAG_SLOT`).
const GUNS := { &"pistol": 3, &"smg": 5, &"rifle": 6 }
const GRENADES := { &"frag": 8, &"stun": 7 }


## What `item` shows held in a hand: its mesh and its art, as a set of their instance ids.
static func held(item: Item) -> Dictionary:
	return _ids([item.art.held_mesh(), item.art.held_texture()])


## What `item` shows lying loose (a gun on its side, a grenade, a spoon), `flip` the side up: its
## mesh and its art, as a set of their instance ids.
static func lying(item: Item, flip := false) -> Dictionary:
	return _ids([item.art.dropped_mesh(flip), item.art.dropped_texture(flip)])


## `things`' instance ids as a set (a null shows nothing).
static func _ids(things: Array) -> Dictionary:
	var out := {}
	for thing in things:
		if thing is Object:
			out[(thing as Object).get_instance_id()] = true
	return out


## A fresh item for inventory `slot` in weapon `style` (`ItemArt.style`); `&""` leaves it never
## given one.
static func make(slot: int, style: StringName) -> Item:
	var item := ItemRegistry.create(slot)
	if style != &"":
		item.art.style = style
	return item


## What a character armed with the item in `slot` alone carries (bare hands, slot 1, beside it),
## holding it, in weapon `style`, with `grenades` (slot -> count): for
## `Character.inventory.set_loadout`.
static func kit(slot: int, style: StringName, grenades := {}) -> CharacterKit:
	var out := CharacterKit.new()
	out.slots = [1, slot]
	out.hold_slot = slot
	out.grenades = grenades
	out.weapon_style = style
	return out


## What a fresh item in inventory `slot` and weapon `style` shows lying, on either side (the union),
## as a set of instance ids.
static func lying_either_side(slot: int, style: StringName) -> Dictionary:
	var item := make(slot, style)
	return lying(item, false).merged(lying(item, true))


## Whether every id in `a` is in `b`.
static func within(a: Dictionary, b: Dictionary) -> bool:
	return a.keys().all(func(k) -> bool: return b.has(k))


## Whether `a` and `b` share no id.
static func apart(a: Dictionary, b: Dictionary) -> bool:
	return not a.keys().any(func(k) -> bool: return b.has(k))
