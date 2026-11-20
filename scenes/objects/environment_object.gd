extends Node2D
## An Objects-domain world object (furniture, decor), a plain `Node2D` plan handle (no engine body,
## no 2D shape: its place and turn are the plan's, in the groups `TwinSpace.BODIES` and `PIECES`).
## Owns its surface data (shape, size, color, penetration, material, mass) and, through its
## `physics` part (object_physics.gd), composes two Physics components — a Knockback child (the
## piece's mass and how take_hit shoves it), a Deformable child (damage dents/chunks) — and, on a
## solid piece, a BloodSmear child (drags blood out of a puddle). The 3D twin the twin space builds
## from its parts (`ObjectTwins`, `PieceHeights`) is its body: a free piece is a `PieceBody`
## (`RigidBody3D`) that moves it, an anchored or wall-hung one a static twin, a non-solid one
## (a rug) has none. It exposes the two contracts the rest of the game talks to it through, and
## nothing else:
##   • get_surface() / take_hit(HitInfo)  — the "hittable" contract (Projectile, melee)
##   • apply_impulse(Vector2, at) / get_mass() — the "pushable" contract (blasts, a character's
##     push, legs, punch, kick). A pusher goes through `Knockback.push`, which shoves a piece
##     through its free 3D body at the push's real height
##   • get_lights() — the lights it gives (object_lights.gd), which the Lighting domain reads
##     duck-typed
## The force and deformation MATH lives in the Physics domain; this file only wires it up.

## The piece's dents were cut again (its silhouette changed): what a mesh built from them follows
## (the carrier builds it again).
signal reshaped

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const ObjectLights = preload("res://scenes/objects/object_lights.gd")
const ObjectLook = preload("res://scenes/objects/object_look.gd")
const ObjectPhysics = preload("res://scenes/objects/object_physics.gd")

## "circle", "square", or "rect".
@export var shape_type: String = "circle"
## The piece's name.
@export var object_name: String = "Object"
## Footprint in px.
@export var size: Vector2 = Vector2(60, 60)
## Fill color.
@export var color: Color = Color.GRAY
## Non-solid objects (rugs, mats) get no twin (no body at all) and draw beneath everything else.
@export var solid: bool = true
## A solid piece that never moves (a streetlight's post): its twin is a static body, so no shove,
## kick, round or blast moves or turns it; it is still struck, dented and throws debris. Ignored on
## a non-solid piece (decor never moves anyway).
@export var anchored: bool = false
## Descriptive material tag (e.g. "wood", "fabric", "metal", "glass"). "wood"/"fabric"
## also drive the room-palette recolor. Named `object_material` to avoid colliding with
## CanvasItem's built-in `material`.
@export var object_material: String = ""
## Penetration value 0–100: resistance to being shot through (soft low, metal high).
@export var penetration: float = 0.0
## Mass used for knockback: a shove's impulse is divided by this. Set from the catalog.
@export var weight: float = 10.0
## Interactions this object offers, as plain data dicts (id, label, optional move_to /
## requires_item). Read by the Interaction domain via get_interactions(); empty means none.
@export var interactions: Array = []

## What its mesh shows (`object_look.gd`): `art`, `art_opts`, `facing`, `overhang`. Built here,
## so it exists before `ObjectFactory` fills it.
var look := ObjectLook.new()
## Its Physics components (`object_physics.gd`: Knockback, Deformable, BloodSmear) and a cloth
## piece's BloodSurface. Built here, holding the piece; composed in _ready().
var physics := ObjectPhysics.new(self)
## How many times its footprint hull changed since it was twinned (a tipped piece's turning over
## reshapes it): what the blood smear is laid across.
var footprint_stamp := 0
## What `get_lights()` declares (worked out once, in `_ready`).
var _lights: Array = []


func _enter_tree() -> void:
	# a plan handle the twin space twins (and the game finds bodies and pieces by)
	add_to_group(TwinSpace.BODIES)
	add_to_group(TwinSpace.PIECES)


func _ready() -> void:
	physics.compose()

	_lights = ObjectLights.of(self)
	if solid:
		physics.add_smear()
	else:
		# Non-solid decor never moves or collides: it has no twin, and a cloth piece soaks blood
		physics.soak()


func _exit_tree() -> void:
	physics.release()


## Its silhouette changed (its dents were cut again): tell what is built from it.
func reshape() -> void:
	reshaped.emit()


# --- Hittable contract (read/hit by projectiles, melee, …) -----------------------------


## The object's ballistic surface: how hard it is to shoot through, its material tag and its color
## (for debris styling: the colour its art is drawn in). Read by the Projectile System. What it
## covers is its real shape in the twin space (`PieceHeights`, interface 28), not a number here.
func get_surface() -> Dictionary:
	return { "penetration": penetration, "material": object_material,
		"color": ObjectArt.drawn_color(color) if look.art != "" else color }


## The hit marks on this object (dicts with `pos`, `depth`, `blood`, …), oldest first.
func hit_marks() -> Array:
	return physics.deformable.impacts


## Take a hit: shove along the impact at the contact point (so an off-center hit spins the
## object; an anchored piece is not shoved), record the deformation, and spray debris. The striker
## fills in a HitInfo.
func take_hit(hit: HitInfo) -> void:
	if not anchored:
		physics.knockback.apply_impulse(Physics.impact_impulse(hit), hit.position, hit.height)
	physics.deformable.record(hit)
	Physics.spawn_debris(get_parent(), hit, get_surface())


# --- Lights (read duck-typed by the Lighting domain) -----------------------------------


## The lights this piece gives, as plain dicts in its own frame (`offset`, `turn`, `colour`,
## `energy`, `radius`, `shape`, `rhythm`, `room_light`, `street`, `height`: see
## object_lights.gd); empty for a piece that gives none.
func get_lights() -> Array:
	return _lights


# --- Interactable contract (read by the Interaction domain) ----------------------------


## The interactions this object offers (plain data dicts; see the Interaction domain). The
## object holds no interaction logic — it only advertises the actions. Empty if none.
func get_interactions() -> Array:
	if not is_tipped():
		return interactions
	# a tipped piece lies on its side (D14): nothing that puts a character on or at it (sit, lie)
	return interactions.filter(
		func(spec: Dictionary) -> bool: return not spec.get("move_to", false)
	)


## Whether the piece has tipped over (its 3D body leans more than `PieceBodyConfig.tipped_degrees`).
func is_tipped() -> bool:
	var body := TwinSpace.twin_for(self) as PieceBody
	return body != null and body.tipped()


## Its footprint is now `hull` (a polygon in its own frame): that of its tipped 3D body
## (`PieceBody.twin_update`). Dents recorded meanwhile are cut again when it is upright.
func set_tipped_footprint(hull: PackedVector2Array) -> void:
	physics.set_tipped_footprint(hull)


## The piece is upright again: its footprint is its silhouette as its dents have left it.
func restore_footprint() -> void:
	physics.restore_footprint()


# --- Pushable contract (interface 5: blasts, a character's walking push, legs, punch, kick) ---
# A piece is a plan handle: the twin space's free 3D body (`PieceBody`) is what moves, so a pusher
# calls `Knockback.push(piece, v, at, height)`, which shoves that body at the push's height. The
# methods here answer the contract for a caller that asks by name (`apply_impulse(v, at)`,
# `get_mass()`): a shove given to a piece with no free 3D body (an anchored or wall-hung piece,
# decor, a world with no twin space) moves nothing.


## The piece's mass: its catalogue `weight`, floored so featherweight decor still reacts.
func get_mass() -> float:
	return Knockback.mass_of(weight)


## Shove the piece by `impulse` (plan space) at `at` px from its origin: through its free 3D body
## when it has one, else nothing moves it.
func apply_impulse(impulse: Vector2, at: Vector2 = Vector2.ZERO) -> void:
	var lead := TwinSpace.leader_of(self)
	if lead != null:
		lead.call(&"push", impulse, at, -1.0)
