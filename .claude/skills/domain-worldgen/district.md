# The downtown district (`scenes/worldgen/`, interface 1)

`WorldGen.generate_district(seed, force_plan, front_entrance_world, parent)` builds the world a match is fought in: a 3 x 3 grid of
blocks (a **tower** each), asphalt streets and sidewalks between and round them, and a ring of 16 roofless **shells**. The centre tower
(block 4) is the **house**. Nothing is drawn overhead: no roofs, no upper floors. The root `District` (a `Node2D` at the origin, so every
position it reports is world space) carries the metas that `WorldGen` and `DistrictReads` read (interface 1).

| File | Role |
|---|---|
| `district_layout.gd` (`DistrictLayout.compute(seed, force_plan)`) | Pure data from a seed, built before any node: per block its plan, turn, footprint and tower corner; the street tiles with their marks; the `landings` (each crossing and the sidewalk at both ends); the 16 shell rects; the streets' `extent`. |
| `district_spawner.gd` (`DistrictSpawner`) | Builds it: streets, a tower per block, the lamps and clutter, the shells. Shifts the layout so the house's front door lands on the entrance. |
| `district_streets.gd` (`DistrictStreets`) | The street floors, the lamps along every block's sidewalks and the sidewalk clutter. |
| `tower_dressing.gd` (`TowerDressing`) | A tower's street shadow, podium band, door awning and glyph sign. |
| `district_shells.gd` (`DistrictShells`) | The ring of shells. |
| `district_reads.gd` (`DistrictReads`) | The test reads (interface 1). |
| `tower_definitions.gd` (`TowerDefinitions`) | The six tower plans. |
| `street_lamps.gd` (`StreetLamps`) | Lamp runs and the door rule, shared with a lone house's street. |
| `world_gen_district_config.gd`, `world_gen_tower_config.gd`, `world_gen_shell_config.gd` | Tuning: the grid's streets, sidewalks, shell ring, crossings, lamps and clutter; a tower's podium, shadow and body; a shell's decor. |

## Plans and room types

- A tower plan is a house plan (`HouseDefinitions` format, plan-local, the front door on the south wall) in `TowerDefinitions.PLANS`:
  `bodega_tower`, `noodle_tower`, `arcade_tower`, `clinic_tower`, `corner_shop_tower`, `food_hall_tower`. Each has exactly one front door, at
  most one `exit` and exactly one `elevator_lobby`. `HouseSpawner.plan_of` finds a key in the houses, else the towers;
  `HouseDefinitions.get_all()` stays the houses, so a random house pick never lands on a tower, and a district's neighbours draw
  `TowerDefinitions.get_all()` only. The 11 house plans reach a district only as the centre `force_plan`.
- New room types, each a `categories/<type>.gd` catalogue with `LayoutRules.ROOMS` / `LINKS` entries and `DoorRules` rows: `shop`,
  `noodle_bar` (either may carry the front door), `stockroom` (may carry the exit), `elevator_lobby`. Street pieces live in
  `categories/street.gd` (`StreetCatalog`).
- **The elevator lobby** is a placeholder for stairs and elevators: about 240 x 200 px, `max_doors` 1 and not `through`, so one interior
  doorway and no exterior door. Its recipe is `bare` (`ElevatorLobbyCatalog`): no pieces, clutter or neon, only a concrete floor under a
  `DecalFactory.stencil` of its `text`, "WIP ELEVATOR LOBBY" in a hazard border, laid by `HouseSpawner._lay_stencil` and read by
  `WorldGen.get_lobbies`. In the house it is an ordinary room to the AI.

## Turning

`HouseSpawner.spawn(..., options)` takes `turn` (0 to 3 quarter turns clockwise on screen) applied after the mirror, and `street` (off in
a district: `DistrictStreets` builds the streets). It validates plan-local before turning, so `LayoutRules.check` and "front on the south
wall" hold for any facing; `outward` of every opening follows the turn. `HouseSpawner.footprint(plan, seed, turn)` sizes a tower without
building it. `WorldGen.generate` never turns, so a lone house keeps its south front and every older test its layout. The stencil's canvas
is never rotated, so the lobby's words stay upright.

## Layout and streets

- Per block `hash([seed, "plan", block])` draws the plan, `[seed, "facing", block]` the turn (so the front faces one of its block's four
  streets) and `[seed, "tower", block]` the tower's own build seed. Each column is as wide as its widest tower, each row as deep as its
  deepest; a tower stands against the edge of its block that its front faces, so its front wall sits on that street's sidewalk.
  Streets are `street_width` wide, sidewalks `sidewalk` deep round each block (sidewalk tiles wholly under a tower are left out).
- Every street floor goes through `FloorFactory` from `GeneralCatalog.STREET` as a lone house's ring does (no sound surface, street
  light layer), cut to `tile_max` on a side so a floor stays within the lighting budget. Each road tile ending at a junction carries that
  arm's `marks.crossings` and `glyphs` (interface 2).
- **Lamps** (`DistrictStreets.lamps`): along all four sides of every block, every other one a neon `street_sign`, `lamp_corner_inset` from
  the corners. A lamp is dropped, not moved, when it meets a doorway zone of **any** tower (`StreetLamps.door_zones`, the door rule) or a
  crossing's landing. **Clutter** (`DistrictStreets.clutter`): a slot about every `clutter_every` px, its piece drawn by `CLUTTER`'s weights
  (vending machine, bench, bin, drain grate, litter), dropped where it meets a doorway zone, a landing, a lamp, a tower's body or another
  piece. Each block side draws from `hash([seed, "lamps" or "clutter", block, side])`.

## Reading as tall (`TowerDressing.dress`)

From a tower's published `get_rooms` / `get_openings`, so a turned tower is dressed as it stands: a long hard street shadow
(`DecalFactory.shadow`, `shadow_length`, away from the art light); a **podium** band of concrete `podium` pieces along every exterior wall,
broken `podium_door_gap` each side of every front and exit doorway (room for an entry stack's slots); a dark **awning** and a hanging
**glyph sign** over the front door (the `awning` and `glyph_sign` rows of `GeneralCatalog`, `overhang.fade_under`). `exterior_runs` finds
the wall stretches no other room abuts. The street furniture keeps off the podium plus `tower_margin`.

## Shells (`DistrictShells`)

A solid outer wall with no doorway (the house wall style), a concrete floor and a few partition walls whose doorways are all inside. The
style is by the seed: `bare`, `site` (rebar, rubble, scaffold, cement bags) or `derelict` (trash, puddles, cardboard, damp stains down the
walls). A shell is no room: not in `district_rooms`, no light fixture, and outside `district_bounds`, so the nav map leaves it out.

## Adding a tower plan

Add it to `TowerDefinitions.PLANS`: plan-local rooms and openings with one `front` (south wall, 69 px), at most one `exit`, one
`elevator_lobby` (240 x 200) with one interior doorway, and `door_sets` (`SHOPFRONT` or `STEEL_FRONT`). A new room type needs its
catalogue, `LayoutRules`, `DoorRules` and registration (`domain-worldgen`). Check with `tools/run_tests.sh worldgen`:
`tower_plans_connected` holds every plan in all four turns and both mirrors to `LayoutRules`, reachability and one lobby.
