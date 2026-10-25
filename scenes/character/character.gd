extends CharacterBody2D
## Character domain: a generic top-down character. It owns the body, movement, aim-based "facing",
## the item inventory, and the knockback it takes from shoves. It reads its intent from a pluggable
## controller child (any node with a `control(character, delta)` method): the controller
## writes `movement.move_input` / `movement.aim_point` and calls `weapon.melee` / `weapon.shoot` /
## `inventory.select_slot`. Drawing is in character_visuals.gd, the hand/punch/fist geometry in
## character_hands.gd, the living motion of head, shoulders, hips and hands in character_pose.gd
## (stepped here each physics frame), the standing skeleton the limbs are drawn from in
## character_rig.gd, and the body's fall on death in character_ragdoll.gd (stepped here once dead).

## Emitted once when health drops to zero.
signal died
## Emitted when a blow lands on a body. `hand` is 0/1 for a melee punch, `KICK_HAND` for a leg kick,
## -1 for a shot; `damage` is the amount dealt (a punch scales it by its range of motion). Melee vs
## shot is told apart by `hand`, not by the damage value.
signal hit_landed(body: Node, damage: float, hand: int)

## The `hit_landed` hand code of a leg kick (0/1 are the punching hands, -1 a shot).
const KICK_HAND := 2
const CharacterPose = preload("res://scenes/character/body/character_pose.gd")
const CharacterRig = preload("res://scenes/character/body/character_rig.gd")
const CharacterRagdoll = preload("res://scenes/character/body/character_ragdoll.gd")
const CharacterFootsteps = preload("res://scenes/character/character_footsteps.gd")
const CharacterLegs = preload("res://scenes/character/body/character_legs.gd")
const CharacterKick = preload("res://scenes/character/body/character_kick.gd")

## Radius of the placeholder circle. Matches chair size (28x28 → 14 radius).
## Body circle radius (px).
@export var radius: float = 14.0
## Slot the character starts holding.
@export var start_slot: int = 1
## Allegiance tag, read by AI perception to tell allies from potential hostiles.
@export var faction: StringName = &"player"
## Maximum health. Characters start at this value; configurable per character in the inspector.
@export var max_health: float = 50.0
## The style it is drawn in (`docs/outfits.md`, styles; a key of `CharacterStyleConfig.styles`):
## `zenitex` or `trauma` (the invaders' police units), `merc` or `borg` (the defenders' crew). What
## it wears is drawn in the style, and its own variety (skin, hair, implants, the colours a defender
## found its garments in) is drawn from `look_seed`. Looks only: nothing it does changes. A
## character never given one is a `zenitex`. Set before `_ready` (as a prop) or with `set_style`.
@export var style: StringName = &"zenitex":
	set(v):
		style = v
		_look_revision += 1
## The seed of its own variety within its style.
@export var look_seed: int = 0:
	set(v):
		look_seed = v
		_look_revision += 1

## A police unit's rank marks: 0 a trooper, 1 the sergeant (chevrons on the shoulder), 2 the lead (a
## stripe across the helmet).
var rank: int = 0:
	set(v):
		rank = v
		_look_revision += 1
## Bumped by every change of `style`, `look_seed` or `rank`: the visuals re-resolve the look when it
## moves.
var _look_revision := 0
## Current health, initialised to max_health. Read-only outside this script.
var health: float
## True once the character has died; gates all movement and action permanently.
var is_dead: bool = false
## Unit vector from the character toward its aim point; read by the hands and visuals.
var facing := Vector2.RIGHT
## The body's living motion (head, shoulders, hips and hands chasing `facing`); read by the hands,
## rig and visuals.
var pose: CharacterPose = CharacterPose.new()
## The falling body once dead (null while alive): stepped here, drawn by the visuals.
var ragdoll: CharacterRagdoll
## What drives `pose`, refilled each physics frame (see `_pose_drive`).
var _drive := PoseDrive.new()
## The standing rig solved for `_rig_frame` (see `rig()`).
var _rig_cache: CharacterRig = null
## The physics frame `_rig_cache` was solved in.
var _rig_frame := -1
## True once the dead body has come to rest and started bleeding out.
var _bled_out := false
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
## What the character wears (Items domain; `set_outfit`): its armour, its weight and, for the art,
## its look. A new one wears nothing (no armour, no weight).
var _outfit := Outfit.new()
## Damage dents/chunks recorded when the character is shot; read by the visuals and the
## collider rebuild. The character is flesh — a hittable surface like furniture.
var _deformable: Deformable
## Splatter and dripping from this character's wounds (Physics domain component).
var _wound: BloodWound
## Bloody footprints from blood the feet walk through (Physics domain component), fed by
## `_footsteps`.
var _footprints: BloodFootprints
## Detects footfalls and feeds `_footprints`.
var _footsteps := CharacterFootsteps.new()
## Rests the legs against walls and furniture and shoves light pieces (see character_legs.gd).
var _legs := CharacterLegs.new()
## The leg kick under way, if any (see character_kick.gd).
var _kick := CharacterKick.new()
## The living body's shadow (a LightOccluder2D child on `LightMasks.CHARACTER`, turned with
## `facing`); null while `LightMasks.shadows` is off, and freed on death.
var _occluder: LightOccluder2D

## The Hands child (character_hands.gd): hand geometry, the punch.
@onready var _hands := $Hands


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
	# Re-emit the hands' punch as a unified hit_landed (melee → hand 0/1, with its dealt damage).
	weapon.hands = _hands
	_hands.punched.connect(_on_punched)
	_kick.kicked.connect(_on_kicked)

	# Compose the flesh deformation component; its impacts dent the drawn silhouette (visual
	# only — the body keeps its circular hitbox). No carved chunks, since a chunk's reach
	# would span this small body and fold it.
	_deformable = Deformable.new()
	_deformable.max_depth = CharacterHitConfig.flesh_deform_max_depth
	_deformable.allow_chunks = CharacterHitConfig.flesh_allow_chunks
	_deformable.max_impacts = CharacterHitConfig.flesh_deform_max_impacts
	add_child(_deformable)

	_wound = BloodWound.new()
	add_child(_wound)

	_footprints = BloodFootprints.new()
	add_child(_footprints)

	use.attach()

	_occluder = LightMasks.occluder(_shadow_footprint(), LightMasks.CHARACTER)
	if _occluder != null:
		add_child(_occluder)
		_occluder.rotation = facing.angle()


func _physics_process(delta: float) -> void:
	_physics_step(delta)
	use.restore_cleared()
	_turn_shadow()


## The living body's shadow footprint, in its own frame with +x along the facing
## (CharacterShadowConfig).
func _shadow_footprint() -> PackedVector2Array:
	var poly := PackedVector2Array()
	var sides := maxi(3, CharacterShadowConfig.sides)
	for k in sides:
		var a := TAU * k / sides
		poly.append(Vector2(
			cos(a) * radius * CharacterShadowConfig.depth,
			sin(a) * radius * CharacterShadowConfig.width,
		))
	return poly


## Turn the shadow with the facing (it moves with the body, its parent); only when the facing has
## turned.
func _turn_shadow() -> void:
	if _occluder == null:
		return
	var angle := facing.angle()
	if not is_equal_approx(_occluder.rotation, angle):
		_occluder.rotation = angle


## One physics frame of the body: a dead one's ragdoll, else the controller's intent, the ride or
## interaction, and the walk.
func _physics_step(delta: float) -> void:
	if is_dead:
		_fall_frame(delta)
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


## One physics frame of a dead body: its ragdoll falls, and once it has settled it bleeds out.
func _fall_frame(delta: float) -> void:
	ragdoll.step(delta, get_world_2d().direct_space_state, global_position)
	if ragdoll.is_settled() and not _bled_out:
		_bled_out = true
		Physics.bleed_out(get_parent(), self, [get_rid()])


## One physics frame on foot: the aim turned, the walk moved and slid, the pushes, the kick, the
## pose, the legs and the footsteps.
func _walk_frame(delta: float) -> void:
	# Aim toward the aim point. Guard the degenerate zero-length case.
	var to_aim := movement.aim_point - global_position
	if to_aim.length() > 0.001:
		facing = _turned_toward(to_aim.normalized(), delta)
	# A parent's _physics_process runs before its children's, so the hands see this fresh
	# facing on the same frame.
	_hands.facing = facing
	weapon.update_raise(delta)
	movement.walk(delta)
	_kick.update(self, delta)
	# Before the children's _physics_process, so the hands build on this frame's pose.
	pose.update(delta, _pose_drive(get_real_velocity(), stun.level()))
	_legs.update(self, delta)
	_footsteps.update(self, _footprints)


# --- The body (held, solved) and what it wears ------------------------------------


## Drop the cached rig: what it is solved from changed mid-frame (the held slot, a posture, a ride,
## death), so the next `rig()` solves it afresh.
func invalidate_rig() -> void:
	_rig_cache = null


## The body held still for a frame (`use.hold_frame`: an interaction, a ride): the hands on the
## facing, the legs and the kick cleared, and the pose updated with `step` as its motion and
## `stun_at` as its stun level.
func hold_body(delta: float, step: Vector2, stun_at: float) -> void:
	_hands.facing = facing
	_legs.clear()
	_kick.clear()
	pose.update(delta, _pose_drive(step, stun_at))


## What drives the pose this frame (`_drive`, refilled): the aim, the walk at `moving` (px/s), each
## hand's stance and punch, and the `stun_at` level.
func _pose_drive(moving: Vector2, stun_at: float) -> PoseDrive:
	_drive.facing = facing
	_drive.velocity = moving
	_drive.top_speed = movement.speed
	_drive.stances = weapon.stances()
	_drive.punch = _hands.punch_amounts()
	_drive.stun = stun_at
	return _drive


## Where side `i`'s ankle rests (local x/y px) against a wall or piece of furniture its leg has met,
## or null when nothing is in its way. The rig draws the leg there (see character_legs.gd).
func foot_clamp(i: int) -> Variant:
	return _legs.ankle(i)


## Dress the character in `ids` (`{ head, body, vest, pants, feet, front_plate, back_plate }`,
## String keys, StringName ids; a missing or empty one = nothing there), replacing everything worn
## before: its armour, its weight and its look (`docs/outfits.md`). How Main dresses a spawn
## (through `LoadoutConfig.apply`); a character never dressed wears nothing.
func set_outfit(ids: Dictionary) -> void:
	_outfit.set_ids(ids)


## Draw the character in `new_style` (a key of `CharacterStyleConfig.styles`) with its own variety
## from `seed_value`, and a police unit's `new_rank` (0 trooper, 1 sergeant, 2 lead): how Main
## styles a spawn (through `LoadoutConfig.apply`). Looks only.
func set_style(new_style: StringName, seed_value: int, new_rank := 0) -> void:
	style = new_style
	look_seed = seed_value
	rank = new_rank


## What the character wears (the `Outfit` the art reads its `look(style)` from).
func outfit() -> Outfit:
	return _outfit


## What it wears, for the UI: each garment slot -> the garment's name ("" for nothing), each plate
## slot -> `{ type, name, condition }`.
func outfit_view() -> Dictionary:
	return _outfit.view()


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


## True while a punch swing is in progress.
func is_attacking() -> bool:
	return _hands.is_attacking()


## Kick with the right leg, whatever is held: the foot is thrown out along `facing`, shoving and
## hurting what it reaches (character_kick.gd). False when dead, crouched, locked in an interaction
## or a kick is still under way.
func leg_kick() -> bool:
	if is_dead or use.is_busy() or movement.posture() != &"stand":
		return false
	return _kick.start()


## True while a kick is under way (the foot thrown out and drawn back).
func is_kicking() -> bool:
	return _kick.is_active()


## How far out side `i`'s foot is thrown, 0 (not kicking with that leg) .. 1 (fully thrown). The rig
## draws the leg by it.
func leg_kick_amount(i: int) -> float:
	return _kick.amount() if i == CharacterKick.LEG else 0.0


## Throw a punch with the given hand (the item decides which).
func punch(hand: int) -> void:
	_hands.punch(hand)


## How far `hand` is thrown, 0 (resting) .. 1 (fully punched); an item draws its swing by it.
func punch_amount(hand: int) -> float:
	return _hands.punch_amount(hand)


## Local-space center of a hand (0 left, 1 right).
func hand_position(hand: int) -> Vector2:
	return _hands.hand_position(hand)


## World-space center of a hand (the character is never rotated, so world = origin + local).
func hand_world(hand: int) -> Vector2:
	return global_position + _hands.hand_position(hand)


## The standing skeleton as it is held right now (see character_rig.gd), for the visuals and
## anything that wants the arms' and legs' joints. Solved once per physics frame and shared: the
## pose, the hands and the feet's rests change only in `_physics_process`, so every caller in the
## same frame (the draw, a footfall, a test) gets the one solve.
func rig() -> CharacterRig:
	var frame := Engine.get_physics_frames()
	if _rig_cache == null or _rig_frame != frame:
		_rig_cache = CharacterRig.new(self)
		_rig_frame = frame
	return _rig_cache


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
	var armour := _outfit.layer(hit_zone(height), hit_side(direction))
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
func hit_zone(height: float) -> StringName:
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
func hit_side(direction: Vector2) -> StringName:
	if direction.length() < 0.001:
		return &"front"
	var off := rad_to_deg(absf(Vector2.from_angle(pose.torso_angle).angle_to(-direction)))
	if off <= CharacterHitConfig.side_front_deg:
		return &"front"
	return &"back" if off >= CharacterHitConfig.side_back_deg else &"flank"


## Take a hit: shove along the impact (folded into locomotion via the pushable path), then hurt by
## where it struck (the striker fills in a HitInfo; `docs/outfits.md` O2 to O9). A round's zone
## (`hit_zone` of its `height`) scales its damage (`CharacterHitConfig.zone_damage`). Where armour
## covers that zone and side (`Outfit.layer`), the hit wears its plate, and a round that did not get
## through it (`penetrated` false: stopped or glanced off) deals only the armour's `blunt` share: no
## wound, no blood, its debris the armour's; one that got through deals all but the armour's
## `reduction`. A hit with no height (a frag's blast) strikes the whole body, cut by the torso
## armour's `blast`. A wound records the deformation relative to the shoulders (it dents the drawn
## body and hands and turns with them), sprays blood debris and starts the bleeding (BloodWound).
func take_hit(hit: HitInfo) -> void:
	apply_impulse(Physics.impact_impulse(hit))
	var side := hit_side(hit.direction)
	if hit.height < 0.0:
		_wound_by(hit, hit.damage * (1.0 - float(_outfit.layer(&"torso", side).get("blast", 0.0))))
		return
	var zone := hit_zone(hit.height)
	var damage := hit.damage * float(CharacterHitConfig.zone_damage.get(zone, 1.0))
	var armour := _outfit.layer(zone, side)
	if armour.is_empty():
		_wound_by(hit, damage)
		return
	_outfit.wear(zone, side, hit.damage)
	if hit.penetrated:
		_wound_by(hit, damage * (1.0 - float(armour["reduction"])))
		return
	Physics.spawn_debris(
		get_parent(),
		hit,
		get_surface().merged({ "material": armour["material"], "color": armour["color"] }, true),
	)
	_apply_damage(damage * float(armour["blunt"]), hit.direction)


## A hit that wounds: the dent, the blood debris and the bleeding, and `damage` off health.
func _wound_by(hit: HitInfo, damage: float) -> void:
	_deformable.record(hit, pose.torso_angle)
	Physics.spawn_debris(get_parent(), hit, get_surface())
	_wound.record(hit)
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
	_rig_cache = null
	ammo.cancel()
	_wound.stop()
	# A corpse is just a body on the floor: clear its collision layer so the living (and bullets,
	# punches, sight lines and the dropped item, all on layer 1) pass right over it instead of being
	# blocked, and draw it beneath them.
	collision_layer = 0
	z_index = CharacterArtConfig.ragdoll_z_index
	if _occluder != null:  # A body on the floor casts no shadow.
		_occluder.queue_free()
		_occluder = null
	use.end_interaction()
	use.abandon()  # Killed boarding or getting out: the ride ends where the body is.
	var momentum := movement.momentum()
	# The body falls from the standing skeleton, whatever it was doing.
	movement.stand_up()
	movement.fold(0.0)
	stun.clear()  # A dead body sees and hears nothing more to fade.
	_legs.clear()
	_kick.clear()
	ragdoll = CharacterRagdoll.new(self, momentum, direction)
	inventory.drop_held(momentum)
	velocity = Vector2.ZERO
	died.emit()


## Where this body's blood leaves it (world): its position while alive; once fallen, the middle of
## the trunk where it lies. Blood pools sample it, so they spill from the body, not where it stood.
func blood_origin() -> Vector2:
	if ragdoll == null:
		return global_position
	var mid: Vector3 = ((ragdoll.point(CharacterRagdoll.CHEST)
			+ ragdoll.point(CharacterRagdoll.PELVIS)) * 0.5)
	return global_position + Vector2(mid.x, mid.y)


## Total accumulated hit damage this character has taken, read from its deformation record. Lets a
## controller sense how hurt the character is (0 when unscathed).
func damage_taken() -> float:
	return _deformable.damage_total if _deformable else 0.0


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
		ragdoll.blast(away * impulse / get_mass())
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
