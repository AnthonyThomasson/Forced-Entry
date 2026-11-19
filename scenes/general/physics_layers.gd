class_name PhysicsLayers
## General domain: named physics-layer bits, shared read-only infrastructure (same role as
## Objects' `Wall.Side` enum) — a single source so "walls + solid furniture" isn't redefined
## as the same magic number in every file that raycasts against it.

## The layer walls, solid (non-see-over) furniture and bodies sit on: the line-of-sight/line-of-fire
## query layer used by AI perception (agent_vision.gd), its debug mirror (vision_debug.gd),
## Interaction (character_interaction.gd), the character's hands and legs, a dropped item, the
## bullet and Physics' wall sweeps.
const SOLID := 1
## The 2D layer a thing lying flat on the floor sits on (a fallen door's footprint, `docs/doors.md`
## DR11): nothing walks or drives into it (no mask has it) but a blast finds it (it asks for
## `SOLID | LYING`), so it is shoved like any piece; a melee strike finds it in the twin space.
const LYING := 2
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
