---
name: domain-worldgen
description: Use when editing scenes/worldgen/ or working on floorplans, room types, furniture catalogues, arrangements, recipes, placement, clutter, wear placement, house doors or the street and its lamps.
---

# World Generation domain (`scenes/worldgen/`)

Picks a floorplan and builds and furnishes a house. It owns the *catalogue* (which furniture, arrangements and recipes exist);
Objects owns the field schema and turns a plain definition dict into a node, so World-Gen never touches an object's fields. A leaf
apart from the five factories (`WallFactory`, `FloorFactory`, `ObjectFactory`, `WearFactory`, `DoorFactory`) and `RoomWalls` / `WearPlan`.
Interfaces: 1 (Main → World Generation, incl. `bounds`, `get_doors` and the test reads `get_wear` / `get_clutter` / `get_street` /
`get_streetlights`), 2 (→ Objects, incl. `DoorFactory`), 11 (`WeightedPick`, the clutter draw). Tests: `tests/worldgen/`.

| File | Role |
|---|---|
| `world_gen.gd` (`WorldGen`) | `generate` picks one `HouseDefinitions.PLANS` floorplan and hands it to `HouseSpawner`; `bounds(rooms)` (the one copy of the rooms' bounding box); `annotate_layout` and the catalogue lookups for outside builders (Testing's arenas and placed pieces). |
| `house_definitions.gd`, `layout_rules.gd` | The floorplans; `LayoutRules`, the table of what makes a plan logical. |
| `categories/doors.gd`, `door_rules.gd`, `house_doors.gd`, `world_gen_door_config.gd` | The doors in a house: `doors.md`. |
| `house_spawner.gd` | Walls, furnishing, floors, the street ring, the street lamps; `_validate` warns with `LayoutRules.check`. |
| `room_furnisher.gd`, `room_site.gd`, `room_dresser.gd` | Placement of arrangements; `RoomSite` is what each room hands them (the plan's `room`, `wall_thickness`, the doorway boxes `blocked`, `solids` so far, its `furniture` node, `run_seed`); clutter, neon and wear placement. |
| `categories/*.gd`, `object_definitions.gd`, `arrangement_definitions.gd` | One `<Name>Catalog` per room type holding `OBJECTS`, `ARRANGEMENTS`, `RECIPES`; the two definitions files merge them behind `get_definition` / `get_arrangement` / `get_recipe`. `general.gd` (`GeneralCatalog`) holds shared entries, the `WOOD` / `FABRIC` palettes, `FLOORS`, `WALL`, `CLUTTER`, `STREET`, the `streetlight` / `street_sign` rows, and the pieces two or more categories use. |
| `world_gen_fill_config.gd`, `world_gen_dress_config.gd`, `world_gen_street_config.gd` | Tuning: fill (`enabled`, `scale`, `attempts`, `max_pieces`), dressing (`near`, `jamb`, clutter and neon and wear chances), the street and its lamps. |

## Floorplans and layout rules

- Rooms are house-local `Rect2`s with a `type`; `openings` are doorway points on wall lines. `HouseSpawner` cuts each opening into
  every wall through it (`WallFactory.openings_for`), keeps opening clearances (`OPENING_CLEARANCE`) free of furniture, and mirrors
  the plan L/R half the time. A doorway with no door is a plain archway; one with a door holds a `Door` (`doors.md`). A doorway is 60 px wide
  inside and 69 px for the front and exit ones.
- Exactly one opening is `front` (the house is positioned by it, always on the south wall); a plan may add `"exit": true`
  openings (one room's exterior wall). `get_openings` reports `{ pos, width, front, exit, rooms, outward, door }`; `outward` is the unit
  normal of each room's wall through the doorway (`HouseSpawner.outward_on`), read by the doorway clearances, the street lamps'
  door rule and the match spawner's invader team.
- `LayoutRules.ROOMS[type]` says whether a type may carry the front door or an exit, may be the only route between two rooms
  (`through`), and its `max_doors`; `LINKS` lists the room-type pairs that may share an interior door. A plan that breaks them
  fails `tests/worldgen/house_doorways_connected_test.gd`; `layout_rules_test.gd` pins the validator against illogical layouts.
  A new room type needs its `ROOMS` / `LINKS` entries before a plan can use it.
- A floorplan must give each room space for its required pieces plus the door lanes (no three-door small bedrooms); otherwise the
  furnisher warns "no room for required zone" and the doorway test fails. `tests/worldgen/house_doorways_connected_test.gd` bakes
  every plan over many seeds: every room's doorways reach each other, each can be passed, and each is reachable from outside the
  front entrance.

## Arrangements, recipes, placement

- Arrangements are authored against the top wall (`x` along, `y` depth); `placement` `"wall"` / `"center"`, `prefer_corner`,
  `tags` (dedupe). An item takes `pos`, optional `rotated` (footprint swap) and optional `facing` (which way its front faces in
  that frame; default `Vector2.DOWN`, into the room). Recipes list ordered `zones` (each picks `count` from `options`, with
  `required` / `fallback`) and `palettes`, each naming its `wood` and `fabric` tones and a `floor` key chosen to contrast with the wood.
- `room_furnisher.gd` fits each arrangement's footprint against a random wall without overlap, rotates / mirrors it (`_map_dir` maps
  an item's `facing` the way positions are mapped, passed on as `opts.facing`) and hands each definition to `ObjectFactory`.
  `_try_place` is the one place a piece is committed (tags, spot search, occupied and walk-grid bookkeeping).
- **Fill pass:** a recipe may carry `fill: { target, options }`; `_fill` draws random `options` through the same placement checks
  until the solid footprints cover `target` of the interior. Each listed option is tried once (list it twice for two tries); a miss
  never becomes a hit later, so a full room ends the pass quickly. Fill consumes the shared RNG: a seed stays stable but changes
  if a recipe's fill does.
- **Ground pieces** (`"ground": true`: the rugs) are non-solid decor lying *under* furniture: they avoid only other ground
  pieces, never touch the walk grid, and are tried dead-centre first. The `"rug"` tag keeps it to one rug a room.
- **Walkability:** furnishing is planned before anything spawns (`_plan`). A spot is accepted only if every doorway of the room
  stays reachable from the others on a coarse grid (furniture grown by `FURNITURE_CLEAR`, the room edge by `WALL_CLEAR`) and no
  dead slot is left: a gap against a wall or furniture must be just the padding or at least `SLOT_MAX`, because a narrower slot
  is unwalkable and its overlapping nav-hole offsets can break the navmesh bake. If a required zone finds no spot the layout is
  re-rolled up to `PLAN_ATTEMPTS` times, then warns.
- Each room's floor (the `FLOORS` entry its palette names) is built after furnishing over the room rect to the wall centrelines
  (so walls cover the seams). It rides on the palette draw, so it costs no extra RNG and seeds keep their layouts.
- Every definition sets `art` (a painter id) and usually `art_opts`; catalogue colours stay plain, because Objects grades every
  colour run down (`domain-objects` (`art.md`)).

## Run-down dressing (`room_dresser.gd`): World-Gen places, Objects draws

- Things gather by `RoomDresser.anchor`: a corner, along a wall's foot, or beside a solid piece (the footprints
  `RoomFurnisher.furnish` appends to `RoomSite.solids`), and stay within `WorldGenDressConfig.near` of a wall line or solid.
- Per room after furnishing: **clutter** (`strew`: 0-2 walk-over non-solid `decor` pieces from the recipe's `clutter`
  `[key, weight]` pairs, default `GeneralCatalog.CLUTTER`; no key twice; off solids and doorway boxes), and about every other room
  a **neon tube** along a wall's foot, clear of doorways. Once every room stands, its **wear**: clusters each handed with the free
  stretch of wall beside it (cut short of doorways by `WorldGenDressConfig.jamb`) to `WearFactory`, which decides and draws the
  marks after all walls, so a mark on a shared wall draws over both caps.
- Every room draws from RNGs of its own, `hash([run seed, room key, ...])`, never the shared RNG, so the dressing never shifts a
  seed's furniture layout (`tests/worldgen/seed_reproducible_test.gd`).

## The street and its lamps

- `HouseSpawner._street`: a sidewalk ring `WorldGenStreetConfig.sidewalk` deep hugging the rooms' bounds and asphalt out to
  `reach`, four strips each (top and bottom span the corners), through `FloorFactory` from `GeneralCatalog.STREET`: `sound_surface:
  false` (footsteps stay `outdoor`) and `light_layer: "street"` (lit only by the street lamps, the flashes and the sky,
  `docs/lighting.md` L4). Each carries `marks` `{ seed, edges, lane }` and a shared `tile_from`, so slab joints meet.
- `HouseSpawner._streetlights`: along the front sidewalk, spaced and jittered by `streetlight_every` / `streetlight_jitter`, each
  post `streetlight_curb` in from the curb with its arm over the road; every other one is a neon `street_sign`, the rest
  `streetlight`s: solid `anchored` posts with an `overhang`, spawned through `ObjectFactory` under a `Street Lamps` node of the
  house, so the nav bake carves them.
- **The door rule** (`_door_zones`, `_clear_of_doors`, reading each doorway's `outward`): no part of a lamp (post square and
  overhang) comes within `streetlight_door_clear` of a front or exit doorway's centre or into the strip straight out of one
  (`streetlight_door_strip_*`). A lamp that would is dropped, not moved. Its own RNG, `hash([run seed, "streetlights"])`
  (`tests/worldgen/streetlight_placement_test.gd`).
- The house carries what it placed as metadata, read through interface 1: `rooms`, `openings`, `doors`, and, for tests, `clutter`,
  `wear`, `street`, `streetlights` (the `get_*` reads).

## To add a room type

Add a `categories/<type>.gd` catalog with its recipe (register it in `ObjectDefinitions` and `ArrangementDefinitions`), give the
type `LayoutRules.ROOMS` / `LINKS` entries, and use its key as a room `type`. Pieces used by two or more categories live in
`GeneralCatalog`. A new `class_name` script resolves only after Godot rescans (open the editor or run `tools/load_check.sh --import`,
which also writes the `.uid` files).

## To add or change a floorplan

Rooms are rects that share walls; put a doorway on each shared wall you want open and make the graph satisfy `LayoutRules`
(check with `tools/run_tests.sh worldgen`). Mind the room sizes (above).
