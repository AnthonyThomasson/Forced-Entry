# Stacked items

Small pieces that rest on any flat top and on each other: tableware on tables, books, lamps and monitors on shelves and
desks, boxes and crates stacked two or three high. Decision D20 of #194 (rule 9, the phase-3 gate). Rules SI1 to SI8; each is
enforced by the tests named under it (`tools/run_tests.sh <id>`), following the convention of `docs/doors.md`. This is the
**piece** half (job `stack-a`): the catalogue rows, the bodies, the walk-over rule and the bullets; SI9 to SI12 are the **world**
half (job `stack-b`): placing them in houses and districts, the AI's cover by the stack's height, a car among them and the perf re-pin.

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
(its mask has no `TWIN_WALKOVER`, and the item's has no `TWIN_VEHICLE` while it lies flat, as a fallen leaf's): a car drives over a
flat item, with no strike and no flick. A box, a crate or a tipped item is a piece to it: struck, shoved on and scattered (free
bodies, nothing joins them).

A swinging door goes over a walk-over item as a walker does (`Door._overlapping` leaves one out): it shuts over a plate and is
no more scraped to a stop by it; it still stops at a crate and at a fallen door's leaf, which lies as flat but is no item.

Tests: `objects/walker_steps_over_a_fallen_plate` (a puppet walks over a plate and a cup; the same walk shoves a crate),
`objects/door_shuts_over_a_plate`, `objects/item_flipped_up_walks_over_again` (a plate flicked up is on `TWIN_WORLD` while it tumbles, back on `TWIN_WALKOVER` flat),
`vehicle/car_drives_over_plates_and_shoves_a_stack` (a car drives over three plates: they stay, no crash, no speed lost; then shoves and scatters a stack of three boxes).

## SI5. What falls onto a walk-over item

What lands (a grenade, a casing, a chip, a dropped item, a ragdoll: `TWIN_SURFACES`) rests on a walk-over item, and so does
another item: the free item's mask holds `TWIN_WALKOVER`, so a book set on a plate, or let fall onto one, rests on its top, not
through it on the floor. A free piece that is no item does not (its mask has no `TWIN_WALKOVER`, as a fallen door's neither).
It is still met the other way round: a chair or any piece shoved along the floor into a walk-over item pushes it on ahead
(the item's own mask holds the piece's layer, `TWIN_WORLD`), it does not slide over or through it.

Tests: `objects/book_falls_onto_a_plate`, `objects/shoved_chair_pushes_floor_plates`.

## SI6. The nav map

A walk-over item is no hole in the nav bake (`PieceRest.walk_over`; `NavHoles.cut` skips it): the map has floor under it. A
taller item is a hole as any piece is: a box, a crate or a lamp on the floor carves its footprint, so a stack of three is one
hole (the holes of its items overlap) and an item on a table sits inside the table's.

Tests: `navigation/walk_over_items_leave_the_map_open`, `navigation/house_items_carve_like_pieces` (a built garage house: its floor stacks are
holes and the map closed under them, an item on a table sits in the table's hole, a plate and a cup set on the floor add none, a crate one, and
the holes equal a full re-cut, also after a loaded table is moved).

## SI7. Bullets by material

A round meets an item at its real height and goes by its material and thickness like any piece's: it passes a plate (6 px of
ceramic) and knocks it off, a crate (wood, 20 px) stops it. A box stack is cover at its real height for rounds (`PieceHeights`); the AI choosing cover by the stack's height is SI10.

Tests: `projectile/round_through_a_plate_stopped_by_a_crate`, `projectile/round_through_books_and_a_monitor` (each book of a stack
by its height; a monitor).

## SI8. Layouts do not move

Items are in no recipe and no seeded layout: today's furniture, house layouts and test premises are unchanged. SI9 places them on
their own RNG stream, after the furniture.

## SI9. Placement: a few on a flat top, stacks on a storage floor

`RoomItems` (World-Gen, `scenes/worldgen/room_items.gd`) places items in every room of a house and of a district tower, after the
room's furniture, clutter and neon, from an RNG of its own, `hash([run seed, room key, "items"])`: no seed's furniture, doors,
clutter, neon or wear moves, and nothing is added to `RoomSite.solids`. What goes on a piece is catalogue data (`ItemsCatalog`):
`TOPS` by the piece's key (tableware on dining tables, kitchen counters and islands; books, lamps and monitors on desks, shelves,
consoles and night stands; boxes on workbenches, garage shelving, filing cabinets), else `TOPS_BY_ART` by its painter (the
general rule: any table, counter, shelf or cabinet takes a small piece), and an empty row keeps a top bare (a basin, a mirror, a
shoe rack). About half the tops carry items (`WorldGenItemConfig.top_chance`, 0.5): 1 to `top_max` (3), kept inside the top and
off the props its painter draws, a plate or a book now and then stacked on one already there (`stack_chance`); a monitor faces
as its desk does. `ItemsCatalog.FLOOR` gives a stockroom, a garage, a home office and a laundry room floor stacks of 2 to 3 boxes
and crates (a crate or a box at the bottom, boxes on it) by a wall or in a corner, `floor_clear` (22 px) from furniture, doorway
boxes and each other, so a walker keeps a lane. The items sit under a `<Room> Items` node beside the room's furniture node;
`RoomItems.placed_in(house)` reads `[{ room, key, node, on }]`. The test switch `worldgen.items` (`WorldGenItemConfig.enabled`)
builds a house bare. Tests keep items **on** unless a premise needs a bare top: `house_turns` (about fifty houses in one frame
pass the twin space's cap of 10240 bodies), `furniture_holes_cache_matches_recut` (a moved table spills its items, each a cut)
and the two `bake_matches_recorded_colliders` (their figures are of the bare world the 2D colliders baked).

Tests: `worldgen/stacking_keeps_the_layout` (a seeded house's and a district's furniture and tree the same with items on and
off), `worldgen/tops_get_a_few_items` (about half the tops, 1 to 3, inside the top, the same seed the same items).

## SI10. The AI's cover is the stack's height

The AI reads cover through the twin space: 3D lines from the threat's eye to a ducked body's head, chest and hips
(`AgentVision.hiding_piece`, `docs/cover-and-stance.md`), so what hides a spot is what the lines meet, at the height each
body of a stack really stands: one box (12 px) and two leave a ducked head (35.9) showing, three (36) or a crate and two boxes
hide it. It does not read a catalogue row's height (`PieceHeights.top_of`, 12 for the box).

Tests: `ai/combat/box_stack_is_cover_by_height`.

## SI11. A car among them

A car drives over a row of plates (they stay, no crash, no speed lost: SI4) and goes through a stack of boxes, shoving it on and
scattering it into free bodies. A flat item that a car's body tumbled into the `TWIN_WORLD` layer would be struck as a crash, so a
flat item's mask leaves out `TWIN_VEHICLE` as it leaves out `TWIN_CHARACTER`.

Tests: `vehicle/car_drives_over_plates_and_shoves_a_stack`.

## SI12. Cost: the fights moved, perf3d re-picks

Items add bodies (the match district of seed 2: 785 twin bodies, 729 before, 56 of them items; Jolt's cap is 10240, which fifty
houses built in one frame pass) and change the four match guards' fights (a round meets a plate or a box stack): `perf_probe.gd`
records the A/B numbers. No budget is loosened; `perf3d` re-picks the 10v10 guards' fight over at least 24 seeds on a quiet machine
and the `match_npc_vision` premise.
