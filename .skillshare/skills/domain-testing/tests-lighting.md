# Lighting tests (domain `lighting`, `tests/lighting/`)

The rules are `docs/lighting.md` (each behaviour with its tests named under it); `tools/run_tests.sh --domain=lighting` runs
them. The helpers are `tests/_lighting/lighting_3d_probe.gd` (`const Probe`; not a test): `light(t, rooms, focus, view_px)` builds the
3D lighting of the test's 2D world into a 3D viewport of its own and returns the `WorldLighting3D`, whose `lights()`, `fixtures()`,
`sun()`, `flashes()`, `shadowed_count()`, `on_count()` and `choose(snap)` the tests read; and `tests/_lighting/lighting_probe.gd`,
the data reads: the `pieces` of a world, what each `declared` (its `get_lights()`), the `floors` and their `floor_rect`.

A test that compares two lightings builds each in a viewport of its own (`Probe.light` twice), as `light_3d_follows_and_flickers`
does for the seeded rhythms.
