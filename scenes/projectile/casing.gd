extends Node2D
## Projectile System: a spent shell tossed out when a gun fires: colliderless world-space debris
## that tweens out, spins, and rests. Despawner-tracked. Drawing lives in casing_visuals.gd.

## The chip debris of the Physics System, whose toss a casing shares.
const Debris = preload("res://scenes/physics/debris.gd")

## Brass fill color.
@export var color: Color = Color(0.85, 0.7, 0.3)
## How far the casing travels as it is ejected (px).
@export var eject_distance: float = 15.0
## Seconds spent flying out before it comes to rest.
@export var eject_time: float = 0.3


func _ready() -> void:
	# On the floor: beneath the player, furniture and a vehicle's chassis.
	z_index = DrawLayers.LYING


## Kick the casing out along `eject_dir` (need not be normalized) and let it settle, a whole turn
## either way (Physics' `Debris.toss`).
func start(eject_dir: Vector2) -> void:
	Debris.toss(self, eject_dir, eject_distance, eject_time, TAU * (1.0 if randf() > 0.5 else -1.0))
