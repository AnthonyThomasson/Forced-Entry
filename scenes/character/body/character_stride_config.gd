class_name CharacterStrideConfig
## The walk and the run (scenes/character/body/): the rig's stride and foot lift (walking, running,
## the run's hip drop) and the pose's stride length, sway, lean, shoulder shift and arm pump. A
## `class_name` holder of `static var`s, read as `CharacterStrideConfig.<name>`; there is no
## instance and no autoload.

## How far each foot swings fore and aft mid-stride at full walking speed, and how high the
## swinging foot lifts (body radii).
static var body_stride: float = 0.85
static var body_foot_lift: float = 0.35
## The same at a full run: a longer, higher stride.
static var body_run_stride: float = 1.5
static var body_run_foot_lift: float = 0.6
## How far the hips sink at a full run (body radii): knees stay bent through the stride.
static var body_run_hip_drop: float = 0.35
## Distance walked per full stride (two steps), in px.
static var pose_stride_length: float = 48.0
## The same at a full run. A planted foot stays put on the ground when this is 2π × the foot's swing
## (`body_run_stride` × radius ≈ 21 px → ~130 px); shorter and the feet scurry and skate.
static var pose_run_stride_length: float = 130.0
## Shoulder sway either way at full walking speed (rad).
static var pose_walk_sway: float = 0.07
## A full run's shoulders counter-rotate against the hips by this much either way (rad).
static var pose_run_sway: float = 0.18
## ...and the upper body shifts this far (px) sideways over the planted foot, once per step.
static var pose_run_shoulder_shift: float = 1.2
## A full run's forward lean: the shoulders (and head) lead the hips this far (px) along the way it
## travels.
static var pose_run_lean: float = 2.5
## How far the forward-swinging hand rises above, and the back one drops below, its grip height
## (body radii).
static var pose_run_hand_rise: float = 0.7
## How far a running elbow's pole swings up and down with the arm (see `elbow_pole`): down under a
## forward hand, up behind a back one.
static var pose_run_elbow_lift: float = 0.5
