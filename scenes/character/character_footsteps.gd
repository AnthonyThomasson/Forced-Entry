extends RefCounted
## Character FOOTSTEPS (Character domain, animate layer): spots the instant each foot lands in the
## walk cycle. It reports the sole to the Physics domain's BloodFootprints, which decides whether it
## prints blood, and posts a `footfall` event on the EventBus (the Audio domain makes the step). A
## foot lands when its lift (max(-cos(phase), 0), see character_rig.gd) returns to the floor, i.e.
## cos(phase) rises through zero, at the forward end of its stride. Stepped by character.gd after
## the pose each physics frame; one rig solve per footfall, none otherwise. The event says whose
## step it is (`character`) and its gait (`running`, `crouched`), which the AI hears by.

const CharacterRig = preload("res://scenes/character/body/character_rig.gd")
## Below this walk amount (0..1) a shuffle makes no steps.
const MIN_WALK := 0.2

## Per foot: cos(phase) last frame.
var _last_cos := [1.0, 1.0]


## Check both feet of `character` and report any footfall to `footprints`.
func update(character: CharacterBody2D, footprints: BloodFootprints) -> void:
	var pose = character.pose
	var phase: float = pose.stride_phase()
	for i in 2:
		var c := cos(phase + (0.0 if i == 0 else PI))
		var landed: bool = _last_cos[i] < 0.0 and c >= 0.0 and pose.walk_amount() >= MIN_WALK
		_last_cos[i] = c
		if landed:
			_report(character, footprints, i)


## Solve the rig for a foot that has just landed and hand its sole's geometry to `footprints`.
func _report(character: CharacterBody2D, footprints: BloodFootprints, foot: int) -> void:
	var rig: CharacterRig = character.rig()
	var r: float = character.radius
	var ankle := rig.point(CharacterRig.ANKLE[foot])
	var toes := rig.toes(foot)
	var dir := Vector2(toes.x, toes.y)
	var fall := Footfall.new()
	fall.direction = dir
	fall.length = CharacterBodyConfig.foot * r
	fall.width = CharacterConfig.body_shoe_widths[0] * r
	fall.at = character.global_position + Vector2(ankle.x, ankle.y) + dir * fall.length * 0.25
	# Left foot (0) has its arch toward +y of the toe frame, right foot toward -y.
	fall.inner = 1.0 if foot == 0 else -1.0
	fall.speed = character.get_real_velocity().length()
	footprints.step(foot, fall)
	# The footfall itself, for whoever listens (the Audio domain picks the sound from the floor it
	# lands on; the AI hears whose it is and how it was walked: running carries far, a crouched step
	# hardly at all).
	EventBus.post(
		&"footfall",
		{
			"position": fall.at, "foot": foot, "speed": fall.speed,
			"running": character.is_running(), "character": character,
			"crouched": character.posture() == &"crouch",
		},
	)
