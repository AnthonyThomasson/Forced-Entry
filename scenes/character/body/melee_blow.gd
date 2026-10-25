class_name MeleeBlow extends RefCounted
## One frame of a melee strike (`body_strike.gd`, a punch's or a kick's): the circle it reaches at,
## the shove and damage it gives each body there, and how the log line names it.

## Where the strike lands (world px) and the radius of the circle it reaches.
var at := Vector2.ZERO
var radius := 0.0
## The shove each body struck takes, and the damage it is dealt.
var impulse := Vector2.ZERO
var damage := 0.0
## The strike's name in the log line, and what ends the line's bracket.
var what := ""
var note := ""


func _init(
	strike_at: Vector2,
	strike_radius: float,
	strike_impulse: Vector2,
	strike_damage: float,
	strike_what: String,
) -> void:
	at = strike_at
	radius = strike_radius
	impulse = strike_impulse
	damage = strike_damage
	what = strike_what
