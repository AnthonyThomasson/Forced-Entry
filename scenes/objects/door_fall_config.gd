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
## How far (px) past the wall line the rearmost point of a leaf knocked down ajar must stand before
## it is let go to fall: past the face of the wall (half its 12 px), so that tipping it lies on the
## floor clear of the jambs, which its ends would catch where it stands.
static var frame_out: float = 7.0
## The speed (px/s) a leaf knocked down ajar is sent out of its frame with, once: the physics
## carries it (it slides edge-on through the doorway, and meets a character or a piece in its way as
## any body does).
static var carry_speed: float = 600.0
## The most physics frames the carry may last: a leaf that is held up (a character in its way) is
## let go to fall where it stands after them.
static var carry_frames: int = 40
## How fast (rad/s) a leaf let go out of its frame is already turning toward its fall: enough to
## pass the angle a free slab this thick stops standing on its foot (about 4 degrees), so it goes
## over and does not rock back upright, whatever the blow's shove and the floor's friction do.
static var lean_spin: float = 2.0
