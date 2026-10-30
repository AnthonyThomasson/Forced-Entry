20. **Main / Testing (through `MatchBuilder`) → Lighting, and the world's lights and shadows** (`scenes/lighting/`; spec `docs/lighting.md`; Lighting is a
    leaf: it imports only General and reads the world duck-typed)
    - `WorldLighting.light(root: Node2D, seed_value: int, rooms: Array = []) -> WorldLighting` — lights the built world under `root`:
      adds one `WorldLighting` node under it, in the group `world_lighting` (`rooms` = `WorldGen.get_rooms`, for the fixtures;
      `seed_value` seeds the rhythms); null, building nothing, while `LightingConfig.enabled` is off. The match builder's `stage` (interface
      23) calls it after the nav bake with the spec's seed: Main's match with the house seed, the Testing world with its setup's. Its reads: `lights()` (every piece and fixture
      PointLight2D), `fixtures()` (`{ room, light }`), `flashes()` (the pooled flash lights) and `budget()` (`{ per_floor, dropped }`,
      `dropped` = `{ piece, index }` per declared light left without a light). `LightingConfig` (static holder): `enabled`, the dusk
      (`ambient_color`, `sky_color`, ...), the flashes and the budget (`per_floor()`); `LightingFixtureConfig` the room fixtures;
      `LightingTextureConfig` the light textures; the Testing domain's `lighting.enabled`
      switch sets `LightingConfig.enabled` and General's `LightMasks.shadows`.
    - **Objects → Lighting: `get_lights() -> Array`** on a light-giving piece (an EnvironmentObject; read duck-typed, like Audio
      reads a vehicle): one plain dict per light in the piece's frame, `offset` (Vector2), `turn` (rad, the pool's long axis),
      `colour`, `energy`, `radius` (px, along the long axis), `shape` (`round` / `wide` / `tube`), `rhythm` (`[[mode, weight],
      ...]`, modes `steady buzz failing blink shimmer pulse`), `room_light` (it lights its room: no fixture there), `street` (it
      lights the street too), `height` (`overhead`: above the heads, a lamp's bulb, a street lamp's head; `low`: a screen, a tube,
      LEDs; the Lighting domain picks the light's shadows and pool by it, `docs/lighting.md` L2 / L6) and `glow` (the piece's
      `Emissive` overlay, dimmed with the light; or null). The Lighting domain parents each light it keeps to the piece, so a
      shoved piece carries it.
    - **The shadows and light layers** (on General's `LightMasks`, interface 11): Objects' walls (one occluder per wall run,
      `WALL`) and solid pieces (their footprint, `EMITTER`, `TALL` or `FURNITURE`) and Character's living body (an oval turned
      with `facing`, `CHARACTER`, freed on death) build their own `LightOccluder2D` children with `LightMasks.occluder`, like
      their colliders; Objects' street floors (catalogue `light_layer: "street"`) put their canvas items on `LightMasks.STREET`;
      Objects' `Emissive` overlays draw unshaded. The Lighting domain reads the floors, found by the group `floors` every Objects `Floor` joins in
      its `_ready` (their `size` and the `light_mask` of their canvas items), for the per-floor budget, and each frame the characters in the group `characters` (`is_dead`,
      `radius`, interface 7) for whom stands in a flash.
    - **The flash events:** the `&"shot"` and `&"explosion"` topics (interface 10) light its flash pool.
