# Stacked items

Small pieces that rest on any flat top and on each other: tableware on tables, books, lamps and monitors on shelves and
desks, boxes and crates stacked two or three high. Decision D20 of #194 (rule 9, the phase-3 gate). Rules SI1 to SI8; each is
enforced by the tests named under it (`tools/run_tests.sh <id>`), following the convention of `docs/doors.md`. This is the
**piece** half (job `stack-a`): the catalogue rows, the bodies, the walk-over rule and the bullets. Placing them in houses and
districts, the nav carve for a tall stack, the AI's cover by height and the perf re-pin are `stack-b`.

An item is a free piece (`docs/adr/0014-twin-staging-and-plan-space.md`): the 3D body in the twin space is the truth, its 2D
node a footprint. Scale: 1 px a 3D unit, 42.3 px a metre.

## SI1. The items

Eight catalogue rows (`ItemsCatalog`, World-Gen), in no recipe: plate (12 px across, 1.5 high), cup (7, 5), bowl (10, 4), book
(9 x 12, 2.5), desk lamp (10, 14), monitor (18 x 8, 14), box (14, 12) and crate (20, 16). Art id `item` (`ItemPainter`,
`ItemMesh`; heights in `ObjectMeshItemConfig`, one number for the mesh and `PieceHeights`). Materials: ceramic (plate, cup,
bowl), paper, metal, electronics, cardboard, wood.

Tests: `objects/piece_heights` (the rows' tops).

## SI2. Resting on a top

`ObjectFactory.spawn_on(definition, base, offset, parent, opts)` sets an item on another piece's top: the body starts at
`ObjectFactory.top_at` (a ray down at that plan point against the twin space, so a box already standing there raises it; a
table's 31 px, a crate's 16) a hair above it (`PieceBody.REST_GAP`, 0.4 px: it is set down, it does not pop), falls the last of it
and settles asleep with its underside on the top. An item set on the same spot goes on top of the first: a stack. A house is built
before the twin space takes any piece over, so items set in one frame have no twin to ask: `spawn_on` keeps the chain itself (what
it set on a base that has no twin yet, `PieceRest.stacked`, read where the footprints overlap) and the ray reads the rest. It stays
where it was put on the plan.

Tests: `objects/stacked_items_rest_on_their_top` (a plate and a cup on a table; a box on a crate on a crate),
`objects/items_set_on_one_spot_in_one_frame` (three plates and a cup on one spot, one frame), `objects/item_set_on_a_twinned_stack_reads_the_ray`
(a plate set later over a settled box), `objects/item_set_down_does_not_pop` (the first-frame gap, the landing speed).

## SI3. Free bodies, physics only

Each item is its own `RigidBody3D` (`ItemBody`, a `PieceBody`): a shot, a blast, a shove, a car or a tipping base moves it
alone, and nothing joins it to what it stands on. There is no pick-up. A box shoved off a stack slides off while the crates stay
put; a table that is knocked over spills what stood on it to the floor.

Tests: `objects/stacked_box_shoved_off_alone`, `objects/stack_falls_apart_when_its_base_tips`.

## SI4. Underfoot: a step over

An item whose highest point is within `DoorFallConfig.step_over` (10 px) is walked over: it lies on `PhysicsLayers.TWIN_WALKOVER`
(and off the layer a walker meets, `TWIN_BLOCKS`) and ignores characters, so a walker passes it and nothing pushes it. Taller (a
box, a crate, a lamp, a monitor, an item on its side), or up on a table, it is on `TWIN_WORLD` and an obstacle like any piece:
a walker shoves it by today's rules (`Knockback.push`). The layer changes while it lies: tipped up it is an obstacle, lying flat
again it is walked over. A round and a blast meet it either way (a line asks `TWIN_ALL`). A vehicle's body does not meet a walk-over item either
(its mask has no `TWIN_WALKOVER`): a car drives over a flat item, with no strike on it.

A swinging door goes over a walk-over item as a walker does (`Door._overlapping` leaves one out): it shuts over a plate and is
no more scraped to a stop by it; it still stops at a crate and at a fallen door's leaf, which lies as flat but is no item.

Tests: `objects/walker_steps_over_a_fallen_plate` (a puppet walks over a plate and a cup; the same walk shoves a crate),
`objects/door_shuts_over_a_plate`, `objects/item_flipped_up_walks_over_again` (a plate flicked up is on `TWIN_WORLD` while it tumbles, back on `TWIN_WALKOVER` flat).

## SI5. What falls onto a walk-over item

What lands (a grenade, a casing, a chip, a dropped item, a ragdoll: `TWIN_SURFACES`) rests on a walk-over item, and so does
another item: the free item's mask holds `TWIN_WALKOVER`, so a book set on a plate, or let fall onto one, rests on its top, not
through it on the floor. A free piece that is no item does not (its mask has no `TWIN_WALKOVER`, as a fallen door's neither).
It is still met the other way round: a chair or any piece shoved along the floor into a walk-over item pushes it on ahead
(the item's own mask holds the piece's layer, `TWIN_WORLD`), it does not slide over or through it.

Tests: `objects/book_falls_onto_a_plate`, `objects/shoved_chair_pushes_floor_plates`.

## SI6. The nav map

A walk-over item is no hole in the nav bake (`PieceRest.walk_over`; `NavHoles.cut` skips it): the map has floor under it. A
taller item is a hole as any piece is (`stack-b` carves a tall stack by its footprint).

Tests: `navigation/walk_over_items_leave_the_map_open`.

## SI7. Bullets by material

A round meets an item at its real height and goes by its material and thickness like any piece's: it passes a plate (6 px of
ceramic) and knocks it off, a crate (wood, 20 px) stops it. A box stack is cover at its real height for rounds (`PieceHeights`); the AI choosing cover by the stacked top (the twin's, not the
catalogue's) is `stack-b`'s job.

Tests: `projectile/round_through_a_plate_stopped_by_a_crate`, `projectile/round_through_books_and_a_monitor` (each book of a stack
by its height; a monitor).

## SI8. Layouts do not move

Items are in no recipe and no seeded layout: today's furniture, house layouts and test premises are unchanged. `stack-b` places
them on their own RNG stream.
