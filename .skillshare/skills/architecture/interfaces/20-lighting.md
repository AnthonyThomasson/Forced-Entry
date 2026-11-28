20. **Main / Testing (through `MatchBuilder`) → Lighting, and the world's lights and shadows** (`scenes/lighting/`; spec `docs/lighting.md`;
    Lighting imports only General and Art's `ToonLight` (the dusk's shader globals) and `MeshNodes`
    (`instance` and `glow` for a fixture's bulb, `changed`: 12) and reads the world duck-typed)
    - **The 3D render's lights** (the lights of the game): `WorldLighting3D.light(parent: Node, world: Node2D, seed_value: int, rooms: Array = [], focus := Callable()) -> WorldLighting3D`
      builds the dusk under `parent` (a node of the 3D view's world, 27): the toon ambient (`ToonLight`), a `DirectionalLight3D` sky that reaches only the street's floors (an Objects `Floor`'s `is_street()` and `size`, read duck-typed: no 2D light layer), an `OmniLight3D` per light a piece declares
      (`get_lights()`, below) and per room fixture, each clipped to its room (the room map, `rooms` = `WorldGen.get_rooms` / `district_rooms`; none: no clipping), and a cost cap chosen from `focus` (`Callable() -> Vector2`, the view's centre in px: at most
      `LightingCostConfig.max_lights` on, fading, `shadow_lights` ceiling fixtures shadowed; none: all on, none shadowed). No per-floor budget. Main builds it (`main_view3d.gd` `light_world`, after the mirror, with the match handle's `site_rooms`) and
      connects its `glow_changed(piece, level)` to the piece's mesh `set_glow_level` (Objects' `FurnitureRig`, a duck-typed call). Reads for tests (`tests/_lighting/lighting_3d_probe.gd`): `lights()` (`OmniLight3D`s, metas `piece`, `index`, `room`,
      `shadowable`), `fixtures()`, `sun()`, `flashes()` (the pooled flash `OmniLight3D`s), `flash_count()`, `shadowed_count()`, `on_count()`, `in_view_count()`, `choose(snap)`. With `LightingConfig.enabled` off it builds no light and lights the art flat.
    - **Tuning holders:** `LightingConfig` (`enabled`, the dusk `ambient_color` / `sky_color`, the flashes),
      `LightingFixtureConfig` (room fixtures, their shadow height and darkness), `Lighting3DConfig` (the 3D sun's elevation and shadow, the lights' heights, and pools),
      `LightingCostConfig` (the 3D lights' shadow and on caps, the fade). The Testing switch `lighting.enabled` sets
      `LightingConfig.enabled`.
    - **Objects → Lighting: `get_lights() -> Array`** on a light-giving piece (an `EnvironmentObject`, read duck-typed): one dict per
      light in the piece's frame: `offset` (Vector2), `turn` (rad, the pool's long axis), `colour`, `energy`, `radius` (px, along the long
      axis), `shape` (`round` / `wide` / `tube`), `rhythm` (`[[mode, weight], ...]`, modes `steady buzz failing blink shimmer pulse`),
      `room_light` (it lights its room: no fixture there), `street` (it lights the street too), `height` (`overhead`: a lamp's bulb, a
      street lamp's head; `low`: a screen, a tube, LEDs; Lighting picks the light's shadows and pool by it, `docs/lighting.md` L2 / L6), `lift` (px above the floor where the glowing part is: the 3D light hangs there, else at its `height` kind's; `rides` true: over the piece's own twin base instead, a monitor item's, so it comes down with the item) and
      Lighting keeps each light at the piece, so a shoved piece carries it; the piece's mesh glows with it.
    - **Shadows and light layers:** shadows are the real geometry of the 3D meshes; Objects' street floors (catalogue `light_layer: "street"`, a district's cut to `WorldGenDistrictConfig.tile_max` on a side) are lit by the street's lights only. Lighting reads the floors (group `floors`, joined by every Objects `Floor` in `_ready`: their `size` and `is_street()`), and each frame the group `characters` (`is_dead`, `radius`, 7). A character has a drop-shadow patch, and its parts cast no light shadow.
    - **The sun's casters** (`sun_casters.gd`, private): Lighting owns the render `layers` of the meshes in the sun's world, moving what cannot shadow
      the street to `LightingCostConfig.sun_indoor_layer`, which the sun's `shadow_caster_mask` leaves out, telling Art of each write
      (`MeshNodes.changed(mesh)`: a merged chunk lets go of it, `domain-art/still-merge.md`). So no other domain writes a mesh's `layers`
      or narrows a camera's or light's `cull_mask`. A mesh under a `StaticBody3D`, an `AnimatableBody3D`, a sleeping `RigidBody3D` or an ancestor with
      `proxies_of` (the carrier, 27) may be left out; under anything else it casts.
    - **Flashes:** the `&"shot"` and `&"explosion"` topics (10) light its flash pool (the 3D one, `WorldLighting3D`'s: `Lighting3DConfig.flash_lights` pooled `OmniLight3D`s, unshadowed, in the room the event is in, `docs/lighting.md` L9-3D; a flash is coded in its `light_specular` for the toon light, a row's `wash` a white-out).
