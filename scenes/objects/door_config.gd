class_name DoorConfig
## A door's tuning (Objects domain, scenes/objects/door/): how it swings, how hard a push must be to
## count against its latch, how fast it bursts, how the leaf is built and how a fallen one lies.
## What differs by material (hit points, penetration, latch, the factors of a hit) is
## `DoorMaterialConfig`. Angles are in degrees. A `class_name` holder of `static var`s, read as
## `DoorConfig.<name>`; there is no instance and no autoload.

## How far a door opens (degrees from shut), where its leaf lies along the room's wall.
static var open_angle: float = 90.0
## Seconds a full swing (shut to `open_angle`, or back) takes; a part swing takes its share.
static var swing_time: float = 0.4
## Degrees one step of the gradual opening turns the door: about five notches open it fully.
static var step_degrees: float = 20.0
## The least impulse (`apply_impulse` units) that counts as a kick or a blast against the latch: a
## walking push (about 900 a frame) and a punch (900) are below it, a kick (2200) above.
static var burst_impulse: float = 1500.0
## Degrees a second a burst latch throws the door open at.
static var burst_speed: float = 540.0
## Px a second a character in the door's arc can be nudged aside at, at most: a leaf that sweeps
## faster than this stops against the character. At the tip of the longest leaf (a front doorway's
## 69 px gap, a 56 px leaf) the swing peaks near 330 and a burst runs at 530.
static var nudge_speed: float = 600.0
## The leaf's thickness in px (its collider and its drawing).
static var leaf_thickness: float = 6.0
## How much shorter than the doorway the leaf's collider is, so it never rests against a jamb.
static var leaf_slack: float = 1.0
## How much slimmer all round (px) than the leaf the shape is that a swing probes the space with.
static var probe_inset: float = 1.0
## How far (px) out from the doorway a knocked-down door lies, end to end.
static var fallen_length: float = 100.0
## Where a character stands to open the door from its latch side: this far (px) out from the
## doorway's wall line and this far in from the latch jamb.
static var latch_spot_out: float = 26.0
static var latch_spot_in: float = 16.0
## The deepest a dent in the leaf caves (px), and how many the leaf keeps.
static var dent_depth: float = 2.0
static var dents: int = 10
## Seconds within which a swing opening a door that was already being opened carries on the same
## movement and posts no `open` again: a run of scroll notches sounds once, however long it lasts. A
## closing swing ends the movement, and so does a rest this long.
static var latch_gap: float = 0.6
