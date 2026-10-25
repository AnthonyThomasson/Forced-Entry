class_name CharacterInventory extends RefCounted
## The items a character carries and the slot it holds (`character.gd`'s `inventory`): slot id ->
## `Item`, filled when the character is ready (`stock`: every item, holding the character's
## `start_slot`) or by a loadout (`set_loadout`). Each physics frame the character ticks the items
## (`tick`, before its controller runs) and on death lets go of the held one (`drop_held`). The
## spare magazines are not slots: they are `ammo`'s.

## The character carrying the items.
var character: CharacterBody2D
## Rounds the starting gun is loaded with (negative = a full magazine). Tests and sandboxes set it
## through `actor(..., props)` as `"inventory:start_rounds"`.
var start_rounds := -1
## Inventory (slot id -> Item).
var _items := {}
## Held inventory slot.
var _current_slot := 1


## The inventory of `host`.
func _init(host: CharacterBody2D) -> void:
	character = host


## The held item (none while riding in a vehicle: it is put away).
func current_item() -> Item:
	if character.is_riding():
		return null
	return _items.get(_current_slot)


## The held slot id (1–9).
func current_slot() -> int:
	return _current_slot


## The item in inventory slot `slot`; the held item for a negative slot.
func item_in(slot: int) -> Item:
	return current_item() if slot < 0 else _items.get(slot)


## Switch to inventory slot `slot`. Ignored while locked. Observers read the held item with
## current_item() (the debug HUD polls it).
func select_slot(slot: int) -> void:
	if character.is_busy():
		return
	if slot in _items and slot != _current_slot:
		character.ammo.cancel()
		_current_slot = slot
		character.invalidate_rig()  # The weapon hand may change: the rig is solved afresh.
		# Judged for the new item now, so a shot in this same frame can't slip past a wall.
		character.weapon.update_raise(0.0)


## The display name of the item in `slot` (the held item by default), or "Unknown" with none there.
## For UI observers and the AI's wording, so they never need to read Item's fields directly.
func item_name(slot := -1) -> String:
	var item := item_in(slot)
	return item.display_name if item else "Unknown"


## The held item's reach, or 0.0 with none held. For UI observers.
func item_reach() -> float:
	var item := current_item()
	return item.reach if item else 0.0


## Whether inventory slot `id` is present (carried, not necessarily held). Gates interactions
## that require an item.
func has_item(id: int) -> bool:
	return _items.has(id)


## How many of the item in `slot` are carried (the held one by default): a grenade slot's count, 1
## for any other item, 0 when the slot is empty.
func item_count(slot := -1) -> int:
	var item := item_in(slot)
	if item == null:
		return 0
	return item.uses_left() if item.is_throwable() else 1


## What the item in `slot` (the held one by default) tells its holder about itself when it is
## thrown: a grenade's `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`
## (`Item.throw_stats`), {} for any other item or an empty slot. The AI reads the grenades' numbers
## here, from what it carries, not from a copy.
func throw_stats(slot := -1) -> Dictionary:
	var item := item_in(slot)
	return item.throw_stats() if item else {}


## Where a grenade leaves this character's hand when it throws one standing: the hand the item in
## `slot` (the held one by default) is thrown with (its `weapon_hand()`; the right hand, 0, for an
## item that is not thrown or an empty slot), in the `throw` stance
## (`CharacterStanceConfig.stances`), as an offset from the body centre in the character's own
## frame: `x` px ahead of it (negative: behind), `y` px to its right. The AI judges a lob from there
## (docs/grenades.md G17) instead of keeping a copy of the stance.
func throw_release_offset(slot := -1) -> Vector2:
	var item := item_in(slot)
	var hand := item.weapon_hand() if item != null and item.is_throwable() else 0
	var stance: Dictionary = CharacterStanceConfig.stances[&"throw"]
	# Hand 0 rests to the character's right, hand 1 to its left (character_hands.gd).
	return Vector2(
		float(stance["forward"]),
		float(stance["lateral"]) * (1.0 if hand == 0 else -1.0),
	)


## The inventory slot of the gun this character fights with: the held item when it takes ammo, else
## the lowest slot holding something that does; -1 with none.
func gun_slot() -> int:
	var held := current_item()
	if held != null and held.ammo_capacity() >= 0:
		return _current_slot
	var best := -1
	for slot: int in _items:
		if _items[slot].ammo_capacity() >= 0 and (best < 0 or slot < best):
			best = slot
	return best


## Carry only what `kit` says: the items in its `slots` (see `ItemRegistry`), holding its
## `hold_slot`, with the spare magazines named by its `spare_types` (`MagazineConfig.types` ids):
## how a spawner arms a character with its gun. Starts every gun loaded as `start_rounds` says (in
## the kit's `loaded_magazine` when that type fits the gun, else the gun's own); a reload in
## progress is dropped. Safe after `add_child`, so a spawner can re-arm a scene-placed character. A
## grenade slot among `slots` holds `grenades[slot]` of them (else `start_rounds`, or one). Every
## item carries the kit's `weapon_style` (`Item.style`: how it is drawn, never what it does).
func set_loadout(kit: CharacterKit) -> void:
	character.ammo.cancel()
	_items = ItemRegistry.inventory_for(
		kit.slots, start_rounds, kit.loaded_magazine, kit.grenades, kit.weapon_style,
	)
	character.ammo.restock(kit.spare_types)
	var hold_slot := kit.hold_slot
	_current_slot = (hold_slot
			if hold_slot in _items
			else (_items.keys()[0] if not _items.is_empty() else hold_slot))
	character.weapon.reset_raise()


## Carry every item (`ItemRegistry.default_inventory`, guns loaded as `start_rounds` says), holding
## the character's `start_slot`: the character's own inventory once it is ready.
func stock() -> void:
	_items = ItemRegistry.default_inventory(start_rounds)
	_current_slot = character.start_slot


## Tick every carried item's own clocks (a gun's time between rounds, a grenade's wind-up), then
## empty the grenade slots whose last grenade has been thrown: if one was held, the gun is taken up
## again (the lowest slot that takes ammo, as `gun_slot()` says), else the fists.
func tick(delta: float) -> void:
	for item: Item in _items.values():
		item.tick(delta)
	var emptied := false
	for slot: int in _items.keys():
		if _items[slot].uses_left() == 0:
			_items.erase(slot)
			emptied = emptied or slot == _current_slot
	if not emptied:
		return
	_current_slot = gun_slot()
	if _current_slot < 0:
		_current_slot = (ItemRegistry.FISTS_SLOT
				if ItemRegistry.FISTS_SLOT in _items
				else ItemRegistry.UNARMED_SLOT)
	character.invalidate_rig()  # The weapon hand may change: the rig is solved afresh.
	character.weapon.update_raise(0.0)


## Let go of the held item: it flies off with the body's `momentum` plus a toss, and leaves the
## inventory if it left something behind in the world.
func drop_held(momentum: Vector2) -> void:
	var item := current_item()
	if item == null:
		return
	var toss := (Vector2.from_angle(randf() * TAU) * CharacterRagdollFallConfig.drop_toss
			* randf_range(0.5, 1.0))
	if item.drop(character, momentum + toss):
		_items.erase(_current_slot)
