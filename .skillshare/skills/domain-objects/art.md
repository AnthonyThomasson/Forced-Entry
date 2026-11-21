# Objects pixel art (`scenes/objects/art/`, private to Objects)

Every catalogue piece, wall and floor is drawn as procedural top-down pixel art through the Art domain (`domain-art`, interface
12). A definition that sets `art` (a painter id) draws as art; one without it keeps the flat shape with its name label. Painters
are `*_painter.gd` files, each `static paint(canvas, base, material, opts)`; `ObjectArt.PAINTERS` maps each `art` id to its
painter (the id list lives there). A painter serving several pieces reads `kind` (and `part`, `v`) from `opts`.

## `object_art.gd` (`ObjectArt`), the registry

`flat` / `flat_facing` render through `PixelArt.render_flat` (canonical; the finish rides in `opts.material`, as `tile_flat`'s
`material` argument; `flat_facing` for a decal that lies facing a way); `tile_flat` renders at the painter's own `tile_size(opts)` (floors); `flat_request` / `tile_flat_request` (the pre-warm); `groove` / `porous` (a
tiling painter's blood grooves and soak); `light_kind` (which variant of a painter gives light: the one rule `ObjectLights` and
`neon_for` read); `neon_for`; `drawn_color`. `BY_KIND` lists the painters whose neon share is the kind's, not the painter's.

## The look: run-down, rust and grime, with a share of neon

One look for every piece.

- **The palette grade** (`decay.gd` `grade`, `ObjectArtDecayConfig.grade_*`): `ObjectArt.flat` / `tile_flat` wash every painter's
  colour toward dun, rust and nicotine yellow, so World-Gen's catalogue keeps plain colours and the house still draws run down. `ObjectArt.AS_GIVEN` painters (`wear`, `street`, `decor` and the district's `awning`, `stencil`, `crossing`, `road_glyph`, `podium`,
  `shell_decor`) take their colours as given. A piece's and
  wall's `get_surface().color` (debris) is the drawn colour (`ObjectArt.drawn_color`).
- **The finish** (`decay.gd`): each painter draws its shape, then its finish through the shared helpers (grime, stains, tears,
  rust, stickers, cracks, screens). Several painters share one: `SofaPainter.upholstery` (also the office chair),
  `ChairPainter.worn_wood` (also the table), `CabinetPainter.casegoods` (also the shelf), `ToiletPainter.porcelain` (also the
  bath). Some pieces are rebuilt rather than aged (the bed is a bare mattress, the lamp a tin shade over a bare bulb, a TV a boxy
  CRT).
- **The neon share** (`ObjectArt.neon_for`, `ObjectArtLightConfig.neon_share`): `ObjectFactory` gives a share of the
  light-giving pieces a `neon` option (`cyan` / `magenta`), picked per piece from where it stands (deterministic; `opts.neon`
  overrides): a trim, under-glow, ring tube or screen. Only three looks per piece, so the texture cache stays small. The ring
  (`decay.gd` `neon_ring`) reads the canvas's `coverage()` bytes, pinned to the plain scan by
  `tests/objects/neon_ring_matches_plain_scan_test.gd`.
- **No light is baked in** (no glow pools, sheen, halos): what gives light is drawn bright inside `canvas.glowing(draw, area)`
  (interface 12): a bare bulb, a CRT's screen, a monitor item's lit edge, a display, every neon trim. The piece's 3D mesh
  then shows those pixels as an emissive part (`SKILL.md`, "Lights").

## Painter conventions

- Each knob reads `opts.get(key, ObjectArt<Topic>Config.<painter>_<key>)` (the floor, wall, street and wear knobs without the
  painter prefix: `ObjectArtFloorConfig.<key>`), so a catalogue `art_opts` picks a variant or overrides one piece.
- Round footprints keep their art inside the inscribed circle.
- A top paints no loose things (`docs/stacked-items.md` SI13): a desk's monitor and mug, a counter's board are items (`item_home_painter.gd`,
  a row's `carries`, `RoomItems.carry`). `table` / `counter` take no `props`; `props.gd` stays for the cabinet's plates, the tech desk and
  `Props.pick`; colours in `ObjectArtDecorConfig.prop_colors`.
- `wear` draws one world-placed mark a canvas (the floor's, wall's and street's marks, `SKILL.md`, "Wear").
- `car_painter.gd` is the garage's parked car: static furniture, unrelated to the Vehicles domain's drivable car.

## Tuning holders (`object_art_*_config.gd`, one `class_name` static holder per topic)

`ObjectArtTableConfig` (tables, chairs), `ObjectArtFabricConfig` (sofa, bed, rug), `ObjectArtStorageConfig` (cabinet, shelf),
`ObjectArtKitchenBathConfig`, `ObjectArtDecorConfig` (plant, lamp, mirror frame, the prop palette), `ObjectArtOutdoorConfig` (the
beater car, the street lamp), `ObjectArtClinicConfig`, `ObjectArtTechConfig`, `ObjectArtLightConfig` (the light `specs`, the
screens' glow, the neon pair and share), `ObjectArtFloorConfig` and
`ObjectArtWallConfig` (the tiles), `ObjectArtDecayConfig` (grade and grime), `ObjectArtWearConfig`, `ObjectArtStreetConfig`, and the district's (below). The
shared light and shadows are `ArtCanvasConfig`, the tones and finishes `ArtSurfaceConfig`.

Key naming (ADR 0003, `docs/adr/0003-config-holders-split-by-topic.md`): a holder of one painter or module drops its topic word
(`ObjectArtFloorConfig.plank_px`, `ObjectArtWallConfig.pattern`, `ObjectArtLightConfig.specs`); a holder serving several painters
keeps each painter's name as its key prefix (`ObjectArtTableConfig.table_plank_px` beside `chair_slats`, `ObjectArtClinicConfig.clinic_*`,
`ObjectArtTechConfig.tech_*`); a module that is no painter keeps its own name (`ObjectArtLightConfig.decay_screen_color`); a key
several painters share is named for what it is (`ObjectArtDecorConfig.prop_colors`, `ObjectArtLightConfig.neon_*`). The colour
knobs hold the grimy values.

## The district's painters

The tower's and the district's pieces, in the grimy steel family, each `kind` a variant of one painter (`ObjectArt.PAINTERS`):

| Painter | Kinds | Knobs |
|---|---|---|
| `shop`, `noodle`, `stock` | counter, aisle, fridge, snack; bar, stool, booth, menu; crates, pallet, safe | `ObjectArtShopConfig` (`shop_*`, `noodle_*`, `stock_*`) |
| `awning` | `awning` (striped cloth, neon edge), `hanging` (vertical glyph sign): only as an `overhang` | `ObjectArtAwningConfig` |
| `street_prop` | vending, bench, bin, grate, litter | `ObjectArtStreetPropConfig` |
| `podium` | a concrete band segment with pillars | `ObjectArtPodiumConfig` (`podium_*`) |
| `shell_decor` | rebar, rubble, scaffold, cement, stain | `ObjectArtShellDecorConfig` |
| `stencil` | the floor text in a hazard border (`DecalFactory`) | `ObjectArtStencilConfig` |
| `crossing`, `road_glyph` | a junction arm's zebra and stop line; a lane number and arrow (`street_marks.gd`) | `ObjectArtCrossingConfig`, `ObjectArtRoadGlyphConfig` |

`glyphs.gd` is their pixel font (5 x 7 capitals and digits, a few brush-stroke characters) for the menu board, the sign and the
stencil; `paint_kit.gd` their shared fills, frames and paint wear. The fridge and the menu board give light (`light_kind` rows `fridge`
and `menu_board` in `ObjectArtLightConfig.specs`).

## Adding a painter

Write `<name>_painter.gd` (its shape, then its run-down finish from `decay.gd`, anything that gives light inside `canvas.glowing`),
register it in `ObjectArt.PAINTERS`, add its knobs to the `ObjectArt*Config` of its topic (or a new holder), set `"art": "<name>"`
on the catalogue definitions, and for a light-giving painter add its `ObjectArtLightConfig.specs` row (`domain-lighting`).

## The 3D meshes (`object_meshes.gd`, `table_mesh.gd`, `object_mesh_config.gd`)

In the 3D render a piece is shown by a mesh built from Art's mesh kit (`domain-art/meshes.md`) beside its painter: `ObjectMeshes.BUILDERS` maps an `ObjectArt` id to
`<name>_mesh.gd` (`static build(piece) -> Node3D`, 3D units, centred), and `ObjectMeshes.register(builders)` plugs them into the carrier under
`MeshKinds.furniture_key(art)` (Main's 3D view calls it). A piece whose art has no mesh has none. `ObjectMeshConfig` holds the heights (px): the table's
`table_*` (30 tall, 22 for a small footprint, `art_opts.height` wins); a table is built like every furniture mesh, through `FurnitureSpec` and `FurnitureRig` (`table_mesh_test.gd`); the domestic kinds: `meshes.md`.

Walls, doors, floors, street meshes: `structure-meshes.md`.
