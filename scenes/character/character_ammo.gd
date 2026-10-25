class_name CharacterAmmo extends RefCounted
## The magazines a character carries and its reloading (`character.gd`'s `ammo`). The spare
## magazines (`Magazine` items) are never inventory slots, so no number key or interaction can
## select them; magazines are lost with the body. A reload (`reload`) runs the held item's
## `reload_time()` and is counted down each physics frame (`update`), right after the controller;
## switching slot, a ride and death cancel it (`cancel`). It posts `&"reload"` on `EventBus` at its
## start and once done.

## The character carrying the magazines.
var character: CharacterBody2D
## The spare magazines carried, as `MagazineConfig.types` ids (several of a kind are fine): two for
## each gun. Carried from the character's `_ready` (`restock`); tests and sandboxes set it through
## `actor(..., props)` as `"ammo:spare_magazine_types"`.
var spare_magazine_types: Array = [
	&"standard", &"standard", &"smg_standard", &"smg_standard", &"rifle_standard",
	&"rifle_standard",
]
## Spare magazines carried (Magazine).
var _magazines: Array = []
## The item being reloaded (null = not reloading) and the seconds left until it is done.
var _reloading_item: Item
var _reload_left := 0.0


## The magazines of `host`.
func _init(host: CharacterBody2D) -> void:
	character = host


## Reload the held item (R): start swapping in the fullest carried magazine, which takes
## the item's `reload_time()`. Ignored when dead, locked in an interaction, running, already
## reloading, or when no carried magazine would add rounds. Switching items, running or an
## interaction cancels it.
func reload() -> void:
	var item: Item = character.inventory.current_item()
	if (character.is_dead
			or character.use.is_busy()
			or character.movement.is_running()
			or is_reloading()
			or item == null
			or not item.can_reload(character)):
		return
	_reloading_item = item
	_reload_left = item.reload_time()
	item.reloading = true
	_post(item, &"start")


## True while a reload is in progress.
func is_reloading() -> bool:
	return _reloading_item != null


## Whether a reload of the item in `slot` (the held one by default) would add rounds right now.
func can_reload(slot := -1) -> bool:
	var item: Item = character.inventory.item_in(slot)
	return item != null and not is_reloading() and item.can_reload(character)


## How many spare magazines are carried.
func spare_magazines() -> int:
	return _magazines.size()


## The carried magazine for `gun` holding the most rounds (null with none); it stays carried.
func best_magazine(gun: StringName) -> Magazine:
	var best: Magazine = null
	for mag: Magazine in _magazines:
		if mag.gun == gun and (best == null or mag.rounds > best.rounds):
			best = mag
	return best


## Take `best_magazine(gun)` out of the carried store (null with none): an item loading it.
func take_magazine(gun: StringName) -> Magazine:
	var mag := best_magazine(gun)
	if mag != null:
		_magazines.erase(mag)
	return mag


## Carry `mag` (a magazine an item has taken out of a gun).
func stow_magazine(mag: Magazine) -> void:
	_magazines.append(mag)


## Rounds loaded in the item in `slot` (the held one by default), or -1 if it has no ammo.
func rounds(slot := -1) -> int:
	var item: Item = character.inventory.item_in(slot)
	return item.rounds_loaded() if item else -1


## Rounds a full load of the item in `slot` (the held one by default) holds, or -1 if it has no
## ammo.
func capacity(slot := -1) -> int:
	var item: Item = character.inventory.item_in(slot)
	return item.ammo_capacity() if item else -1


## Count a reload down; it is dropped if its item is no longer held, the character is locked in an
## interaction or runs. Done: the item swaps its magazine.
func update(delta: float) -> void:
	if _reloading_item == null:
		return
	if (character.use.is_busy()
			or character.movement.is_running()
			or character.inventory.current_item() != _reloading_item):
		cancel()
		return
	_reload_left -= delta
	if _reload_left > 0.0:
		return
	var item := _reloading_item
	cancel()
	item.finish_reload(character)
	_post(item, &"done")


## Stop any reload in progress and clear the item's `reloading` flag.
func cancel() -> void:
	if _reloading_item != null:
		_reloading_item.reloading = false
	_reloading_item = null


## Carry only the spare magazines `types` names (`MagazineConfig.types` ids), dropping the rest.
func restock(types: Array) -> void:
	_magazines = ItemRegistry.create_magazines(types)


## Tell the world a reload began (`stage` &"start": the magazine comes out) or finished (&"done":
## the new one is seated) by `item`, from the weapon hand (the Audio domain voices it; a cancelled
## reload never posts "done").
func _post(item: Item, stage: StringName) -> void:
	EventBus.post(
		&"reload",
		{
			"position": character.hand_world(item.weapon_hand()), "gun": item.gun_id(),
			"stage": stage, "power": item.round_power(), "character": character,
		},
	)
