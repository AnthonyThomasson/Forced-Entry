## Lighting tests (domain `lighting`, `tests/lighting/`)

The rules are `docs/lighting.md` (L1 to L10, each with its tests named under it); `tools/run_tests.sh --domain=lighting` runs the
eleven (`lighting/stun_flash_light` reads the stun's held-then-faded flash off `flashes()` each frame). The shared helper is `tests/_lighting/lighting_probe.gd` (`const Probe := preload(...)`; not a test): the plan's numbers as
consts (`AMBIENT`, `ITEM_LIGHTS` 15, `PER_FLOOR` 12, `FLASH_NEAR`, the pool profile bounds `OVERHEAD_HALF_MIN` / `LOW_HALF_MAX`,
the smoothness bound `SMOOTH_SAMPLES` / `SMOOTH_STEP_MAX` and the street pool's `STREET_POOL_MAX` / `STREET_POOL_CENTRE`), the test
world's `WorldLighting` (`lighting`, `require_lighting`: the one in the group `world_lighting`, with its four reads), the light-giving kinds told apart by the pieces' public fields (`light_kind`), a
piece's `declared` lights / `lights_of` / `dropped_of`, a light's pool profile (`profile`: its gradient at a share of its radius;
`largest_step`: its biggest jump), the floors and what reaches them (`floors`, `floor_mask`, `light_box`: a light's texture box,
`reaches`), and the occluders (`casting`, `holds`, `occluders_at`, `own_occluders`). Everything else is read off plain Godot nodes
(LightOccluder2D, PointLight2D, CanvasModulate, DirectionalLight2D, the overlays' `material`). `rhythms_seeded_per_piece` builds
its room twice, each in a `SubViewport` with a World2D of its own, and lights each with `WorldLighting.light(root, seed)` itself.
