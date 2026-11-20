class_name PhysicsLayers
## General domain: named physics-layer bits, shared read-only infrastructure (same role as
## Objects' `Wall.Side` enum) — a single source so "walls + solid furniture" isn't redefined
## as the same magic number in every file that raycasts against it.

## The 2D layer solid furniture (and a test's bare body) sits on. No 2D physics query asks for it
## any more (the sim reads the twin layers below): it marks a 2D body as solid (`ViewWatch`, a
## twin's presence: a body on none has no twin on its layer). Walls, doors and vehicles are plan
## handles (`Node2D`, `TwinSpace.BODIES`) with no layer at all.
const SOLID := 1
## The 3D layers of the twin space (`TwinSpace`, `docs/adr/0014-twin-staging-and-plan-space.md`),
## their own bits in the 3D physics space (not `SOLID`'s 2D one): what a 3D ray or sweep asks for.
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
const TWIN_ALL := TWIN_WORLD | TWIN_VEHICLE | TWIN_CHARACTER
