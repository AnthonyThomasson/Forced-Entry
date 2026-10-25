class_name CharacterKit extends RefCounted
## What a character carries (`Character.set_loadout`, interface 7): its item slots and the one held,
## its spare magazines, the type its gun starts loaded with, its grenades and the weapon style every
## item is drawn in. Whoever arms a character fills it (`LoadoutConfig.apply` for a match's spawns);
## a field left alone is the plain default.

## The `ItemRegistry` slots it carries, and only those.
var slots: Array = []
## The slot it holds; one it does not carry = the first carried item.
var hold_slot: int = -1
## Its spare magazines, by `MagazineConfig.types` id, one entry each.
var spare_types: Array = []
## The magazine type its gun starts loaded with when that type fits the gun (`&""` = the gun's own).
var loaded_magazine: StringName = &""
## How many grenades a grenade slot among `slots` holds, by slot (a slot missing = the character's
## `start_rounds`, or one).
var grenades: Dictionary = {}
## The weapon style every item carries (`Item.style`: how it is drawn, never what it does).
var weapon_style: StringName = &"police"
