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
`TOPS` by the piece's key (today a plate, cup, bowl, book or lamp on a table, a dining table and a coffee table, a box or a book on a
filing cabinet, and a bare top for a mirror, a sink and a laundry sink; a piece that carries its own items, SI13 and SI14, has no row),
else `TOPS_BY_ART` by its painter (the
general rule: any table, counter or cabinet takes a small piece; a shelf carries its own, `PieceCarries`), and an empty row keeps a top bare (a basin, a mirror, a
shoe rack). About half the tops carry items (`WorldGenItemConfig.top_chance`, 0.5): 1 to `top_max` (3) items (a plate or a book may
be stacked on one more now and then, `stack_chance`), each inside the top's main flat part (`ObjectFactory.flat_top`: the footprint
but for a part that rises over it, a counter's backsplash, which an item keeps off: set against it, it would lean); a monitor
faces as its desk does. A piece that carries its own items (SI13, SI14) takes no fill. `ItemsCatalog.FLOOR` gives a stockroom, a garage, a home office and a laundry
room floor stacks of 2 to 3 boxes and crates by a wall or in a corner, `floor_clear` (22 px) from furniture, doorway boxes and each
other, so a walker keeps a lane. **An item goes only where its footprint fits**: on a stack, one at least as big as the one under it
(a crate on a crate, a box on a box or a crate, never a crate on a box: it would overhang and topple), put off its centre by at most
the margin the two footprints leave (`ItemsCatalog.fitting`, `RoomItems._jitter`: nothing for two of a size), so a placed item
settles where it was set. The items sit under a `<Room> Items` node beside the room's furniture node;
`RoomItems.placed_in(house)` reads `[{ room, key, node, on }]`. The test switch `worldgen.items` (`WorldGenItemConfig.enabled`)
builds a house bare. Tests keep items **on** unless a premise needs a bare top: `house_turns` (about fifty houses in one frame
pass the twin space's cap of 10240 bodies), `furniture_holes_cache_matches_recut` (a moved table spills its items, each a cut)
and the two `bake_matches_recorded_colliders` (their figures are of the bare world the 2D colliders baked).

A room that gets no item has no `<Room> Items` node.

Tests: `worldgen/stacking_keeps_the_layout` (a seeded house's and a district's whole tree, the doors' openings, materials and styles
the same with items on and off), `worldgen/tops_get_a_few_items` (about half the tops, 1 to 3, inside the top, the same seed the
same items), `worldgen/items_fit_what_they_stand_on` (inside the footprint under, off a backsplash), `worldgen/items_settle_in_district_11`,
`_in_district_16`, `_in_houses` (after 2 s every item is asleep within 3 px and 8 degrees of where it was set; a three-high stack
is measured asleep by 1.0 s).

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

Items add bodies (the match district of seed 2: 785 twin bodies, 729 before, 56 of them items; Jolt's cap is 10240 bodies, and a build
that nears it aborts the engine, it does not degrade: `worldgen/house_turns`, about fifty houses in one frame, shows it, so it
builds them bare) and change the four match guards' fights (a round meets a plate or a box stack): `perf_probe.gd`
records the A/B numbers. No budget is loosened; `perf3d` re-picks the 10v10 guards' fight over at least 24 seeds on a quiet machine
and the `match_npc_vision` premise.

## SI13. Unbake: what a piece built in is loose items (job `unbake-b`, shelves and stock; D21)

A piece whose look or mesh would build loose things in gives them up as separate items (rule 9), set where its rows name,
and is drawn without them: its mesh, its painter and its `PieceHeights` leave them out. This part is the shelves and the stock;
the home tops (`unbake-a`) and the shops and special rooms (`unbake-c`) follow the same rule. **The unbake rule:** an emptied
piece says what it carries as **data** (`PieceCarries`, Objects: a catalogue row's `carries`, rows of `{ key, at, size, lift, height,
color, weight, maybe, on_top }`, `at` from the piece's centre in the painter's canonical frame, or, for a shelf, `art_opts.loose` and the generator
`ShelfLoose` that walks the boards the old mesh walked, with the same seed); `RoomItems.carry` sets each item with
`ObjectFactory.spawn_on` and `rest_at` (the height it stands on), the entry `carried: true`. The random few-per-top fill skips an
emptied piece (`ItemsCatalog.options_for` is empty for it). With `worldgen.items` off a house is built bare: an emptied piece shows
empty.

- **Shelves** (bookshelf, shelving, linen shelf, shoe rack: `art: "shelf"`, `art_opts.loose`): the sides, the back and a slab per board
  but the top one are the parts (`ShelfMesh.hollow_parts`), so the compartments are open to a round, a line of sight and what stands
  on a board; the shelf has **no top board** (the camera looks down at it: what it holds is seen, lit, as the old flat paint showed it,
  the top compartment's things on its boards; the bare boards are painted wood). The sides and the back are `ShelfMesh.HULL` (4 px)
  thick as bodies, thicker than drawn (a car shoves a 2 px plate along without laying the shelf over), and the things keep inside them.
  The body moves as the solid box of its extent (centre of mass and inertia: `PieceBody`, `PieceHeights.hollow`), so a shove lays it
  over as it laid the solid shelf. Books are `book_stood` items in runs of up to six side by side (one body, the spines drawn from
  `art_opts.spines`, pale page-block tops as the old mesh drew): a bookshelf of hundreds of books would be as many bodies; a run is
  18 px of paper, penetration 70: **a pistol round through a run is spent** (it loses over half its speed) and a rifle round carries
  on. Shelving and linen-shelf boxes are `box` items sized to the row, with the odd `paint_tin` (the old painter's, 3 places in 10 of a board); shoe racks hold `shoes` (a pair). **Sight:** a viewer in front
  looks into an empty compartment (the front is open) and sees its back; the back and the sides stop sight at every height.
- **Crate stack and pallet** (`StockroomCatalog`): `crate_stack` and `wrapped_pallet` are bare places (non-solid, no art, no mass:
  `PieceHeights.parts_of` says 0). The stack is two or three loose `crate` items (38 px across, 20 high, the second 4 px off; a third, 34 px across, on the pair for about half the places: the row's `maybe`, by where the place stands), the pallet a
  `pallet` item (a low item a walker steps over, 5 px) with four `wrapped_box` items on it. A place keeps its `examine`, and its footprint
  is in `RoomSite.solids` (`RoomFurnisher`: a place that carries is a solid for the dressing, the wear and the floor stacks, though it is no
  solid piece), so nothing lies under its crates. The stockroom floor is strewn with stacks of boxes and crates on the free floor around the stock
  (`ItemsCatalog.FLOOR`'s `stockroom` row, the garage's).
- **Hotplate** (`KitchenetteCatalog`): the piece is the crate (12 px, still giving the ring's light); the plate (`hob`, with its
  hot ring glowing) and the pan stand on it.
- New kinds (`LooseStockCatalog`; `item_stock_mesh.gd`, `item_stock_painter.gd`, heights in `ObjectMeshStockItemConfig`): `pallet`,
  `wrapped_box`, `book_stood`, `shoes`, `paint_tin` (the old painter's odd tin on a shelf of boxes: 30 % of the places on a board, at most 5 px a radius, 8 high), `hob`, `pan`, `pot` (the noodle bar's, unused by this job). An item's flat art is painted
  by its `kind` alone (`ObjectArt._art_opts`) and `DistrictPrewarm` warms every carried item at its size.

Tests: `objects/emptied_shelving_carries_its_boxes`, `objects/bookshelf_tips_and_spills_its_books` (the books stand asleep at the
start; a tipped shelf spills them), `objects/emptied_shelves_keep_their_things` (nothing thrown out of a compartment),
`objects/hollow_shelf_compartments_are_open` (a ray between boards reaches the back, at a board the lip, a side stops it),
`objects/hollow_shelf_moves_like_a_solid_one` (inertia, tipping, slide), `projectile/round_through_a_run_of_books` (pistol stopped,
rifle through), `art/emptied_shelves_windowed` (the contents read as bright as the old look under the game camera), the car and the
hysteresis tests (`vehicle/car_tips_a_bookshelf_but_slides_a_sofa`, `objects/tipped_piece_has_hysteresis_and_cuts_when_changed`) on
the real bookshelf, `worldgen/old_looks_keep_their_items` (stockrooms, kitchenettes, shelves), and the settle and fit tests
(`worldgen/items_settle_in_*`, `items_fit_what_they_stand_on`) over the carried items.

## SI14. Unbake: the home tops carry their props as items (job `unbake-a`; D21)

A piece's top shows small props (a desk's monitor, keyboard, mug and papers). Painted into the piece they would show in 3D only as a flat
texture, so each is a free item (`props.gd` keeps the painter these are measured against). The unbake rule of SI13 holds: a loose thing a piece's look builds in is a separate item. For the home tops each painted prop is now an item, set
at the point the prop's drawing had, so the look is kept and each moves alone (SI3). The catalogue has no `art_opts.props`; a piece's row holds
`carries` rows in the one schema of SI13 (`PieceCarries`: `{ key, at, ... }`, `at` in px from the piece's centre in the painter's frame, the
front toward +y; the points are those the old painter drew, the prop's unit point through the painter's rect inset 3 px). The home rows say
**`on_top: true`** and no `lift` or `size`: the item rests on the piece's top where it is (`ObjectFactory.top_at` reads the part under the
point, so an item set on a counter's slab starts on the slab, not the backsplash, and on what already lies there) and has the catalogue
item's own size. `RoomItems.carry` (one, SI13's) sets them all; a piece that carries takes no random few-per-top fill
(`ItemsCatalog.options_for` is empty for it: one guard, `PieceCarries.carries`).

| piece | carries |
|---|---|
| `desk` | monitor, keyboard, mug (`cup`), papers |
| `side_table` | book |
| `nightstand` | clock, book |
| `dresser` | vase, book |
| `console_table` | bowl, vase |
| `kitchen_counter`, `kitchenette_counter` | cutting board |
| `island` | fruit bowl |
| `workbench` | tools, vise |

The new kinds are `HomeItemsCatalog` rows (art id `item`: `item_home_painter.gd`, `item_home_mesh.gd`, heights in `ObjectMeshHomeItemConfig`):
keyboard (18 x 6, 1.5 high, plastic), papers (11 x 14, 0.6, paper), clock (8 round, 4), vase (8 round, 10, ceramic), fruit bowl (12 round, 6),
cutting board (16 x 11, 1.5, wood), tools (16 x 14, 2.5, metal) and vise (10 x 12, 5, metal, weight 10: a cast-iron bench vise, the heaviest of
them); the monitor is 24 x 8 as its prop was. All of them, the vase too, lie within a step (`DoorFallConfig.step_over` 10 px; the rule is "no
higher than", and the vase's 10 is at the line), so a walker steps over one on the floor (SI4); thin paper (a 1 px penetration) stops no round.
They place only on the piece's footprint, so a sampled house has them asleep within two seconds (`worldgen/items_settle_in_houses`).
**The old look is kept**: a home item paints in the prop palette (`ObjectArtDecorConfig.prop_colors`) at the prop's size, not in the catalogue
colour's run-down grade (a carrying `on_top` row sets `art_opts.plain`: the mesh and the flat art, and the district's warm of it, use the item's own colour; the bowl and the mug paint as the props did, a fruit bowl and a vase stand a flat-topped fruit and flower on each spot the painter draws one, so the lit top reads as the painted one: `art/home_items_lit_windowed`), and the monitor's lit
front edge is drawn `glowing` in `Decay.screen_color` (the screen's green, or the neon) and is an emissive glow node of its mesh (`ItemMesh._monitor_glow`:
a strip on the screen's top and a panel on its front, the old prop's bar being a 1 px lit line along the screen's front edge, in the room's light too: a painted edge went dull under it; `objects/monitor_edge_glows_in_a_lit_room_windowed`).
The reused kinds take the prop's size, orientation and palette colour from the `carries` row that sets them (a book 12 x 9 lying landscape in a
book colour, a mug and a bowl ceramic, the bowl 12 round; `objects/home_items_keep_the_old_look`), a mug has its coffee and a bowl its well, and the
tools and the vise are slim and small as drawn (a hammer, a wrench and a screwdriver apart; a stand with its jaw and screw).

**The desk's light** is the monitor item's: `ObjectArt.light_kind("item", { kind: "monitor" })` is the `monitor` row of
`ObjectArtLightConfig.specs` (the `desk` row of a table paints no monitor), so a desk gives no screen light, the monitor does. The row's
`lift` (8) is over the item's own base (`rides`: `WorldLighting3D` hangs it over the item's twin and re-hangs it when the base moves), so the
glow is 8 px over a desk's top, and a monitor shoved off its desk takes its glow with it and down to the floor, to where it lands
(interface 20; `lighting/knocked_monitor_takes_its_glow`). Its pool stands `ahead` 22 px past the item's front edge: where the desk's old
row had it (12 px inside the desk's front edge). **The neon** is the desk's: `ObjectArtLightConfig.neon_share["desk"]` (a table's `neon_as`
option names it; no other table takes one) gives about half the desks a neon strip round the edge and its `trim` light, as before; a monitor
item rolls none of its own (`neon_share` has no `monitor`): `RoomItems.carry` hands a desk's neon to the monitor it sets (its lit edge and its light), so a
desk's trim and its screen never disagree (`objects/desk_keeps_its_neon_trim`). A light is built with the
world's lighting: an item set on a built world later (a test's `carry`) has none.

A piece set bare (a test's `s.object(&"desk", "desk", ...)`, `worldgen.items` off) carries nothing: the premise of a test built on one is a
bare desk (the ajar-door tests, the blast and casing tests).

Tests: `objects/emptied_desk_carries_its_items` (four items, each asleep on the top, a shove moves the monitor alone),
`worldgen/old_looks_keep_their_items` (the one test of SI13 and SI14: also each home top paints no props and carries exactly its rows at the drawn points),
`lighting/knocked_monitor_takes_its_glow` (the light follows the item down; its mutant 'the light stays' is red), `objects/desk_keeps_its_neon_trim`, `objects/home_items_keep_the_old_look` (size, palette and the glowing edge against `props.gd`), `objects/piece_heights` (the new kinds' tops), `worldgen/items_settle_in_houses`,
`_in_district_11`, `_in_district_16` and `worldgen/items_fit_what_they_stand_on` (they read every `Items` node, carried ones included).

**The floor stacks and the items' draws.** `RoomItems.place` draws a room's floor stacks from the same RNG as its tops, and a piece that
carries (SI13, SI14) takes no top roll: a room's floor stacks are what the draws after its carrying pieces give. A mesh lit on a top is judged
against the old prop by `art/home_items_lit_windowed` (windowed).

## SI15. Unbake: sandbags, a hat, and what hangs stays drawn (job `unbake-d`; D21)

- **Sandbags.** The security barricade (`SecurityVestibuleCatalog`) is the bare slab; its sandbags are eight `sandbag` items (`LooseStockCatalog`: 15 by 8
  px, 10 high, `fabric`, penetration 90: a bag of sand stops a round as the barricade it flanked did) set by its `carries` rows where the painter drew
  them: two stacks of three side by side at the ends and a smaller bag (11 by 4, 6 high) on each middle one. The slab is 4 px shorter at each end
  (`SecurityMesh.BAG_OVERLAP`: the stacks of bags end 4 px past 12 % of its width, and a free body must not start inside another); the mesh, the
  painter and the part (`PieceHeights`) are all that slab. A bag is 10 high: within a step (SI4), so a walker steps over one and it carves no nav hole.
- **The coat rack's hat** is a `hat` item (a brim and a crown) resting on the rack's top (`on_top`), over the post. A hat on a rack is a thing standing on a
  top like a mug on a desk: knock the rack over and it falls off.
- **Coats and towels stay drawn, with a reason each.** A hanging coat or towel has no rest pose: it hangs from a hook or a rail, so as a free body it would
  need a pin (a joint) to its hook, and the twin space carries no joints (a body is a rest-on-the-floor-or-a-top piece, interface 29): a free body there would
  fall to the floor. Cloth also stops no round and blocks no walker, so a drawn coat costs nothing the player reads; the rack's mesh keeps its three
  coats and the towel rail its towels (`fixture_mesh`, kind `towels`), as the painted ones did. A pin joint is the follow-up if a hanging body is wanted.
- **Cover and the nav at the barricade.** Its cover is the slab: 84 of its 120 px across (12 % in from each end plus the 4 px the bags' stacks end at, 0.70), 40
  high (`furniture_commercial_mesh` pins its cover share at 0.65 for that reason). Its ends carry only bags, 10 high (a small one on a middle bag brings a stack
  to 16): under a ducked head (35.9), so a ducked fighter at an end of the barricade is not covered there (the slab covers), and a walker steps over a bag on
  the floor (10 is within a step; no nav hole). The two small top bags rest 10 px up and are 16 high, past a step: each cuts a nav hole, 11 by 4 px, over the
  bag under it (`objects/emptied_barricade_and_coat_rack_carry_items` pins the two top bags: lift 10, 11 by 4, 6 high).
- **Their own colour.** The bags are `plain` by their rows (`PieceCarries`) and the hat is plain through `on_top`: the sandbags' tan and the hat's coat-palette colour are not
  graded to the run-down look (graded, a bag was lit at 0.39 of the old bag's luminance: `art/home_items_lit_windowed`, bar 0.85). The hat's colour is a
  `palette` row: a colour of `ObjectArtDecorConfig.prop_colors["coats"]` picked by where its rack stands, as the old hat's was; the district's warm
  paints every colour of the palette.
- A pistol round does not pass a sandbag (`projectile/round_stopped_by_a_sandbag`: penetration 90; the mutant 20 lets it through).
- Tests: `objects/emptied_barricade_and_coat_rack_carry_items` (no sandbag or hat in the meshes, eight bags at the drawn points asleep, the hat on the top, a
  shove moves one bag alone), `worldgen/old_looks_keep_their_items` (a district's barricades and racks).

## SI16. Unbake: the shops and special rooms carry what they drew as items (job `unbake-c`; D21)

The unbake rule of SI13 and the `on_top` rows of SI14 hold for the commercial and special pieces: what their painter and mesh drew
loose is a free item set where it was drawn, and the piece is drawn bare (`PieceCarries`, one `RoomItems.carry`). `ShopItemsCatalog`
has the new kinds (art id `item`: `item_shop_painter.gd`, `item_shop_mesh.gd`, heights in `ObjectMeshShopItemConfig`); the rest are
kinds that exist (`pot`, `bowl`, `monitor`, `keyboard`, `cup`, `papers`).

| piece | carries |
|---|---|
| `shop_counter` | till (its screen is a glow node), jar, five packs |
| `noodle_counter` | three pots (16 px round, 11 high), three bowls |
| `noodle_booth` | two bowls on the table |
| `tool_cart` | instruments, syringe, a diagnostic `monitor` (9 by 6) |
| `monitor_wall` | keyboard, mug (`cup`), papers on the ledge |
| `drinks_fridge`, `snack_machine`, `shelf_aisle` | runs of bottles, snack packs (below) |

The monitor wall's `PieceHeights` are its real parts now (the desk and its ledge 31 px, the band of the screens 53, the rail 62: an
item set on the ledge starts on it, not on the rail); the cart's tray is still the cart's one box, so an item stands on the rim, 2 px
over the tray's floor.

**Stock behind glass (the fridge, the snack machine, the shelf aisle).** These three are hollow (`ShopHollow`):
thin parts round open bays, like the emptied shelves of SI13, and they move as the solid box of their extent (`PieceBody._as_solid`).
Their stock is free items on the boards, from `ShopStock`: a run of up to four bottles (`bottles`, glass) on the fridge's three shelves,
snack packs (`snacks`, cardboard) on the machine's two and on each side of an aisle's three tiers; a run is one body, its `spines` what
the mesh draws. The fridge's and the machine's front is a **glass part** (3 px, a collider; the pane is not drawn: a clear pane has no
mesh) that holds the stock in when the piece lurches or turns; a piece laid on its side spills it. A round meets the glass as glass
(`penetration` 6, material `glass`: `EnvironmentObject.get_surface_at_point`, which the Projectile reads where it has the point struck; the steel
elsewhere), goes on through it to the bottles, and meets each by its own material. **The stock shows through the glass** (user decision, D21): it
stands against the glass (a bay's `front`, `ShopStock.FRONT_GAP`), and the front is a lit glow node (the fridge's pale blue, the machine's
glass colour, no collider) with a 3 px window cut for each bottle or pack (`ShopStock.windows`, `ShopMesh._glass`), so a
player sees each item against the glow round it. The fridge's pane sits just inside its glass, the glass's own width (1 px a side narrower than the
old front's 3, so a thin dark frame shows round it) and its bottles stand dark against it. The machine's pane is **flush with its face**
(`ShopMesh._pane_y`: just inside the glass it sat in the roof band's shade and read as a dim slit) and as wide as its bay, and each pack's
window holds a **lit tile of that pack's colour** (a glow node per colour, `ShopMesh._pack_faces`, `ShopStock.faces`): the packs stand in the
shade, so without the tile the machine's stock read as black ticks. A window is where an item of a row stood when the piece was built: a bottle that has
left the shelf leaves a dark window, and a piece shoved from behind (lurched, not tipped) keeps its stock behind its windows to within 1.5 px
(`objects/stocked_fridge_keeps_its_stock`; the pack is 5 px wide, its window 3). The flat art laid over the roof still paints the old pane and packs (`ShopPainter._fridge`, `_snack`): it is
the old look, kept on the roof. **Not done:** breaking the glass (a shot leaves the front whole, so the stock never falls out of an upright piece), the
monitor wall's screens (part of the wall: a screen is a lit pane of its band, not a loose thing).

**The cyberware shelf.** The ripperdoc's shelf is hollow too (`CyberwareShelf`) and steps up in three columns, a board on four posts each, the left lowest and the right as tall as the shelf, moving as the solid box of its extent. No board is over another's cyberware: the game camera looks down on the shelf, so a tier under a board would hide its items, and every item shows from above. Its items are free on the boards, laid left to right along each column by a generator seeded from the look: chrome arms (`cyber_arm`: a bar with its joint, lying the depth of the column) and stacks of three small things across it, eyes (`cyber_eye`, a ball with its pupil), chips (`cyber_chip`, a body with its pins) and jars (`cyber_jar`), each in its own colour (`plain`); a shelf is 26 of them (a step of `ARM_STEP` 4 px along a column after an arm, of `SMALL_STEP` 6 after a stack of `SMALL` 3 across the depth at a `SMALL_STRIDE` of 9). Tests: `objects/cyberware_shelf_carries_its_cyberware` (26 items, no part over any item) and the shelf in `objects/emptied_shelves_keep_their_things`.

**Sight and the glass.** The glass front of the fridge and the snack machine is a plain collider, not transparent: `get_surface()` (read per body by `SightRay`) says opaque for the whole piece, so AI and player sight stop at the glass as at a solid fridge, though the stock behind it is drawn. A round meets the glass as glass (`EnvironmentObject.get_surface_at_point`, `ShopHollow.surface_at`). **The aisle's bays are open:** a shelf aisle is two runs of boards with posts, a middle panel and a lip, so a ducked eye (32 px) sees through the bays between its boards (the old solid aisle blocked it): `docs/player-vision.md`. A standing eye looks over the aisle's 36 px top as it did.

**The old look** (D21: a piece looks as it did, its parts now real). The noodle counter's pots carry their broth (`well` on the row, `ItemStockMesh._pot` and `ItemStockPainter._pot`; the item's flat art is laid over its mesh top, so the flat art carries the broth too: `objects/noodle_pot_paints_its_broth`). A noodle bowl is a row's item, so `plain`, and paints as the old noodle painter's: a rim of its own colour to the footprint's edge and the broth two pixels in, no outline ring, its mesh the old plain cylinder (`objects/noodle_bowl_is_the_old_size`). A run's top is painted pack by pack (`spines` reach the flat art); the cyberware's lid is a rim; the tool cart's diagnostic screen is its own item, `screen` (a dark body with a lit pane in the piece's neon).
The **oracle** is the old code itself, kept as `tests/_art/old_*.gd`: `old_shop_look.gd` holds what the shop, noodle, clinic and tech painters drew of each thing and `old_shop_pieces.gd` builds a shop piece with the old `shop_mesh`, `noodle_mesh`, `clinic_mesh`, `tech_mesh` and painters. It is a geometry and shape oracle that reads the live tunables (`ObjectMeshShopConfig`, `ObjectArtShopConfig` and the rest), not a frozen picture: retune a colour or a height and the old and the new move together. Two windowed tests set old against new at one spot in turn under one light: `art/shop_items_lit_windowed` (each kind of item alone: its mean colour, the pixels it changes within a least and most share, its bright and saturated pixels, a pot's middle) and `art/shop_pieces_lit_windowed` (the nine whole pieces: bright and saturated pixels, mean luminance and colour, and the stock's shape: on the fridge the runs of dark stock a scan line of the front crosses, 8 against the old 10, on the snack machine the runs of lit pack colour, 4 where the old front and the front before its flush pane had none). Each bar is its kind's measured result less a little for the GPU, and each that sits at its result states a cause in the test.

**Bodies, and the rule for grouping.** `TwinSpace.bodies()` 120 frames after `s.district(Perf.MATCH_SEED, "garage_home")` is built: seed 2 holds 1165 bodies, seed 13 1410; a quiet district's physics step costs about a tenth of a millisecond more than without the shops' items, all asleep. Nothing is grouped beyond **a run is one body** (up to four like bottles or
packs, `ShopStock.RUN`, as a `book_stood` run is). The rule: where a room's free bodies would make a fight frame cost show, group
like items into runs of one body per row (a row is what stands in a line on one board); a shelf of cyberware (26 bodies) is not one.
Tests: `worldgen/old_looks_keep_their_items`
(`COMMERCIAL`: each piece carries exactly its row and paints none of it), `objects/furniture_commercial_mesh`,
`objects/piece_heights`, `objects/stocked_fridge_keeps_its_stock`, `objects/lit_front_shows_its_stock`, `objects/shop_stock_paints_its_packs`, `objects/emptied_shelves_keep_their_things`,
`projectile/round_through_a_fridge_glass`.
