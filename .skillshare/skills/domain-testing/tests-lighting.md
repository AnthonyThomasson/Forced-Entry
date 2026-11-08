# Lighting tests (domain `lighting`, `tests/lighting/`)

The rules are `docs/lighting.md` (L1 to L10, each with its tests named under it); `tools/run_tests.sh --domain=lighting` runs
them. The helper is `tests/_lighting/lighting_probe.gd` (`const Probe`; not a test): the plan's numbers as consts
(`AMBIENT`, `ITEM_LIGHTS`, `PER_FLOOR`, `FLASH_NEAR`, the pool profile and smoothness bounds), the test world's
`WorldLighting` (`lighting`, `require_lighting`: the one in the group `world_lighting`), the light-giving kinds told apart
by the pieces' public fields (`light_kind`), a piece's `declared` lights / `lights_of` / `dropped_of`, a light's pool
profile (`profile`, `largest_step`), the floors and what reaches them (`floors`, `floor_mask`, `light_box`, `reaches`) and
the occluders (`casting`, `holds`, `occluders_at`, `own_occluders`). Everything else is read off plain Godot nodes
(LightOccluder2D, PointLight2D, CanvasModulate, DirectionalLight2D, the overlays' `material`).

`rhythms_seeded_per_piece` builds its room twice, each in a `SubViewport` with a World2D of its own, and lights each with
`WorldLighting.light(root, seed)` itself.
