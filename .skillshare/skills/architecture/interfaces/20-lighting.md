20. **Main / Testing (through `MatchBuilder`) → Lighting, and the world's lights and shadows** (`scenes/lighting/`; spec `docs/lighting.md`;
    Lighting imports only General and Art's `ToonLight` (the dusk's shader globals) and reads the world duck-typed)
    - **The 3D render's lights** (the lights of the game): `WorldLighting3D.light(parent: Node, world: Node2D, seed_value: int, rooms: Array = [], focus := Callable()) -> WorldLighting3D`
      builds the dusk under `parent` (a node of the 3D view's world, 27): the toon ambient (`ToonLight`), a `DirectionalLight3D` sky that reaches only the street's floors, an `OmniLight3D` per light a piece declares
      (`get_lights()`, below) and per room fixture, within the 2D per-floor budget and a cost cap chosen from `focus` (`Callable() -> Vector2`, the view's centre in px: at most
      `LightingCostConfig.max_lights` on, `shadow_lights` shadowed; none: all on, none shadowed). Main builds it (`main_view3d.gd` `light_world`, after the mirror, with the match handle's `site_rooms`: `WorldGen.get_rooms`, or `district_rooms`) and
      connects its `glow_changed(piece, level)` to the piece's mesh `set_glow_level` (Objects' `FurnitureRig`, a duck-typed call). Reads for tests (`tests/_lighting/lighting_3d_probe.gd`): `lights()` (`OmniLight3D`s, metas `piece` and
      `index`), `fixtures()`, `sun()`, `budget()`, `shadowed_count()`, `on_count()`, `choose()`. With `LightingConfig.enabled` off it builds no light and lights the art flat. The match builder builds no 2D lights for a 3D match.
    - `WorldLighting.light(root: Node2D, seed_value: int, rooms: Array = []) -> WorldLighting` lights the built 2D world under `root` (2D render only, until it is removed; the match builder does not call it for a match in the 3D render mode, `render` of the spec, 23, 27): adds one
      `WorldLighting` node (group `world_lighting`) and returns it; `rooms` = `WorldGen.get_rooms`, or `WorldGen.district_rooms` for a district (every tower's rooms, keys unique, so each gets a fixture or a
      piece's light; a shell is no room and gets none), for the fixtures; `seed_value` seeds the
      rhythms. It builds nothing and returns null while `LightingConfig.enabled` is off. The match builder's `stage` (23) calls it after the
      nav bake with the spec's seed (Main: the house seed; Testing: its setup's). Test reads `WorldLighting`'s (helpers in `tests/_lighting/lighting_probe.gd`):
      `lights()` (every piece and fixture `PointLight2D`), `fixtures()` (`{ room, light }`), `flashes()` (the pooled flash lights) and
      `budget()` (`{ per_floor, dropped }`, `dropped` = `{ piece, index }` per declared light left without a light).
    - **Tuning holders:** `LightingConfig` (`enabled`, the dusk `ambient_color` / `sky_color`, the flashes, the budget `per_floor()`),
      `LightingFixtureConfig` (room fixtures), `LightingTextureConfig` (2D light textures), `Lighting3DConfig` (the 3D sun's elevation and shadow, the lights' heights and pools),
      `LightingCostConfig` (the 3D lights' shadow and on caps). The Testing switch `lighting.enabled` sets
      `LightingConfig.enabled` and General's `LightMasks.shadows`.
    - **Objects → Lighting: `get_lights() -> Array`** on a light-giving piece (an `EnvironmentObject`, read duck-typed): one dict per
      light in the piece's frame: `offset` (Vector2), `turn` (rad, the pool's long axis), `colour`, `energy`, `radius` (px, along the long
      axis), `shape` (`round` / `wide` / `tube`), `rhythm` (`[[mode, weight], ...]`, modes `steady buzz failing blink shimmer pulse`),
      `room_light` (it lights its room: no fixture there), `street` (it lights the street too), `height` (`overhead`: a lamp's bulb, a
      street lamp's head; `low`: a screen, a tube, LEDs; Lighting picks the light's shadows and pool by it, `docs/lighting.md` L2 / L6) and
      `glow` (the piece's `Emissive` overlay, dimmed with the light, or null). Lighting parents each light it keeps to the piece, so a
      shoved piece carries it.
    - **Shadows and light layers** (General's `LightMasks`, 11): Objects' walls (one occluder per wall run, `WALL`) and solid pieces (their
      footprint: `EMITTER`, `TALL` or `FURNITURE`) and Character's living body (an oval turned with `facing`, `CHARACTER`, freed on death)
      build their own `LightOccluder2D` children with `LightMasks.occluder`, like their colliders. A `Door` (24) builds one over its leaf on `WALL`
      as a child of its body, so it turns with the leaf: none for the glass-panel door, freed when the door falls. Objects' street floors (catalogue `light_layer: "street"`, a district's cut to `WorldGenDistrictConfig.tile_max` on a side so a block's lamps stay within the budget) and the tower shadows (`DecalFactory.shadow`, 2) put their canvas items on `LightMasks.STREET`; `Emissive` overlays draw unshaded. Lighting reads the
      floors (group `floors`, joined by every Objects `Floor` in `_ready`: their `size` and their items' `light_mask`) for the per-floor
      budget, and each frame the group `characters` (`is_dead`, `radius`, 7) for who stands in a flash.
    - **Flashes:** the `&"shot"` and `&"explosion"` topics (10) light its flash pool.
