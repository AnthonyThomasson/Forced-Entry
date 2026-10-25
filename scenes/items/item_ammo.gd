class_name ItemAmmo extends RefCounted
## Items domain: what a held item is loaded with and its reload, the item's `ammo` part, which the
## character's `ammo` and `inventory` components call on the held item. This base is the inert
## default every item that takes no ammo has (fists, a key, a grenade): no rounds, nothing to
## reload. A gun hands up its own (`GunAmmo`). Built once with its item and never replaced; it holds
## no reference to its item, and the user is passed in on each call.

## True while the character is reloading this item (the character's `ammo` component sets and
## clears it).
var reloading := false


## Rounds loaded right now, or -1 for an item with no ammo (the default).
func rounds_loaded() -> int:
	return -1


## Rounds a full load holds, or -1 for an item with no ammo (the default).
func capacity() -> int:
	return -1


## Seconds a reload of this item takes. Default: 0 (instant).
func reload_time() -> float:
	return 0.0


## Whether reloading would change anything: a carried magazine fuller than what is loaded. Default:
## no.
func can_reload(_user: Node2D) -> bool:
	return false


## The reload time is up: swap the loaded magazine for a carried one (through the character's
## `ammo.best_magazine` / `take_magazine` / `stow_magazine`). Default: nothing.
func finish_reload(_user: Node2D) -> void:
	pass
