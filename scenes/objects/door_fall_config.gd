class_name DoorFallConfig
## How a door knocked down falls and lies (Objects domain, `DoorSlab`, `docs/doors.md` DR11, D18):
## what the hinges' tearing gives the leaf, how far it is carried out of its frame and how it leans,
## and how high a lying leaf may be and still be walked over. A `class_name` holder of
## `static var`s, read as `DoorFallConfig.<name>`; there is no instance and no autoload. Lengths are
## px.

## The speed (px/s) the hinges' tearing gives the top of a leaf that is knocked down, across its
## face the way the blow came (a free upright slab on the floor has no preferred way to fall: this
## is the wrench that always lays it down, however gentle the blow, a wound with no direction
## included; a blast or a kick's own shove is far more). Times the leaf's mass.
static var fall_nudge: float = 20.0
## How much lower (px) than the doorway's lintel the free body of a knocked-down leaf stands: a leaf
## flush under the head jamb could not tip out of its frame (its top corner rises a tenth of a px
## as it begins to turn), as a real door hangs a gap under the head.
static var head_gap: float = 0.5
## How much shorter (px, each end) the free body of a knocked-down leaf is than the leaf, so it
## tips out between the jambs without catching a jamb's end.
static var side_gap: float = 1.0
## How high (px) a fallen leaf's top may stand over the floor and still be walked over: a leaf lying
## flat is as high as it is thick (6 px) and stops no foot; one leaning on a wall or lying on a bed
## stands higher and is an obstacle (its footprint a solid collider, a hole in the nav bake).
static var step_over: float = 10.0
## How far (px) either side of the wall line a leaf lying leaning still stands in its doorway's
## mouth: what it covers of the doorway there is what it takes from the gap a body can pass (a
## body's radius).
static var mouth: float = 14.0
## How far (px) past the wall line the rearmost point of a leaf knocked down ajar stands once it
## has been carried out of its frame with the blow: past the face of the wall (half its 12 px), so
## that tipping that way it lies on the floor clear of the jambs, which its ends would catch where
## it stands.
static var frame_out: float = 7.0
## How far (degrees) a leaf knocked down ajar is already leaning, with the blow, when it has been
## carried out of its frame: past the angle at which a free slab this thick stops standing on its
## foot (about 4 degrees), so it goes over and does not rock back upright, whatever the blow's
## shove and the floor's friction do to it.
static var lean_out: float = 8.0
