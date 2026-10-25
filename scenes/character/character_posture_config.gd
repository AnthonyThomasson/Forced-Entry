class_name CharacterPostureConfig
## Stand or crouch (scenes/character/): the posture table (speed, turn, coverage, height), the
## change cooldown and ease, and the crouched body's stance (pitch, narrowed hips and feet, stagger,
## shorter stride, hands further ahead). A `class_name` holder of `static var`s, read as
## `CharacterPostureConfig.<name>`; there is no instance and no autoload.

## Not to be confused with `stances` below (how a hand is held). A posture trades speed for a
## smaller target: `speed` multiplies the walk speed; `turn` is the fastest the body swings round to
## the aim (rad/s, 0 = at once); `coverage` is the body's height on the same 0–100 scale as an
## object's coverage (a bullet carries one height, and strikes whatever is taller than it), so a
## lower posture is struck by fewer shots and hides behind lower cover; `height` scales the drawn
## body's standing heights. Keep `crouch` coverage at or below the AI's `cover_min` (40), so
## everything it treats as cover hides a crouch.
static var postures: Dictionary = {
	&"stand": { "speed": 1.0, "turn": 0.0, "coverage": 60.0, "height": 1.0 },
	&"crouch": { "speed": 0.6, "turn": 5.0, "coverage": 35.0, "height": 0.62 },
}
## Seconds after a posture change before the next one is allowed, so a controller can't flicker
## between them.
static var change_time: float = 0.25
## How fast the drawn body eases into a new posture (1/s): the share of the way per second.
static var posture_ease: float = 9.0
## A crouch pitches the spine forward about the pelvis (degrees, at the crouch's height; the neck
## pitches on from the shoulders), and the pelvis shifts back and the chest forward by half the lean
## so the body stays centred over its feet.
static var body_crouch_pitch: float = 25.0
static var body_crouch_neck_pitch: float = -10.0
## A crouch narrows the stance: the hips and the feet sit this share of their standing width apart,
## the feet stand this far ahead of the pelvis (body radii, so the knees lead over the toes), the
## foot opposite the weapon hand steps back by the stagger (body radii), and the stride is this
## share of a standing one.
static var body_crouch_hip_width: float = 0.7
static var body_crouch_foot_gap: float = 0.5
static var body_crouch_foot_ahead: float = 0.9
static var body_crouch_stagger: float = 0.35
static var body_crouch_stride: float = 0.45
## How far further forward (px) the hands are held crouched (about the chest's forward shift, so the
## arms keep their reach and the gun is held out in front).
static var body_crouch_hand_ahead: float = 8.0
