class_name CharacterAnatomy extends RefCounted
## The body's animate parts as the character steps them (`character.gd`'s `anatomy`): the living
## motion (`pose`) and what drives it, the standing rig solved once a physics frame (`rig()`), the
## `Hands` child (hand geometry and the punch), the legs against walls, the leg kick, the footfalls,
## the flesh's dents and its bleeding, the living body's shadow, and the fall once dead (`ragdoll`)
## with the bleeding out once it has settled. The character adds the parts that are nodes from its
## `_ready` (`attach`), steps the body each physics frame on foot or once dead (`step`), holds it
## still in an interaction or a ride (`hold`), and lays it down on death (`die`, `fall`).

const CharacterPose = preload("res://scenes/character/body/character_pose.gd")
const CharacterRig = preload("res://scenes/character/body/character_rig.gd")
const CharacterRagdoll = preload("res://scenes/character/body/character_ragdoll.gd")
const CharacterFootsteps = preload("res://scenes/character/character_footsteps.gd")
const CharacterLegs = preload("res://scenes/character/body/character_legs.gd")
const CharacterKick = preload("res://scenes/character/body/character_kick.gd")

## The character the body is.
var character: CharacterBody2D
## The body's living motion (head, shoulders, hips and hands chasing `facing`); read by the hands,
## rig and visuals.
var pose: CharacterPose = CharacterPose.new()
## The Hands child (character_hands.gd): hand geometry, the punch. Found by `attach()`.
var hands: Node2D
## Rests the legs against walls and furniture and shoves light pieces (see character_legs.gd).
var legs := CharacterLegs.new()
## The leg kick under way, if any (see character_kick.gd).
var kick := CharacterKick.new()
## Detects footfalls and feeds the bloody footprints (see character_footsteps.gd).
var footsteps := CharacterFootsteps.new()
## The falling body once dead (null while alive): stepped here, drawn by the visuals.
var ragdoll: CharacterRagdoll
## Damage dents/chunks recorded when the character is shot; read by the visuals and the
## collider rebuild. The character is flesh — a hittable surface like furniture.
var deformable: Deformable
## Splatter and dripping from this character's wounds (Physics domain component).
var wound: BloodWound
## The living body's shadow (a LightOccluder2D child on `LightMasks.CHARACTER`, turned with
## `facing`); null while `LightMasks.shadows` is off, and freed on death.
var occluder: LightOccluder2D
## What drives `pose`, refilled each physics frame (see `_pose_drive`).
var _drive := PoseDrive.new()
## The standing rig solved for `_rig_frame` (see `rig()`).
var _rig: CharacterRig = null
## The physics frame `_rig` was solved in.
var _rig_frame := -1
## True once the dead body has come to rest and started bleeding out.
var _bled_out := false


## The body of `host`.
func _init(host: CharacterBody2D) -> void:
	character = host


## Find the Hands child and add the parts that are nodes as children of the character (from its
## `_ready`): the flesh's dents, the wound's bleeding, the bloody footprints and the shadow.
func attach() -> void:
	hands = character.get_node(^"Hands")
	# Compose the flesh deformation component; its impacts dent the drawn silhouette (visual
	# only — the body keeps its circular hitbox). No carved chunks, since a chunk's reach
	# would span this small body and fold it.
	deformable = Deformable.new()
	deformable.max_depth = CharacterHitConfig.flesh_deform_max_depth
	deformable.allow_chunks = CharacterHitConfig.flesh_allow_chunks
	deformable.max_impacts = CharacterHitConfig.flesh_deform_max_impacts
	character.add_child(deformable)

	wound = BloodWound.new()
	character.add_child(wound)

	footsteps.footprints = BloodFootprints.new()
	character.add_child(footsteps.footprints)

	occluder = LightMasks.occluder(_shadow_footprint(), LightMasks.CHARACTER)
	if occluder != null:
		character.add_child(occluder)
		occluder.rotation = character.facing.angle()


## The standing skeleton as it is held right now (see character_rig.gd), for the visuals and
## anything that wants the arms' and legs' joints. Solved once per physics frame and shared: the
## pose, the hands and the feet's rests change only in `_physics_process`, so every caller in the
## same frame (the draw, a footfall, a test) gets the one solve.
func rig() -> CharacterRig:
	var frame := Engine.get_physics_frames()
	if _rig == null or _rig_frame != frame:
		_rig = CharacterRig.new(character)
		_rig_frame = frame
	return _rig


## Drop the cached rig: what it is solved from changed mid-frame (the held slot, a posture, a ride,
## death), so the next `rig()` solves it afresh.
func invalidate_rig() -> void:
	_rig = null


## Kick with the right leg, whatever is held: the foot is thrown out along `facing`, shoving and
## hurting what it reaches (character_kick.gd). False when dead, crouched, locked in an interaction
## or a kick is still under way.
func leg_kick() -> bool:
	if (character.is_dead
			or character.use.is_busy()
			or character.movement.posture() != &"stand"):
		return false
	return kick.start()


## True while a kick is under way (the foot thrown out and drawn back; a test read).
func is_kicking() -> bool:
	return kick.is_active()


## How far out side `i`'s foot is thrown, 0 (not kicking with that leg) .. 1 (fully thrown). The rig
## draws the leg by it.
func leg_kick_amount(i: int) -> float:
	return kick.amount() if i == CharacterKick.LEG else 0.0


## One physics frame of the body after the walk has moved it: the kick, the pose, the legs and the
## footsteps; once dead, the ragdoll falls instead, and once it has settled it bleeds out.
func step(delta: float) -> void:
	if character.is_dead:
		ragdoll.step(delta, character.get_world_2d().direct_space_state, character.global_position)
		if ragdoll.is_settled() and not _bled_out:
			_bled_out = true
			Physics.bleed_out(character.get_parent(), character, [character.get_rid()])
		return
	kick.update(character, delta)
	# Before the children's _physics_process, so the hands build on this frame's pose.
	pose.update(delta, _pose_drive(character.get_real_velocity(), character.stun.level()))
	legs.update(character, delta)
	footsteps.update(character)


## The body held still for a frame (`use.hold_frame`: an interaction, a ride): the hands on the
## facing, the legs and the kick cleared, and the pose updated with `moving` as its motion and
## `stun_at` as its stun level.
func hold(delta: float, moving: Vector2, stun_at: float) -> void:
	hands.facing = character.facing
	legs.clear()
	kick.clear()
	pose.update(delta, _pose_drive(moving, stun_at))


## Record a wound: the dent (relative to the shoulders, so it turns with them), the blood debris and
## the bleeding.
func wound_by(hit: HitInfo) -> void:
	deformable.record(hit, pose.torso_angle)
	Physics.spawn_debris(character.get_parent(), hit, character.get_surface())
	wound.record(hit)


## The body dies: the rig is solved afresh, the bleeding stops, it is drawn beneath the living
## (`CharacterArtConfig.ragdoll_z_index`), and a body on the floor casts no shadow.
func die() -> void:
	invalidate_rig()
	wound.stop()
	character.z_index = CharacterArtConfig.ragdoll_z_index
	if occluder != null:
		occluder.queue_free()
		occluder = null


## Let the body fall from the standing rig: the ragdoll takes over from the live pose with
## `momentum` (px/s), toppling along `direction`; the legs and the kick are let go.
func fall(momentum: Vector2, direction: Vector2) -> void:
	legs.clear()
	kick.clear()
	ragdoll = CharacterRagdoll.new(character, momentum, direction)


## Turn the shadow with the facing (it moves with the body, its parent); only when the facing has
## turned.
func turn_shadow() -> void:
	if occluder == null:
		return
	var angle: float = character.facing.angle()
	if not is_equal_approx(occluder.rotation, angle):
		occluder.rotation = angle


## What drives the pose this frame (`_drive`, refilled): the aim, the walk at `moving` (px/s), each
## hand's stance and punch, and the `stun_at` level.
func _pose_drive(moving: Vector2, stun_at: float) -> PoseDrive:
	_drive.facing = character.facing
	_drive.velocity = moving
	_drive.top_speed = character.movement.speed
	_drive.stances = character.weapon.stances()
	_drive.punch = hands.punch_amounts()
	_drive.stun = stun_at
	return _drive


## The living body's shadow footprint, in its own frame with +x along the facing
## (CharacterShadowConfig).
func _shadow_footprint() -> PackedVector2Array:
	var poly := PackedVector2Array()
	var sides := maxi(3, CharacterShadowConfig.sides)
	var radius: float = character.radius
	for k in sides:
		var a := TAU * k / sides
		poly.append(Vector2(
			cos(a) * radius * CharacterShadowConfig.depth,
			sin(a) * radius * CharacterShadowConfig.width,
		))
	return poly
