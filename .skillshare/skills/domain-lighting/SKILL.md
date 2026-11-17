---
name: domain-lighting
description: Use when editing scenes/lighting/, retuning the dusk, a fixture, a flash or the light budget, adding a light-giving piece, changing who shadows whom, or asserting on lights in a test.
---

# Lighting domain (`scenes/lighting/`)

The world's dusk lighting. The spec is `docs/lighting.md`: the 3D lighting, each behaviour with its tests
(`tests/lighting/light_3d_*`, through `tests/_lighting/lighting_3d_probe.gd` and the data reads of `lighting_probe.gd`). The numbers
live in the holders and the spec, not here. Interfaces: 10 (the `shot` / `explosion` topics), 20 (Main / Testing → Lighting; a piece's
`get_lights()`; the 3D lights), 27 (the 3D render).

A **near-leaf**: it imports General (`EventBus`, `WeightedPick`, `RenderConfig`), Art's `ToonLight` (the 3D dusk's shader globals) and
Godot, and reads the world duck-typed (`get_lights()`, the groups `floors` and `characters`). Its caller is Main (`main_view3d.gd`
`light_world` → `WorldLighting3D.light`); Testing's `lighting.enabled` switch and the probes read `lights()` / `fixtures()`. The
lights and shadows of the world's things are declared by their own domains.

## The 3D lighting (`world_lighting_3d.gd`, `WorldLighting3D`)

Built under the 3D view's world from the 2D world the sim runs in (group `world_lighting_3d`; `docs/lighting.md` "The 3D lighting").
A street floor says `is_street()`.

1. **Dusk.** `ToonLight.set_ambient(LightingConfig.ambient_color)` (the toon shaders add it to every pixel), one `DirectionalLight3D`
   (`sky_color`, `sky_energy`, from `sky_from` at `Lighting3DConfig.sun_elevation`, 76: short shadows, hard) and the sky mask: an `Image` of the
   street floors (white) less every house floor and its walls (black), so the sun lights the street and never a room.
2. **Lights.** An `OmniLight3D` per declared light and per room fixture (a room no `room_light` stands in): `_omni(colour, energy,
   pool, kind, room_code)`, `pool` the radius and the height (a declaration's `lift`, else its `kind`'s: `overhead` / `low` / `street`, `Lighting3DConfig`; a fixture's `LightingFixtureConfig.shadow_height_for` (400 to 600), so its shadow is short while the bulb hangs at the ceiling), `kind` giving the slope of the pool, `omni_range` the distance to the pool's rim (`radius * range_scale`), `omni_attenuation` 0. `light_specular`
   carries `slope`, the room and street flag, and the light's height over its rim and height class (`ToonLight.specular`; a pool is the same size at any height) to the toon light, which clips a pool to its room (the room map, `ToonLight.set_rooms`).
   No per-floor budget. Each `Lit` follows its piece (`follow`, only when the piece's transform changed; a freed piece's light is
   freed), steps its seeded rhythm (the energy written only on change, none while off) and tells `glow_changed` (Main dims the
   piece's mesh glow, `FurnitureRig.set_glow_level`).
3. **The cost** (`choose(snap)`, every `LightingCostConfig.refresh` s, when the `focus` moved `refocus` px or the zoom changed):
   the nearest `max_lights` pools (distance less radius) that reach the view are on, fading over `fade_time`; the nearest
   `shadow_lights` ceiling fixtures cast shadows (a piece's light never: its own body would shadow it), keeping a shadow within
   `1 / keep_margin` of the cutoff. No focus: all on, none cast.
4. **Flat.** `LightingConfig.enabled` off: no lights, a white ambient and a sun of energy 0.01 (the toon light needs one directional
   light to run its ambient).
5. **The globals** (`ToonLight`) belong to the last `WorldLighting3D` in the tree: the last to leave clears them.
6. **Flashes** (`flash_pool_3d.gd`, `docs/lighting.md` L9-3D): `_on_posted` lights a `shot` / `explosion` (kind `frag` or `stun`) from the
   2D `LightingConfig.flashes` rows as a pooled `Lighting3DConfig.flash_lights` `OmniLight3D` (a dark one, else the oldest), unshadowed and
   off the shadow cap, in the room it stands in (`_flash_code`: the street when in none), skipped when the view cannot reach it (a full pool
   gives the slot of the flash with the least left to run); `step` fades it (`hold`, then `energy x left^2` over `life`). It is coded in `light_specular`
   (kind 1 a tint, 2 a row's `wash`, an additive white-out) and the toon light adds it apart from its cap: no global is written. A flash outside the
   vision cone is dimmed by the vision mask (Art's `seen`), no code here.
7. **Fixture bulb:** each room fixture has an emissive sphere (`LightingFixtureConfig.bulb_*`) over the walls, dimming with its rhythm and fade; the
   fixture's shadow is part dark (`shadow_opacity`).

The toon light itself (the bands, the cap, why the ambient rides the one directional light) is Art's: `domain-art/textured-toon.md`.
**Adding a light-giving piece** is unchanged (below, Objects declares it); its 3D light follows from the declaration, its glow from
the mesh (`FurnitureRig.add_glow`). 

## The files

| File | Role |
|---|---|
| `world_lighting_3d.gd` (`WorldLighting3D`) | The game's lights (above). `light(view, world, seed_value, rooms, focus)` (a district's `rooms`: every tower's, keys unique) returns null while `enabled` is off. |
| `lighting_config.gd`, `lighting_3d_config.gd`, `lighting_cost_config.gd`, `lighting_fixture_config.gd` | Tuning holders: `LightingConfig` (switch, dusk colours, flash rows, `floor_reach`), `Lighting3DConfig` (the sun, heights, pools, the flash pool, the fixture shadow), `LightingCostConfig` (the caps), `LightingFixtureConfig` (the room fixtures and their bulb). |
| `flash_pool_3d.gd`, `light_rhythm.gd` | Private parts: the flash pool; one light's seeded rhythm. |

A kept light's rhythm is picked from the declaration's `rhythm` weights with an RNG seeded `hash([seed, piece position
(rounded), index])` (a fixture: `hash([seed, "fixture", room key])`), so the same seed flickers the same.

A rhythm still steps every frame and drives the light's energy, but an unchanged energy is not written again
(`rhythm_skips_unchanged_writes_test.gd`).

## The world's side (built by the owning domains)

- **Objects** (`domain-objects`): `object_lights.gd` works out a piece's `get_lights()` once in `_ready` from the painter, its
  options, size, facing and the rows of `ObjectArtLightConfig.specs`; the street's floors (`light_layer: "street"`) are lit by the
  street's lights only.
- **Shadows** are the real geometry of the 3D meshes (`docs/lighting.md` L6-3D); a character's is a drop-shadow patch
  (`CharacterShadowConfig`).

## Adding to it

- **A light-giving piece:** a row in `ObjectArtLightConfig.specs` and its case in `object_lights.gd` (`_kind`, or
  `ObjectArt.light_kind` for a painter that lights only in some variants; colour / turn / reach in `_by_kind`; the offset is
  the row's `ahead`). Its painter draws the source inside `canvas.glowing` so the mesh glows with it.
- **Who shadows whom:** the geometry of the meshes; which lights cast is `LightingCostConfig.shadow_lights`.
- **A flash:** a `LightingConfig.flashes` row (its `wash` for a white-out) and its topic in `_on_posted`. A flash that is the whole look of something (the
  stun's) takes a `hold` and a longer `life` rather than a drawn effect beside it.

## Gotchas

- Headless, the dummy renderer accepts every light: tests read node properties (energy, range, `light_specular`), and perf tests
  see only the CPU side. The GPU cost of shadows is measured by hand.
- A test that must have no lights turns `lighting.enabled` off, as does a sandbox that lights itself.
