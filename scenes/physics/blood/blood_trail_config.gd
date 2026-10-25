class_name BloodTrailConfig
## Blood pulled out of a pool by a smear, extending the pool's outline (scenes/physics/blood/:
## BloodSmear, BloodFlow): the smear's trail and the pool's trail cap and length.
## A `class_name` holder of `static var`s, read as `BloodTrailConfig.<name>`; there is no instance
## and no autoload.

## Blood pulled out of a pool extends the pool's own outline: a finger carrying at least
## `smear_trail_min` load within `smear_trail_reach` px of a pool grows it by that load x
## `smear_trail_gain`, and the pool keeps at most `pool_trail_max` such cells. No trail cell lies
## more than `pool_trail_length` px from the pool's own flooded cells: the tongue tapers to nothing
## there, so this is how far a pool can be dragged (a full load would otherwise carry about 100 px).
static var smear_trail_min: float = 0.3
static var smear_trail_reach: float = 10.0
static var smear_trail_gain: float = 1.0
static var pool_trail_max: int = 600
static var pool_trail_length: float = 50.0
