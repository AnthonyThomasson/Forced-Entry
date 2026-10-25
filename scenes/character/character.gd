extends CharacterBody2D
## Character domain: a generic top-down character. It owns the body's health, its aim-based
## "facing" and the hit and push contracts, and holds a typed component per topic (`movement`,
## `inventory`, `weapon`, `ammo`, `stun`, `use`, `anatomy`, `wardrobe`). It reads its intent from
## a pluggable controller child (any node with a `control(character, delta)` method): the
## controller writes `movement.move_input` / `movement.aim_point` and calls `weapon.melee` /
## `weapon.shoot` / `inventory.select_slot`. Drawing is in character_visuals.gd; the body's animate
## parts (the living motion, the rig, the hands, the legs, the kick, the footsteps, the wounds, the
## shadow and the fall on death) are its `anatomy` (character_anatomy.gd), stepped here each physics
## frame.

## Emitted once when health drops to zero.
signal died
## Emitted when a blow lands on a body. `hand` is 0/1 for a melee punch, `KICK_HAND` for a leg kick,
## -1 for a shot; `damage` is the amount dealt (a punch scales it by its range of motion). Melee vs
## shot is told apart by `hand`, not by the damage value.
signal hit_landed(body: Node, damage: float, hand: int)

## The `hit_landed` hand code of a leg kick (0/1 are the punching hands, -1 a shot).
const KICK_HAND := 2
const CharacterRagdoll = preload("res://scenes/character/body/character_ragdoll.gd")

## Radius of the placeholder circle. Matches chair size (28x28 → 14 radius).
## Body circle radius (px).
@export var radius: float = 14.0
## Slot the character starts holding.
@export var start_slot: int = 1
## Allegiance tag, read by AI perception to tell allies from potential hostiles.
@export var faction: StringName = &"player"
## Maximum health. Characters start at this value; configurable per character in the inspector.
@export var max_health: float = 50.0

## Current health, initialised to max_health. Read-only outside this script.
var health: float
## True once the character has died; gates all movement and action permanently.
var is_dead: bool = false
## Unit vector from the character toward its aim point; read by the hands and visuals.
var facing := Vector2.RIGHT
## The controller's intent, the posture, running and stamina, knockback and the push slow
## (`character_movement.gd`).
var movement := CharacterMovement.new(self)
## The items carried and the held slot (`character_inventory.gd`).
var inventory := CharacterInventory.new(self)
## The held item's use: firing, melee, the raise, recoil and aim (`character_weapon.gd`).
var weapon := CharacterWeapon.new(self)
## The magazines carried and the reload (`character_ammo.gd`).
var ammo := CharacterAmmo.new(self)
## The stun (a grenade's flash and bang; `take_stun`; `character_stun.gd`).
var stun := CharacterStun.new(self)
## What occupies the body: an object interaction, a vehicle ride, and the collision exceptions
## both leave behind (`character_use.gd`).
var use := CharacterUse.new(self)
## The body's animate parts: the pose, the rig, the hands, the legs, the kick, the footsteps, the
## wounds, the shadow and the fall (`body/character_anatomy.gd`).
var anatomy := CharacterAnatomy.new(self)
## How it is drawn and what it wears: its style, look seed and rank, and its `Outfit` (the
## `Wardrobe` child, `character_wardrobe.gd`; found in `_enter_tree`, before any child's `_ready`).
var wardrobe: CharacterWardrobe


func _enter_tree() -> void:
	wardrobe = $Wardrobe as CharacterWardrobe


func _ready() -> void:
	# The group every domain finds the world's characters by (interface 7).
	add_to_group(&"characters")
	# Top-down: no floor/ceiling, so a moving body it touches is never ridden as a platform.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Build the body's collision circle to match `radius`.
	var circle := CircleShape2D.new()
	circle.radius = radius
	($CollisionShape2D as CollisionShape2D).shape = circle

	health = max_health

	movement.controller = _find_controller()
	inventory.stock()
	ammo.restock(ammo.spare_magazine_types)
	anatomy.attach()
	# Re-emit the hands' punch as a unified hit_landed (melee → hand 0/1, with its dealt damage).
	anatomy.hands.punched.connect(_on_punched)
	anatomy.kick.kicked.connect(_on_kicked)
	use.attach()


func _physics_process(delta: float) -> void:
	_physics_step(delta)
	use.restore_cleared()
	anatomy.turn_shadow()


## One physics frame of the body: a dead one's ragdoll, else the controller's intent, the ride or
## interaction, and the walk.
func _physics_step(delta: float) -> void:
	if is_dead:
		anatomy.step(delta)
		return

	movement.tick(delta)
	stun.update(delta)
	# Items keep their own clocks (a gun's time between rounds, a grenade's wind-up); tick them
	# before the controller pulls the trigger, so a round that is due this frame can leave this
	# frame.
	inventory.tick(delta)
	# Pull intent from the controller first, so facing/movement use this frame's input.
	movement.pull(delta)
	# A ride in a vehicle overrides the controller's intent: it walks the character to the door,
	# poses it in and out, and hands its keys on to the vehicle from the driver's seat.
	use.control(delta)
	ammo.update(delta)
	# A ride or an interaction holds the body still: no move_and_slide, aim, knockback or push.
	if use.hold_frame(delta):
		return
	_walk_frame(delta)


## One physics frame on foot: the aim turned, the walk moved and slid, the pushes, then the body
## (`anatomy.step`: the kick, the pose, the legs and the footsteps).
func _walk_frame(delta: float) -> void:
	# Aim toward the aim point. Guard the degenerate zero-length case.
	var to_aim := movement.aim_point - global_position
	if to_aim.length() > 0.001:
		facing = _turned_toward(to_aim.normalized(), delta)
	# A parent's _physics_process runs before its children's, so the hands see this fresh
	# facing on the same frame.
	anatomy.hands.facing = facing
	weapon.update_raise(delta)
	movement.walk(delta)
	anatomy.step(delta)


## `facing` turned toward the unit vector `want`: at once standing, but no faster than the posture's
## `turn` rate (rad/s) crouched, so a low body takes longer to come round. The aim point itself is
## never held back.
func _turned_toward(want: Vector2, delta: float) -> Vector2:
	var rate: float = CharacterPostureConfig.postures[movement.posture()]["turn"]
	if rate <= 0.0:
		return want
	var step := rate * delta
	return facing.rotated(clampf(facing.angle_to(want), -step, step)).normalized()


## A punch landed: surface it as hit_landed and post a world `&"hit"` event (like a projectile's)
## so listeners such as the AI learn who struck whom. The event is a `punch` outcome on the struck
## `material` (what its surface reports; "" for a wall or anything without one).
func _on_punched(hand: int, body: Node, damage: float) -> void:
	_post_melee_hit(hand, body, damage)


## A kick landed: the same `hit_landed` and `&"hit"` event as a punch (hand code `KICK_HAND`,
## outcome `punch`).
func _on_kicked(body: Node, damage: float) -> void:
	_post_melee_hit(KICK_HAND, body, damage)


## Surface a landed blow (`hand`: 0/1 punch, `KICK_HAND` kick) as `hit_landed` and the `&"hit"`
## event.
func _post_melee_hit(hand: int, body: Node, damage: float) -> void:
	hit_landed.emit(body, damage, hand)
	var pos: Vector2 = body.global_position if body is Node2D else global_position
	var surface_material := ""
	if body.has_method("get_surface"):
		surface_material = String(body.get_surface().get("material", ""))
	EventBus.post(&"hit", {
		"position": pos, "victim": body, "attacker": self,
		"direction": facing, "damage": damage, "outcome": &"punch", "material": surface_material,
	})


# --- Item-facing API (what an Item may call on its user) --------------------------------


## The scene node transient projectiles/casings/debris spawn into (world space, not under us).
func world_root() -> Node:
	return get_parent()


## An item forwards a projectile hit here so the character can surface it (HUD).
func report_shot(body: Node, damage: float) -> void:
	hit_landed.emit(body, damage, -1)


# --- The stun (a grenade's flash and bang; docs/grenades.md G13) -------------------------


## An explosion's stun (interface 3): blind and deafen the character for `blind` and `deaf` seconds
## (`stun.take`).
func take_stun(blind: float, deaf: float) -> void:
	stun.take(blind, deaf)


# --- Hittable contract (struck by projectiles: flesh surface + deformation) -------------


## The character's ballistic surface: partial cover (the body's height, so a lower posture is struck
## by fewer shots and hides behind lower cover), low penetration, flesh material and a base color
## for debris styling. Read by the Projectile System.
func get_surface() -> Dictionary:
	return {
		"coverage": CharacterPostureConfig.postures[movement.posture()]["coverage"],
		"penetration": CharacterHitConfig.flesh_penetration,
		"material": CharacterHitConfig.flesh_material,
		"color": CharacterHitConfig.flesh_color,
	}


## The surface a round flying at `height` (0..100) along `direction` meets (the Projectile System
## asks before it resolves): the body's own (`get_surface()`) where nothing protects it, else the
## armour over that zone and side (`Outfit.layer`): its `penetration`, `material` and `color`, plus
## `stop_power` (a round below it is stopped) and `inner_material` (the flesh a round that gets
## through strikes). A `height` below 0 is the plain surface.
func get_surface_at(height: float, direction: Vector2) -> Dictionary:
	var surface := get_surface()
	if height < 0.0:
		return surface
	var armour := wardrobe.outfit.layer(_hit_zone(height), _hit_side(direction))
	if armour.is_empty():
		return surface
	surface["inner_material"] = surface["material"]
	surface.merge(
		{
			"penetration": armour["penetration"], "material": armour["material"],
			"color": armour["color"], "stop_power": armour["stop_power"],
		},
		true,
	)
	return surface


## The hit zone (`&"feet"`, `&"legs"`, `&"torso"`, `&"head"`) a round at `height` (0..100) strikes:
## its height over the posture's coverage against `CharacterHitConfig.zones`. `&""` for no height
## (below 0: a blast, the whole body).
func _hit_zone(height: float) -> StringName:
	if height < 0.0:
		return &""
	var share := height / maxf(movement.posture_coverage(movement.posture()), 0.001)
	for row: Array in CharacterHitConfig.zones:
		if share <= float(row[1]):
			return row[0]
	return &"head"


## The side (`&"front"`, `&"flank"`, `&"back"`) a blow travelling along `direction` strikes: the
## angle between the way back along it and the shoulders' facing (`pose.torso_angle`) against
## `CharacterHitConfig.side_front_deg` / `side_back_deg`.
func _hit_side(direction: Vector2) -> StringName:
	if direction.length() < 0.001:
		return &"front"
	var shoulders := Vector2.from_angle(anatomy.pose.torso_angle)
	var off := rad_to_deg(absf(shoulders.angle_to(-direction)))
	if off <= CharacterHitConfig.side_front_deg:
		return &"front"
	return &"back" if off >= CharacterHitConfig.side_back_deg else &"flank"


## Take a hit: shove along the impact (folded into locomotion via the pushable path), then hurt by
## where it struck (the striker fills in a HitInfo; `docs/outfits.md` O2 to O9). A round's zone
## (`_hit_zone` of its `height`) scales its damage (`CharacterHitConfig.zone_damage`). Where armour
## covers that zone and side (`Outfit.layer`), the hit wears its plate, and a round that did not get
## through it (`penetrated` false: stopped or glanced off) deals only the armour's `blunt` share: no
## wound, no blood, its debris the armour's; one that got through deals all but the armour's
## `reduction`. A hit with no height (a frag's blast) strikes the whole body, cut by the torso
## armour's `blast`. A wound records the deformation relative to the shoulders (it dents the drawn
## body and hands and turns with them), sprays blood debris and starts the bleeding (BloodWound).
func take_hit(hit: HitInfo) -> void:
	apply_impulse(Physics.impact_impulse(hit))
	var side := _hit_side(hit.direction)
	var outfit := wardrobe.outfit
	if hit.height < 0.0:
		_wound_by(hit, hit.damage * (1.0 - float(outfit.layer(&"torso", side).get("blast", 0.0))))
		return
	var zone := _hit_zone(hit.height)
	var damage := hit.damage * float(CharacterHitConfig.zone_damage.get(zone, 1.0))
	var armour := outfit.layer(zone, side)
	if armour.is_empty():
		_wound_by(hit, damage)
		return
	outfit.wear(zone, side, hit.damage)
	if hit.penetrated:
		_wound_by(hit, damage * (1.0 - float(armour["reduction"])))
		return
	Physics.spawn_debris(
		get_parent(),
		hit,
		get_surface().merged({ "material": armour["material"], "color": armour["color"] }, true),
	)
	_apply_damage(damage * float(armour["blunt"]), hit.direction)


## A hit that wounds: the dent, the blood debris and the bleeding (`anatomy.wound_by`), and `damage`
## off health.
func _wound_by(hit: HitInfo, damage: float) -> void:
	anatomy.wound_by(hit)
	_apply_damage(damage, hit.direction)


## Reduce health by `amount`; called by the punch path (projectile path goes through take_hit).
func take_damage(amount: float) -> void:
	_apply_damage(amount)


## Apply `amount` of damage to health (shared by the punch and projectile paths), dying at zero;
## `direction` is the blow's (zero when unknown), which the body falls along.
func _apply_damage(amount: float, direction := Vector2.ZERO) -> void:
	if is_dead:
		return
	health = maxf(health - amount, 0.0)
	if health == 0.0:
		_die(direction)


## Mark the character dead and let the body fall: the ragdoll takes over from the live pose with the
## momentum it had (walk + any shove, including the killing blow's), toppling along `direction`, and
## the hand lets go of what it held. Emits `died` for observers.
func _die(direction: Vector2) -> void:
	is_dead = true
	ammo.cancel()
	# The body stops bleeding, is drawn beneath the living and casts no shadow.
	anatomy.die()
	# A corpse is just a body on the floor: clear its collision layer so the living (and bullets,
	# punches, sight lines and the dropped item, all on layer 1) pass right over it instead of being
	# blocked.
	collision_layer = 0
	use.end_interaction()
	use.abandon()  # Killed boarding or getting out: the ride ends where the body is.
	var momentum := movement.momentum()
	# The body falls from the standing skeleton, whatever it was doing.
	movement.stand_up()
	movement.fold(0.0)
	stun.clear()  # A dead body sees and hears nothing more to fade.
	anatomy.fall(momentum, direction)
	inventory.drop_held(momentum)
	velocity = Vector2.ZERO
	died.emit()


## Where this body's blood leaves it (world): its position while alive; once fallen, the middle of
## the trunk where it lies. Blood pools sample it, so they spill from the body, not where it stood.
func blood_origin() -> Vector2:
	var ragdoll := anatomy.ragdoll
	if ragdoll == null:
		return global_position
	var mid: Vector3 = ((ragdoll.point(CharacterRagdoll.CHEST)
			+ ragdoll.point(CharacterRagdoll.PELVIS)) * 0.5)
	return global_position + Vector2(mid.x, mid.y)


## Total accumulated hit damage this character has taken, read from its deformation record. Lets a
## controller sense how hurt the character is (0 when unscathed).
func damage_taken() -> float:
	return anatomy.deformable.damage_total if anatomy.deformable else 0.0


# --- Pushable contract (interface 5: Knockback transfers, blasts, a walking character, punch, kick)


## Take a shove; divided by mass and folded into locomotion. `_at` (the contact offset from the
## origin) is the pushable contract's; a character does not turn, so a shove anywhere on it is a
## central one.
func apply_impulse(impulse: Vector2, _at := Vector2.ZERO) -> void:
	movement.knock(impulse)


## An explosion's shove: away from the blast point `from`, `impulse` hard (the units of
## `apply_impulse`). A living character is knocked back like any shove; a dead one's ragdoll is
## thrown (and woken, if it had come to rest).
func blast_push(from: Vector2, impulse: float) -> void:
	var away := ((global_position - from).normalized()
			if global_position.distance_squared_to(from) > 0.01
			else Vector2.RIGHT)
	if is_dead:
		anatomy.ragdoll.blast(away * impulse / get_mass())
	else:
		apply_impulse(away * impulse)


## The character's mass, used by pushers to scale their shove.
func get_mass() -> float:
	return maxf(CharacterPushConfig.player_mass, 0.5)


## First child that can drive this character (has a `control` method).
func _find_controller() -> Node:
	for child in get_children():
		if child.has_method("control"):
			return child
	return null
