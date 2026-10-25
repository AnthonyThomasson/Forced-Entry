class_name PoseGait extends RefCounted
## The gait of a character's pose (`character_pose.gd`'s `gait`): the walk cycle's stride phase,
## how much the body walks and runs, the way it last walked, the stun as the body shows it, and
## the clock and per-character phase the breath, the glances and a steady hand's wander run on. A
## stunned walk staggers: a shorter, uneven stride (docs/grenades.md G13). Stepped by the pose once
## a physics frame, before its springs. Tuning: CharacterStrideConfig.pose_*, CharacterPaceConfig's
## run_speed_mult and CharacterStunConfig's look_ease, hunch_pitch and stagger_*.

## Walk cycle phase (rad; one turn per stride).
var _stride := 0.0
## How much the character is walking, 0..1 (smoothed speed).
var _walk := 0.0
## How much the character is running, 0..1 (smoothed, past walking speed).
var _run := 0.0
## Last walking direction (unit), for the head bob, the hips and a runner's lean.
var move_dir := Vector2.ZERO
## How stunned the body looks, 0..1: the stun level handed in, eased.
var _stun := 0.0
## Seconds alive, for breathing, glances and a steady hand's wander.
var time := 0.0
## Per-character offset so characters don't move in lockstep.
var phase := randf() * TAU


## Advance the gait by `delta` as `drive` asks: the clock, the stun eased toward its `stun` level,
## and the stride at its `velocity` (top speed `top_speed`).
func update(delta: float, drive: PoseDrive) -> void:
	time += delta
	_stun = lerpf(_stun, drive.stun, 1.0 - exp(-CharacterStunConfig.look_ease * delta))
	_step_stride(delta, drive.velocity, drive.top_speed)


## The walk and the run, eased toward the share of `top_speed` the body moves at (`velocity`), and
## the stride phase advanced by the distance walked.
func _step_stride(delta: float, velocity: Vector2, top_speed: float) -> void:
	var speed := velocity.length()
	_walk = lerpf(_walk, clampf(speed / maxf(top_speed, 1.0), 0.0, 1.0), 1.0 - exp(-8.0 * delta))
	# Past walking speed is running: how far toward a full run, smoothed like the walk.
	var run_span := maxf(CharacterPaceConfig.run_speed_mult - 1.0, 0.01)
	_run = lerpf(
		_run,
		clampf((speed / maxf(top_speed, 1.0) - 1.0) / run_span, 0.0, 1.0),
		1.0 - exp(-8.0 * delta),
	)
	var stride_length := lerpf(CharacterStrideConfig.pose_stride_length,
			CharacterStrideConfig.pose_run_stride_length, _run)
	stride_length *= lerpf(1.0, CharacterStunConfig.stagger_stride, _stun)
	# A stunned walk staggers: one step comes longer than the next (a limp) and the pace of the
	# steps wanders.
	var cadence := 1.0 + _stun * (CharacterStunConfig.stagger_limp * cos(_stride)
		+ CharacterStunConfig.stagger_wander * sin(time * 1.3 + phase))
	_stride = fmod(_stride + speed * delta / maxf(stride_length, 1.0) * TAU * cadence, TAU)
	if speed > 1.0:
		move_dir = velocity / speed


## The walk cycle's phase (rad; one turn per stride).
func stride_phase() -> float:
	return _stride


## How much the character is walking, 0..1.
func walk_amount() -> float:
	return _walk


## How much the character is running, 0 (walking or still) .. 1 (full run).
func run_amount() -> float:
	return _run


## How stunned the body looks, 0..1: the stun level, eased (CharacterStunConfig.look_ease); the
## stagger scales by it.
func stun_amount() -> float:
	return _stun


## How far the stun bends the spine forward (rad): CharacterStunConfig.hunch_pitch at the full
## level, eased.
func hunch() -> float:
	return deg_to_rad(CharacterStunConfig.hunch_pitch) * _stun
