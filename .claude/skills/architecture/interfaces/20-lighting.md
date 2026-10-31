20. **Main / Testing (through `MatchBuilder`) → Lighting, and the world's lights and shadows** (`scenes/lighting/`; spec `docs/lighting.md`;
    Lighting is a leaf: it imports only General and reads the world duck-typed)
    - `WorldLighting.light(root: Node2D, seed_value: int, rooms: Array = []) -> WorldLighting` lights the built world under `root`: adds one
      `WorldLighting` node (group `world_lighting`) and returns it; `rooms` = `WorldGen.get_rooms`, for the fixtures; `seed_value` seeds the
      rhythms. It builds nothing and returns null while `LightingConfig.enabled` is off. The match builder's `stage` (23) calls it after the
      nav bake with the spec's seed (Main: the house seed; Testing: its setup's). Test reads, through `tests/_lighting/lighting_probe.gd`:
      `lights()` (every piece and fixture `PointLight2D`), `fixtures()` (`{ room, light }`), `flashes()` (the pooled flash lights) and
      `budget()` (`{ per_floor, dropped }`, `dropped` = `{ piece, index }` per declared light left without a light).
    - **Tuning holders:** `LightingConfig` (`enabled`, the dusk `ambient_color` / `sky_color`, the flashes, the budget `per_floor()`),
      `LightingFixtureConfig` (room fixtures), `LightingTextureConfig` (light textures). The Testing switch `lighting.enabled` sets
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
      build their own `LightOccluder2D` children with `LightMasks.occluder`, like their colliders. Objects' street floors (catalogue
      `light_layer: "street"`) put their canvas items on `LightMasks.STREET`; `Emissive` overlays draw unshaded. Lighting reads the
      floors (group `floors`, joined by every Objects `Floor` in `_ready`: their `size` and their items' `light_mask`) for the per-floor
      budget, and each frame the group `characters` (`is_dead`, `radius`, 7) for who stands in a flash.
    - **Flashes:** the `&"shot"` and `&"explosion"` topics (10) light its flash pool.
