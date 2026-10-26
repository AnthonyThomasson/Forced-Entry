extends RigidBody2D
## An Objects-domain world object (furniture, decor). Owns its surface data (shape, size,
## color, cover/penetration ratings, material, mass) and, through its `physics` part
## (object_physics.gd), composes three Physics components — a Knockback child (RigidBody2D adapter,
## how take_hit shoves it), a Deformable child (damage dents/chunks) and, on a solid piece, a
## BloodSmear child (drags blood out of a puddle). The engine integrates its motion, collisions and
## pivoting. It exposes the two contracts the rest of the game talks to it through, and nothing
## else:
##   • get_surface() / take_hit(HitInfo)  — the "hittable" contract (Projectile, melee)
##   • apply_impulse(Vector2, at) / get_mass() — the "pushable" contract (blasts, a character's
##     push, legs, punch, kick)
##   • get_lights() — the lights it gives (object_lights.gd), which the Lighting domain reads
##     duck-typed
## A solid piece also casts a shadow: a LightOccluder2D over its footprint (on General's
## `LightMasks`), a child so it follows a shove, built here as its physics part builds its collider.
## The force and deformation MATH lives in the Physics domain; this file only wires it up.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const ObjectLights = preload("res://scenes/objects/object_lights.gd")
const ObjectLook = preload("res://scenes/objects/object_look.gd")
const ObjectPhysics = preload("res://scenes/objects/object_physics.gd")
## The sides of a round piece's shadow footprint.
const OCCLUDER_SIDES := 12

## "circle", "square", or "rect".
@export var shape_type: String = "circle"
## Label drawn on the object.
@export var object_name: String = "Object"
## Footprint in px.
@export var size: Vector2 = Vector2(60, 60)
## Fill color.
@export var color: Color = Color.GRAY
## Non-solid objects (rugs, mats) get no collider and draw beneath everything else.
@export var solid: bool = true
## A solid piece that never moves (a streetlight's post): frozen static, so no shove, kick, round or
## blast moves or turns it; it is still struck, dented and throws debris. Ignored on a non-solid
## piece (decor is frozen anyway).
@export var anchored: bool = false
## Descriptive material tag (e.g. "wood", "fabric", "metal", "glass"). "wood"/"fabric"
## also drive the room-palette recolor. Named `object_material` to avoid colliding with
## CanvasItem's built-in `material`.
@export var object_material: String = ""
## Coverage rating 0–100, a height/cover proxy (flat decor 0 … tall storage 90+).
@export var coverage: float = 0.0
## Penetration value 0–100: resistance to being shot through (soft low, metal high).
@export var penetration: float = 0.0
## Mass used for knockback: a shove's impulse is divided by this. Set from the catalog.
@export var weight: float = 10.0
## Interactions this object offers, as plain data dicts (id, label, optional move_to /
## requires_item). Read by the Interaction domain via get_interactions(); empty means none.
@export var interactions: Array = []

## What its visuals draw (`object_look.gd`): `art`, `art_opts`, `facing`, `text_color`. Built here,
## so it exists before `ObjectFactory` fills it.
var look := ObjectLook.new()
## Its Physics components (`object_physics.gd`: Knockback, Deformable, BloodSmear), its collider and
## a cloth piece's BloodSurface. Built here, holding the piece; composed in _ready().
var physics := ObjectPhysics.new(self)
## What `get_lights()` declares (worked out once its visuals are ready).
var _lights: Array = []


func _ready() -> void:
	physics.compose()

	# The visuals (a child, ready first) have built their light-source overlay, which a light dims
	# with.
	_lights = ObjectLights.of(self)
	if solid:
		physics.build_collider()
		_build_occluder()
		physics.add_smear()
		if anchored:
			# Frozen static: the physics server gives it no inverse mass, so every impulse (a push,
			# a kick, a blast) is ignored and a body striking it stops as at a wall; queries and the
			# hittable contract still find it.
			freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
			freeze = true
	else:
		# Non-solid decor never moves or collides: freeze it (a shapeless RigidBody2D would
		# be invalid) and draw it beneath everything else.
		freeze = true
		z_index = ObjectArtLayerConfig.rug_z_index
		physics.soak()


func _exit_tree() -> void:
	physics.release()


# --- Hittable contract (read/hit by projectiles, melee, …) -----------------------------


## The object's ballistic surface: how much it covers, how hard it is to shoot through,
## its material tag and its color (for debris styling: the colour its art is drawn in). Read by the
## Projectile System.
func get_surface() -> Dictionary:
	return { "coverage": coverage, "penetration": penetration, "material": object_material,
		"color": ObjectArt.drawn_color(color) if look.art != "" else color }


## The hit marks on this object (dicts with `pos`, `depth`, `blood`, …), oldest first.
func hit_marks() -> Array:
	return physics.deformable.impacts


## Take a hit: shove along the impact at the contact point (so an off-center hit spins the
## object; an anchored piece is not shoved), record the deformation, and spray debris. The striker
## fills in a HitInfo.
func take_hit(hit: HitInfo) -> void:
	if not anchored:
		physics.knockback.apply_impulse(Physics.impact_impulse(hit), hit.position)
	physics.deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())


# --- Lights (read duck-typed by the Lighting domain) -----------------------------------


## The lights this piece gives, as plain dicts in its own frame (`offset`, `turn`, `colour`,
## `energy`, `radius`, `shape`, `rhythm`, `room_light`, `street`, `height`, `glow`: see
## object_lights.gd); empty for a piece that gives none.
func get_lights() -> Array:
	return _lights


# --- Interactable contract (read by the Interaction domain) ----------------------------


## The interactions this object offers (plain data dicts; see the Interaction domain). The
## object holds no interaction logic — it only advertises the actions. Empty if none.
func get_interactions() -> Array:
	return interactions


# --- Pushable contract (interface 5: blasts, a character's walking push, legs, punch, kick) ---
# Both halves are served by RigidBody2D's native methods: apply_impulse(v, at) (`at` the contact
# offset from the origin, so a shove off the centre turns the piece; omitted = a central shove) and
# get_mass() (returns `mass`, which Knockback sets from `weight`). Nothing to add: an anchored piece
# is frozen static, which the engine never moves.

# --- Shadow (built in code, like the collider) ---------------------------------------


## The piece's shadow: an occluder over its undented footprint (its rect, or a circle as a
## `OCCLUDER_SIDES`-gon: a shadow needs no more, and every edge is drawn into each light's shadow
## map; dents are too small to show in one). A piece that gives light is on `LightMasks.EMITTER`, so
## its own light, sitting inside it, is never shut in; one as tall as `LightMasks.TALL_COVERAGE` on
## `TALL` (it shadows the low lights too); the rest on `FURNITURE`. None while `LightMasks.shadows`
## is off.
func _build_occluder() -> void:
	var poly := PackedVector2Array()
	if shape_type == "circle":
		for k in OCCLUDER_SIDES:
			poly.append(Vector2.RIGHT.rotated(TAU * k / OCCLUDER_SIDES) * size.x * 0.5)
	else:
		var h := size * 0.5
		poly = PackedVector2Array([-h, Vector2(h.x, -h.y), h, Vector2(-h.x, h.y)])
	var bit := LightMasks.FURNITURE
	if not _lights.is_empty():
		bit = LightMasks.EMITTER
	elif coverage >= LightMasks.TALL_COVERAGE:
		bit = LightMasks.TALL
	var occ := LightMasks.occluder(poly, bit)
	if occ != null:
		add_child(occ)
