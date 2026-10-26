class_name SquadFollowConfig
## The squads' follow file and leash (`docs/leadership.md` LD21 to LD23), the same for every squad:
## where a follower keeps to behind its leader and how far from it it fights. A `class_name` holder
## of `static var`s, read as `SquadFollowConfig.<name>`; there is no instance and no autoload.

## The follow file (px): the first follower keeps this far back along the leader's trail...
static var gap := 55.0
## ... and each next one this much further (also the spacing of the slots on a ring, and of the
## rings).
static var step := 45.0
## A follower that has fallen `step` behind its spot runs to catch up, and keeps running until it
## is this near (px) its spot.
static var caught_up := 20.0
## The ring (px) round a still leader its followers stand on, behind its facing.
static var ring := 80.0
## Seconds the leader stands (within `SquadFollow.TRAIL_STEP`) before it counts as still.
static var still_time := 0.8
## A follower re-aims its walk only once its spot has moved this far (px) from where it is going.
static var retarget := 20.0
## A follower is at its spot within this distance (px).
static var arrive := 10.0
## A follower fights within this distance (px) of the leader's live position...
static var leash := 320.0
## ... and one fighting further than this many leashes from it re-decides.
static var leash_break := 1.3
