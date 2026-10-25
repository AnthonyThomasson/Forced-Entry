class_name CharacterBodyConfig
## The standing skeleton (scenes/character/): joint heights and widths, bone lengths, the arm's
## stretch and the shoulder's follow. A `class_name` holder of `static var`s, read as
## `CharacterBodyConfig.<name>`; there is no instance and no autoload.

## Hip joints above the floor (legs stand a touch bent).
static var hip_height: float = 3.8
## Shoulder joints above the floor.
static var shoulder_height: float = 6.3
## Head center above the floor.
static var head_height: float = 7.2
## Each shoulder joint off the spine.
static var shoulder_width: float = 0.8
## Each hip joint off the spine.
static var hip_width: float = 0.4
## Shoulder to elbow.
static var upper_arm: float = 1.35
## Elbow to the center of the fist.
static var forearm: float = 1.4
## Hip to knee.
static var thigh: float = 1.95
## Knee to ankle.
static var shin: float = 1.85
## Shoe length.
static var foot: float = 1.0
## How far an arm may stretch before its shoulder follows the hand (fraction of its length), and the
## furthest the shoulder joint follows a hand out of reach (body radii) — a punch's lean-in.
static var arm_extension: float = 0.98
static var shoulder_reach: float = 1.0
