class_name RigMeasures extends RefCounted
## The measures one rig solve (`character_rig.gd`) builds the skeleton from, read off the character
## as it stands: the body's frames, its heights as the posture folds it, and its bone lengths, all
## in px. Made once per solve and read by each of its steps (the trunk, the arms, the legs).

const Pose = preload("res://scenes/character/body/character_pose.gd")

## The pose the solve reads (the character's `pose`).
var pose: Pose
## The body radius.
var r := 0.0
## The shoulders' forward and hand 1's side (the character's left as drawn: Godot's orthogonal()
## turns counter-clockwise), and the hips' (flat, unit).
var fwd := Vector3.ZERO
var right := Vector3.ZERO
var hip_fwd := Vector3.ZERO
var hip_right := Vector3.ZERO
## The posture's height (1 standing) and how far it folds the body (0 standing .. 1 crouched).
var height := 1.0
var folded := 0.0
## How far the spine pitches forward (rad), its length, and how far the chest sits ahead of the
## pelvis.
var pitch := 0.0
var spine := 0.0
var lean := 0.0
## The heights of the hips and the chest.
var hip_z := 0.0
var chest_z := 0.0
## The bones: upper arm, forearm, thigh and shin; how far an arm reaches before its shoulder
## follows.
var upper := 0.0
var fore := 0.0
var thigh := 0.0
var shin := 0.0
var arm_reach := 0.0
## A foot's height at rest, half the hips' and the feet's widths, and how far the feet stand ahead
## of the pelvis.
var foot_z := 0.0
var hip_half := 0.0
var foot_half := 0.0
var foot_fwd := 0.0
## The hand that holds the weapon (its side's foot is staggered back in a crouch), and the share of
## a stride a stunned walk keeps.
var weapon_hand := 0
var staggered := 1.0


## The measures of `character` as it stands now.
func _init(character: CharacterBody2D) -> void:
	pose = character.pose
	r = character.radius
	_frames()
	_heights(character)
	upper = CharacterConfig.body_upper_arm * r
	fore = CharacterConfig.body_forearm * r
	thigh = CharacterConfig.body_thigh * r
	shin = CharacterConfig.body_shin * r
	arm_reach = (upper + fore) * CharacterConfig.body_arm_extension
	foot_z = CharacterConfig.ragdoll_limb_radius * r
	hip_half = (CharacterConfig.body_hip_width * r
			* lerpf(1.0, CharacterConfig.body_crouch_hip_width, folded))
	foot_half = (CharacterConfig.body_hip_width * r
			* lerpf(1.0, CharacterConfig.body_crouch_foot_gap, folded))
	foot_fwd = CharacterConfig.body_crouch_foot_ahead * r * folded - lean * 0.5
	var item: Item = character.current_item()
	weapon_hand = item.weapon_hand() if item != null else 0
	# A stunned walk's shorter steps.
	staggered = lerpf(1.0, CharacterConfig.stun_stagger_stride, pose.stun_amount())


## The shoulders' frame (turned to the pose's torso angle) and the hips' (its hip angle).
func _frames() -> void:
	var torso_dir := Vector2.from_angle(pose.torso_angle)
	fwd = Vector3(torso_dir.x, torso_dir.y, 0.0)
	right = Vector3(torso_dir.orthogonal().x, torso_dir.orthogonal().y, 0.0)
	var hips := Vector2.from_angle(pose.hip_angle)
	hip_fwd = Vector3(hips.x, hips.y, 0.0)
	hip_right = Vector3(hips.orthogonal().x, hips.orthogonal().y, 0.0)


## A lower posture scales the standing heights down and folds the body: the spine pitches forward
## about the pelvis (the pelvis sits back and the chest forward by half the lean, so the body stays
## centred over its feet), the hips and feet come together, and the feet stand ahead of the pelvis
## so the knees lead over the toes.
func _heights(character: CharacterBody2D) -> void:
	height = character.posture_height()
	var crouch_height: float = CharacterConfig.postures[&"crouch"]["height"]
	folded = clampf((1.0 - height) / maxf(1.0 - crouch_height, 0.01), 0.0, 1.0)
	# A stun hunches it on.
	pitch = deg_to_rad(CharacterConfig.body_crouch_pitch) * folded + pose.hunch()
	spine = (CharacterConfig.body_shoulder_height - CharacterConfig.body_hip_height) * r
	lean = spine * sin(pitch)
	# A run sinks.
	hip_z = ((CharacterConfig.body_hip_height
			- CharacterConfig.body_run_hip_drop * pose.run_amount()) * r * height)
	chest_z = CharacterConfig.body_hip_height * r * height + spine * cos(pitch)
