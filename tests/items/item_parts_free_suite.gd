extends UnitSuite
## Native unit suite (pure logic): an item frees itself once nothing holds it (ADR 0005). Its parts
## (`strike`, `ammo`, `art`) hold no reference back to it, so no `RefCounted` cycle keeps an item
## alive: every item the registry makes, the popped spoon and a magazine, each let go into the world
## as a `DroppedItem` and the node then freed, leaves a `WeakRef` that reads null. Each item is made
## inside `_dropped_then_freed`, so no temporary of the calling test still holds it.


## Make an item with `make`, drop it into the world as its dead holder does, free the node, and
## return what is left of the item.
func _dropped_then_freed(make: Callable) -> WeakRef:
	var item: Item = make.call()
	var held: WeakRef = weakref(item)
	var node := DroppedItem.spawn(item, 0.0, Vector2.ZERO)
	node.free()
	return held


## The item the registry makes for `slot`, prepainted as a fight's inventory is.
func _made(slot: int) -> Item:
	return ItemRegistry.inventory_for([slot]).values()[0]


## A spoon whose art holds it: the cycle the parts must never make.
func _spoon_held_by_its_art() -> Item:
	var spoon := GrenadeSpoon.new()
	spoon.art.set_meta(&"item", spoon)
	return spoon


func test_premise_a_part_holding_its_item_keeps_it_alive() -> void:
	var held := _dropped_then_freed(_spoon_held_by_its_art)
	assert_object(held.get_ref()).is_not_null()
	(held.get_ref() as Item).art.remove_meta(&"item")  # Break the cycle: nothing leaks.


func test_every_registry_item_frees_itself_once_dropped() -> void:
	var slots := [ItemRegistry.UNARMED_SLOT, ItemRegistry.FISTS_SLOT, ItemRegistry.KEY_SLOT]
	slots += ItemRegistry.gun_slots() + [ItemRegistry.STUN_SLOT, ItemRegistry.FRAG_SLOT]
	assert_int(slots.size()).is_greater(5)
	for slot: int in slots:
		var held := _dropped_then_freed(_made.bind(slot))
		assert_object(held.get_ref()).is_null()


func test_a_popped_spoon_frees_itself_once_dropped() -> void:
	var held := _dropped_then_freed(func() -> Item: return GrenadeSpoon.new())
	assert_object(held.get_ref()).is_null()


func test_a_magazine_frees_itself_once_dropped() -> void:
	var type := StringName(GunConfig.row(&"pistol").get("magazine", &"standard"))
	var held := _dropped_then_freed(func() -> Item: return Magazine.create(type))
	assert_object(held.get_ref()).is_null()
