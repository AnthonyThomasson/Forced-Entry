---
name: domain-lighting
description: Use when editing scenes/lighting/, retuning the dusk, a fixture, a flash or the light budget, adding a light-giving piece, changing who shadows whom, or asserting on lights in a test.
---

# Lighting domain (`scenes/lighting/`)

The world's dusk lighting. The spec is `docs/lighting.md` (L1 to L10, each with its tests, which are in `tests/lighting/` through
`tests/_lighting/lighting_probe.gd`); the numbers (ambient, sky, budget, flashes, fixtures) live in the holders and the spec, not
here. Interfaces: 10 (the `shot` / `explosion` topics), 11 (`LightMasks`, `DrawLayers.OVERHEAD`), 20 (Main / Testing → Lighting;
a piece's `get_lights()`; the occluders and light layers).

A **leaf**: it imports General (`EventBus`, `DrawLayers`, `LightMasks`, `WeightedPick`) and Godot, and reads the world
duck-typed (`get_lights()`, the groups `floors` and `characters`). Its one caller is the match builder (`MatchBuilder.stage` →
`WorldLighting.light`), for Main's match and the Testing world alike; Testing's `lighting.enabled` switch and the probe read
`lights()` / `fixtures()` / `flashes()` / `budget()`. The lights and shadows of the world's things are declared and built by
their own domains.

| File | Role |
|---|---|
| `world_lighting.gd` (`WorldLighting`) | The node, in the group `world_lighting`; `light(root, seed_value, rooms)` returns null while `enabled` is off; the build and the per-frame work. |
| `lighting_config.gd`, `lighting_fixture_config.gd`, `lighting_texture_config.gd` | Tuning holders: `LightingConfig` (switch, dusk, flash rows, budget, `body_clear`), `LightingFixtureConfig` (the room fixtures), `LightingTextureConfig` (pool textures per shape). |
| `flash_pool.gd`, `light_budget.gd`, `light_rhythm.gd`, `ceiling_fixture.gd` | Private parts: the flash pool and its fall-off and character clearing; the per-floor count; one light's seeded rhythm; the fixture's bulb glyph. |

General's `scenes/general/light_masks.gd` (`LightMasks`) holds the occluder bits, shadow masks and item layers, and
`occluder(polygon, bit)`: it winds the polygon clockwise on screen and culls counter-clockwise, the probed winding that keeps the
shape itself lit and darkens only what lies behind it.

## Build order (`_build`, once)

1. The ambient and the street's `Sky`. None on the house's items: the house has a roof (L1).
2. Every Objects floor (group `floors`) becomes a budget area, its `size` grown by `floor_reach`, its light layers the union of
   its canvas items' `light_mask`. One walk of the root's descendants collects the candidates (nodes with `get_lights()`); a
   `room_light` marks its room (by the piece's position) lit.
3. Fixtures for rooms no `room_light` marked, counted against the budget whatever (`always`).
4. Candidates **strongest declared energy first** (ties in walk order): placed when `take` says every floor the box reaches has
   room, else listed in `budget().dropped` and freed. `height` picks the shadow mask and texture (`overhead`: walls only, the
   downward pool; `low`: walls and tall pieces, the glow); a `street` light also takes the `STREET` layer.
5. A room whose room lights were all dropped gets its fixture if its floors have room.
6. The flash pool and the `EventBus` connection (dropped in `_exit_tree`).

A kept light's rhythm is picked from the declaration's `rhythm` weights with an RNG seeded `hash([seed, piece position
(rounded), index])` (a fixture: `hash([seed, "fixture", room key])`), so the same seed flickers the same.

## Each frame (`_process`), allocation-free

- A rhythm drives the light's energy and dims its `glow` (the piece's `Emissive` overlay or the fixture's glyph) with it.
- `flash_pool.gd`'s `clear_bodies`: a lit flash drops `CHARACTER` from its shadow mask while a living character's centre is
  within `radius × body_clear` of the flash's, and gets it back once none is. The character list is re-read from the group
  `characters` only when `get_node_count_in_group` changes; `shadow_item_cull_mask` is written only when it changes. A flash runs
  it at once when lit.
- Lights and occluders are children of their piece, so nothing is moved by hand.

## The world's side (built by the owning domains)

- **Objects** (`domain-objects`): `object_lights.gd` works out a piece's `get_lights()` once in `_ready` from the painter, its
  options, size, facing and the rows of `ObjectArtLightConfig.specs`; a solid piece builds its occluder (`EMITTER` when it
  gives light, else `TALL` from `LightMasks.TALL_COVERAGE`, else `FURNITURE`); a wall builds one per segment (`WALL`); the
  street's floors (`light_layer: "street"`) put themselves on `STREET`; every `Emissive` overlay draws unshaded.
- **A door** (Objects, interface 24, `docs/doors.md` DR5): an occluder over the leaf on `WALL` (it shadows every light), a child of the
  door's body so it turns with the leaf; none for the glass-panel door, freed when the door falls (`tests/objects/door_blocks_test.gd`,
  `door_contract_test.gd`, `door_knocked_down_test.gd` there).
- **Character** (`domain-character`): an oval occluder (`CharacterShadowConfig`) on `CHARACTER`, freed in `_die`.

## Adding to it

- **A light-giving piece:** a row in `ObjectArtLightConfig.specs` and its case in `object_lights.gd` (`_kind`, or
  `ObjectArt.light_kind` for a painter that lights only in some variants; colour / turn / reach in `_by_kind`; the offset is
  the row's `ahead`). Its painter draws the source inside `canvas.glowing` so the overlay shows it.
- **Who shadows whom:** the masks in `LightMasks` and the shadow mask each light is given here.
- **A flash:** a `LightingConfig.flashes` row and its topic in `_on_posted`. A flash that is the whole look of something (the
  stun's) takes a `hold` and a longer `life` rather than a drawn effect beside it.

## Gotchas

- **15 point lights per canvas item** (Godot 4.4): a new big batched layer must stay under a floor's count (split it per room,
  as the wear is) or draw on a layer the house's lights do not reach (as the street is).
- A DirectionalLight2D's shadows run to the edge of the view (`max_distance` is a camera cull distance, not a shadow length):
  hence no shadows on the sky.
- Headless, the dummy renderer accepts every light and occluder: tests read node properties (texture box, masks, energy), and
  perf tests see only the CPU side. The GPU cost of shadows is measured by hand (`docs/lighting.md`, "Measured cost").
- A test that must have no lights or occluders turns `lighting.enabled` off, as does a sandbox that lights itself.
