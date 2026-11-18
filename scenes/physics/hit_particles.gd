class_name HitParticles
## Physics System: one-shot particle bursts where a projectile enters and leaves an object, styled
## by the struck surface's material. Stateless statics like DebrisSpawner; a burst is plain data (a
## dict, below), no node: `PhysicsFxHook.burst_made` hands it to the 3D render, which flings the
## cubes. Switched by PhysicsConfig.hit_particles_enabled (+ hit_particles_scale / _max).

## ENTRY: where a round goes in and out the other side (weak: the exit carries the burst). EXIT:
## where it leaves (the strongest a burst gets). IMPACT: a hit that does not pass through (blocked,
## ricochet, no exit found): one burst on the surface, as strong as an exit.
enum Kind {
	ENTRY,
	EXIT,
	IMPACT,
}

## Per-material burst style, keyed by material tag ("default" covers walls and unlisted tags).
##   amount  — particles per burst
##   life    — seconds each particle lives
##   speed   — Vector2(min, max) launch speed (px/s)
##   spread  — half-angle (degrees) of the cone around the burst direction
##   damping — velocity lost per second, so particles slow to a stop rather than fly on
##   size    — Vector2(min, max) square side (px)
##   tint    — how _color() recolors the object's base color
const STYLES := {
	"wood": {
		"amount": 8,
		"life": 0.45,
		"speed": Vector2(60, 150),
		"spread": 55.0,
		"damping": 160.0,
		"size": Vector2(1.5, 3.5),
		"tint": "wood",
	},
	"metal": {
		"amount": 10,
		"life": 0.3,
		"speed": Vector2(120, 320),
		"spread": 40.0,
		"damping": 220.0,
		"size": Vector2(1.0, 2.0),
		"tint": "spark",
	},
	"glass": {
		"amount": 12,
		"life": 0.5,
		"speed": Vector2(90, 260),
		"spread": 70.0,
		"damping": 150.0,
		"size": Vector2(1.0, 2.5),
		"tint": "glass",
	},
	"ceramic": {
		"amount": 9,
		"life": 0.45,
		"speed": Vector2(70, 190),
		"spread": 60.0,
		"damping": 170.0,
		"size": Vector2(1.5, 3.0),
		"tint": "light",
	},
	"fabric": {
		"amount": 6,
		"life": 0.7,
		"speed": Vector2(25, 70),
		"spread": 80.0,
		"damping": 70.0,
		"size": Vector2(2.0, 4.0),
		"tint": "soft",
	},
	"foliage": {
		"amount": 8,
		"life": 0.6,
		"speed": Vector2(40, 110),
		"spread": 75.0,
		"damping": 90.0,
		"size": Vector2(1.5, 3.0),
		"tint": "leaf",
	},
	"flesh": {
		"amount": 10,
		"life": 0.5,
		"speed": Vector2(60, 190),
		"spread": 45.0,
		"damping": 170.0,
		"size": Vector2(1.5, 3.0),
		"tint": "blood",
	},
	"blood": {
		"amount": 8,
		"life": 0.45,
		"speed": Vector2(50, 150),
		"spread": 60.0,
		"damping": 170.0,
		"size": Vector2(1.5, 2.5),
		"tint": "blood",
	},
	"default": {
		"amount": 7,
		"life": 0.55,
		"speed": Vector2(35, 100),
		"spread": 65.0,
		"damping": 110.0,
		"size": Vector2(1.5, 3.5),
		"tint": "dust",
	},
}
## An exit burst (and a lone impact) is the full-strength one: the round tears out what it pushed
## through.
const EXIT_AMOUNT := 1.4
const EXIT_SPEED := 1.3
const EXIT_SPREAD := 0.75
## A penetrating round's entry burst is a fraction of that: much weaker than the exit.
const ENTRY_AMOUNT := 0.35
const ENTRY_SPEED := 0.6


## Burst `kind` particles for `hit`: an ENTRY or IMPACT burst at `hit.position`, thrown out along
## the surface normal (back along the shot when the normal is degenerate), an EXIT burst at
## `hit.exit_position`, thrown on along the shot. `surface` is the struck object's get_surface()
## (its `material` picks the style, its `color` tints it); `strength` (~0.5..1.5) scales how many
## particles and how fast, from how hard the hit was. Returns the burst, told to the 3D render
## (`PhysicsFxHook.burst_made`):
## `{ at, direction (unit), amount, spread (degrees either side of it), speed_min, speed_max
## (px/s), damping_min, damping_max (px/s lost), size_min, size_max (px), life, life_random (the
## share of it a particle may lose), color, spark (the metal style's own lit-whatever-the-light
## kind), height (the hit's, px up; negative: the floor) }`;
## empty when switched off or the count rounds to nothing.
static func spawn(
	hit: HitInfo,
	surface: Dictionary,
	kind: Kind,
	strength: float = 1.0,
) -> Dictionary:
	if not PhysicsConfig.hit_particles_enabled:
		return {}
	var material: String = surface.get("material", "")
	var style: Dictionary = STYLES.get(material, STYLES["default"])
	var amount := int(round(float(style["amount"])
			* (EXIT_AMOUNT if kind != Kind.ENTRY else ENTRY_AMOUNT)
			* strength * PhysicsConfig.hit_particles_scale))
	amount = mini(amount, PhysicsConfig.hit_particles_max)
	if amount <= 0:
		return {}
	var direction := _direction(hit, kind)
	var burst := _burst(style, kind, strength)
	burst["amount"] = amount
	burst["direction"] = direction.normalized() if direction.length() > 0.001 else Vector2.UP
	burst["color"] = _color(surface.get("color", Color(0.6, 0.6, 0.6)), style["tint"])
	burst["at"] = hit.exit_position if kind == Kind.EXIT else hit.position
	burst["spark"] = style["tint"] == "spark"
	burst["height"] = hit.height
	PhysicsFxHook.burst_made(burst)
	return burst


## Which way a `kind` burst for `hit` is thrown: out along the surface normal (back along the shot
## when the normal is degenerate), or for an exit on along the shot past the exit normal.
static func _direction(hit: HitInfo, kind: Kind) -> Vector2:
	if kind != Kind.EXIT:
		return hit.spray_direction()
	var out := hit.exit_normal if hit.exit_normal.length() > 0.001 else hit.direction
	return (out + hit.direction).normalized()


## A `kind` burst of `strength` styled by `style` (its count, direction, colour, place and height
## still to set).
static func _burst(style: Dictionary, kind: Kind, strength: float) -> Dictionary:
	var speed: Vector2 = style["speed"]
	var size: Vector2 = style["size"]
	var boost := (EXIT_SPEED if kind != Kind.ENTRY else ENTRY_SPEED) * strength
	return {
		"life": style["life"],
		"life_random": 0.4,
		"spread": float(style["spread"]) * (EXIT_SPREAD if kind == Kind.EXIT else 1.0),
		"speed_min": speed.x * boost,
		"speed_max": speed.y * boost,
		"damping_min": float(style["damping"]) * 0.8,
		"damping_max": float(style["damping"]) * 1.2,
		"size_min": size.x,
		"size_max": size.y,
	}


## A burst colour from the object's base colour per the style's tint mode.
static func _color(base: Color, mode: String) -> Color:
	var color: Color
	match mode:
		"spark":
			color = Color(1.0, 0.92, 0.65) if randf() < 0.6 else Color(0.75, 0.77, 0.8)
		"glass":
			color = base.lerp(Color(0.85, 0.92, 1.0), 0.55)
			color.a = 0.8
		"light":
			color = base.lightened(0.25)
		"leaf":
			color = base.lerp(Color(0.3, 0.5, 0.2), 0.4)
		"soft":
			color = base.lightened(0.08)
		"blood":
			color = Color(0.6, 0.05, 0.06)
		"dust":
			color = base.lerp(Color(0.75, 0.75, 0.72), 0.55)
		_:  # "wood": the splinters and pale core of the object's own wood
			color = base.lightened(0.15)
	return color
