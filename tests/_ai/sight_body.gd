extends CharacterBody2D
## Test double (a probe, not a test): a character as an NPC's sight reads it, with no world of its
## own but the physics space it stands in. Alive or `is_dead`, a `faction`, nothing held, not
## reloading, standing, unhurt and never blinded; `facing` and `world_root()` as the sight's list
## reads them. `tests/ai/perception_cadence_suite.gd` places these around a perception.

## Where the body faces.
var facing := Vector2.RIGHT
## Dead characters are skipped by sight.
var is_dead := false
## Which side it is on.
var faction: StringName = &"household"
## What sight reads off it.
var stun := Stun.new()
var ammo := Ammo.new()
var inventory := Inventory.new()
var movement := Movement.new()


## The world this body's sight list is scoped to.
func world_root() -> Node:
	return get_parent()


## No wounds.
func damage_taken() -> float:
	return 0.0


## Never blinded.
class Stun:
	extends RefCounted

	func is_blind() -> bool:
		return false


## Never reloading.
class Ammo:
	extends RefCounted

	func is_reloading() -> bool:
		return false


## Nothing held.
class Inventory:
	extends RefCounted

	func current_item() -> Variant:
		return null


## Always standing.
class Movement:
	extends RefCounted

	func posture() -> StringName:
		return &"stand"
