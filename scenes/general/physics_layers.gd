class_name PhysicsLayers
## General domain: named physics-layer bits, shared read-only infrastructure (same role as
## Objects' `Wall.Side` enum) — a single source so "walls + solid furniture" isn't redefined
## as the same magic number in every file that raycasts against it.

## The 3D layers of the twin space (`TwinSpace`, `docs/adr/0014-twin-staging-and-plan-space.md`),
## the only layers there are (no 2D physics body exists): what a 3D ray or sweep asks for.
## `TWIN_WORLD`: walls, floors, furniture and doors. `TWIN_VEHICLE`: a vehicle's body.
## `TWIN_CHARACTER`: a character's hit cylinder (a dead or seated one is on none). `TWIN_ALL`: those
## three. `TWIN_ROOF`: the roof over a house's rooms (`Floor.roofed`): in none of them, so a ray
## from the sky (the player's aim, a sight line) reaches what is under it; what a lob flies under
## asks for it.
const TWIN_WORLD := 1
const TWIN_VEHICLE := 2
const TWIN_CHARACTER := 4
const TWIN_ROOF := 8
## `TWIN_GROUND`: the one plane under the whole twin space (`TwinSpace`) a free piece of furniture
## rests on where no floor slab is; in no line layer (nothing casts at it).
const TWIN_GROUND := 16
## `TWIN_WALKOVER`: anything lying flat within a step over of the floor (a fallen door's leaf,
## `DoorFallConfig.step_over`): no walker and no vehicle meets it (`TWIN_BLOCKS` leaves it out), but
## a line (a round, a sight, a lob, a sweep: `TWIN_ALL`) and what lands on it (a grenade, a casing,
## debris, a dropped item, a ragdoll: `TWIN_SURFACES`) meet it where it lies, at its lying height.
const TWIN_WALKOVER := 32
## What a line asks for: every body in the twin space but the roof and the ground.
const TWIN_ALL := TWIN_WORLD | TWIN_VEHICLE | TWIN_CHARACTER | TWIN_WALKOVER
## What stops a walker or a vehicle: the bodies of `TWIN_ALL` that are no walk-over.
const TWIN_BLOCKS := TWIN_WORLD | TWIN_VEHICLE | TWIN_CHARACTER
## What a body that lands, rests or is held against reads: the structure, the furniture and the
## vehicles, and what lies flat; not the people.
const TWIN_SURFACES := TWIN_WORLD | TWIN_VEHICLE | TWIN_WALKOVER
