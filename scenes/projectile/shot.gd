class_name Shot extends RefCounted
## A shot's ballistics, what `ProjectileSpawner.spawn` builds a bullet from beside where it starts
## and the way it flies: whoever fills it (a gun, a grenade's fragments) sets what differs from a
## plain pistol round; a field left alone is that round's.

## The shooter's body, skipped in the bullet's sweep (null = none).
var shooter: Node = null
## Added to the bullet's base damage.
var item_damage: float = 0.0
## The bullet's damage outright, in place of its base plus `item_damage` (negative = that sum): a
## grenade's fragments deal their row's `fragment_damage`.
var damage: float = -1.0
## The speed the bullet leaves at, px/s (negative = `BallisticsFlightConfig.projectile_speed`).
var muzzle_speed: float = -1.0
## Its power to punch through what it hits (1 = a pistol round, higher goes further).
var penetration: float = 1.0
## How far it flies before it is spent, stopping exactly there, px (negative = the default of
## `Projectile.max_distance`).
var max_range: float = -1.0
## It may strike `shooter` as well (a grenade's fragments name their thrower as the attacker and
## hurt it).
var strikes_shooter: bool = false
