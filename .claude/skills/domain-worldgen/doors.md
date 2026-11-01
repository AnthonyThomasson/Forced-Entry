# World-Gen's doors (`categories/doors.gd`, `door_rules.gd`, `house_doors.gd`; spec `docs/doors.md` DR1 to DR4)

- **The catalogue** (`DoorCatalog`): one definition per material and style (`hollow_flush`, `hollow_panelled`, `solid_panelled`,
  `solid_plank`, `steel_riveted`, `steel_peephole`, `glass_panes`): `name`, `material`, `style`, `color` (one per material).
  `WorldGen.door_definition(material, style)` reads it (interface 1; `DoorCatalog.by_key` reads it by key, which the door sets list) and
  `DoorFactory.spawn` (interface 2, Objects) builds it. What a material is made of is Objects' `DoorMaterialConfig`.
- **The rules** (`DoorRules`, a rules table beside `LayoutRules`): `ROOMS[type]` = `rank` (how private) and `chance` (the share of the
  doorways it is the more private room of that get a door: bathroom and netrunner den 1.0; bedroom, office, ripperdoc 0.85; garage and
  laundry 0.5; kitchens, living spaces, studio, vestibule 0.15; hallway 0.0, so never between two hallways); a type with no entry gets
  `DEFAULT_ROOM`. `SETS` = the default door sets per kind (`front`, `exit`: solid wood; `interior`: hollow-core), `TIE_FIRST`,
  `START_WEIGHTS` (shut 0.6, ajar 0.15, open 0.25) and `AJAR_DEGREES` (15 to 35). `chance(a, b)`, `rank(type)` and `set_of(kind,
  plan_sets)` read it.
- **The floorplans** (`HouseDefinitions`): an opening may carry `door: true` / `false` (forced / forbidden whatever the rooms say) and
  `door_set` (one of the plan's `door_sets`, which name sets for `front`, `exit`, `interior` or any name an opening picks). The flats and
  the loft have steel at the street, the houses solid wood; `open_plan_home`'s patio exit and `office_loft`'s office door are
  glass-panel.
- **Doorway width** (DR1): 60 px inside, 69 px for the front and exit ones (`tests/worldgen/doorway_widths_test.gd`).
- **Building** (`HouseDoors.build`, called by `HouseSpawner.spawn` after the rooms and wear, with the mirrored plan): each doorway rolls
  from a stream of its own, `hash([run seed, "doors", its index])`, drawing the same values whatever the outcome, so it never shifts
  another door's roll nor the shared RNG the furniture draws from. It has a door when the plan's `door` flag says so, else always for a
  front or exit doorway, else by the `chance` of its rooms' types. It swings into the more private room (a tie: seeded), an exterior
  door into the house; the hinge is on the jamb nearer that room's corner along the wall (the middle: seeded), `wall_thickness / 2` in
  from the gap's edge, which is where `Door`'s hinge sits; the door is drawn from the opening's set; it starts shut, an interior one shut,
  ajar or open by `START_WEIGHTS`. `DoorFactory` spawns it under the house's `Doors` node; the house's `doors` metadata is
  `WorldGen.get_doors` and each opening's `door` flag is true where one stands (interface 1).
- **The swing arc** (a quarter disc the leaf's length from the hinge) lies inside the doorway's clearance box (as wide as the doorway,
  each side of the wall as deep as the open leaf reaches: `width - wall_thickness + 2`, never under `OPENING_CLEARANCE`;
  `HouseSpawner._opening_clearances`), which the furnisher and the dresser keep clear, so the doors add nothing to `blocked` and no plan
  is re-laid for them (`tests/worldgen/door_swing_and_hinge_test.gd`, which also keeps the whole box the open leaf reaches clear:
  change a door's length and it says whether the box still holds it).
- **The switch** `WorldGenDoorConfig.enabled` (the behaviour switch `worldgen.doors`, on by default) is guarded at the one spawn point,
  `HouseDoors.build`: off, the doorways stay open archways and nothing else of the house changes, a seed's furniture included
  (`tests/worldgen/door_placement_test.gd`). `WorldGenDoorConfig.start_open` (the switch `worldgen.doors_open`, off) makes `HouseDoors.roll`
  start every door fully open, the draws unchanged. Other tests: `door_rules_suite.gd`, `door_start_state_test.gd`, `door_start_open_option_test.gd` there.
