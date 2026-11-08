---
name: domain-art
description: Use when editing scenes/art/, writing or debugging a painter (furniture, walls, floors, characters, held items, vehicles), or tuning the shared pixel-art look.
---

# Art domain (`scenes/art/`)

A leaf: the procedural pixel-art engine. It knows nothing of furniture, characters or items; each domain owns its painters and
renders them through here. Depends only on Godot's `Image`. Interfaces: 12 (Objects / Character / Items / Vehicles → Art) and 13
(a sandbox's own painter, as an assets ticket's showroom has).

| File | Role |
|---|---|
| `pixel_art.gd` (`PixelArt`) | The cached renderer. |
| `pixel_canvas.gd` (`PixelCanvas`) | The drawing surface: RGBA image plus coverage and height layers; shading, finishes, `glowing`. |
| `pixel_shape.gd` (`PixelShape`), `pixel_convex_shape.gd` (`PixelConvexShape`) | The shapes a canvas fills. |
| `art_canvas_config.gd`, `art_surface_config.gd` | Tuning: `ArtCanvasConfig` is what every painting shares (`pixel_size`, `light_from`, `turn_steps`, drop and cast shadow); `ArtSurfaceConfig` is how a surface is shaded (the `tones(base)` ramp, finish densities). A domain's own proportions and colours stay in its own config (`ObjectArt*Config`, `CharacterArtConfig`); a painter knob reads `opts.get(key, <DomainConfig>.<painter>_<key>)`. |

## Painters

A painter is a script with `static func paint(canvas, base, material, opts)`. It draws in a **canonical frame** (front toward +y,
width across the front) under `canvas.light`, the world light already turned into that frame, so its shading lands right once
the art is turned. Painters live in their own domain: Objects (`objects/art/`, `domain-objects`), Character
(`character/body/art/`), Items (`items/art/`, the gun and grenade painters share `weapon_art.gd`), Vehicles (`vehicle/art/`,
shared `vehicle_art.gd`, `domain-vehicle`).

## Rendering

Pick the entry point by how the thing turns:

- `render` — a cardinal `facing`: paints at `size / ArtCanvasConfig.pixel_size`, lit for that facing, then turns the image
  (furniture, walls, floor tiles). The surface finish rides in `opts.material`, handed to the painter as `material`.
- `render_turned` — the image stays canonical and is lit as if turned by `angle`; the caller draws it rotated (characters,
  hands, guns, vehicle bodies, doors, wheels, lamps). Callers pass `snap_angle(angle)` (one of `ArtCanvasConfig.turn_steps`) and
  rotate to the exact angle when drawing: few cached textures, smooth turning, world-consistent light.
- `emissive` — the twin of `render`'s texture holding only what the painter drew `glowing`; null when nothing glows. Kept from
  the same paint, so it costs no second paint; `render_turned` keeps none.

Invariants:

- The cache is static (survives scene reloads), keyed by painter path + inputs + orientation. A piece's random detail is seeded
  by its inputs *without* orientation, so it does not change as the piece turns. `warm(requests)` paints complete `render` requests
  on one worker under the cache mutex (concurrent painter scripts are not safe); `finish_warming` waits and creates their textures
  on the main thread. A `render` never waits for the warm: it files the image the worker has painted for its key, else paints synchronously (the worker skips a cached key). Main starts the
  district warm through `WorldGen.prewarm`; headless skips it. Pixel equivalence: `prewarm_paints_shared_textures_test.gd`.
- A painter's big look (a character style, a gun's `looks` row) travels in `opts.look` as the int from `handle(look)`, never as
  a dict: the caches key by the options. `look_of(opts)` reads it back. Character and Items painters use it.
- `render_turned` sits behind a bounded memo (`_turned_memo`, `TURNED_MEMO_MAX`) keyed by exact arguments, because a character
  repaints every part every frame; values the string key treats as equal still share one texture
  (`tests/art/pixel_art_turned_cache_test.gd`).
- `PixelArt.TurnedLast` is a caller's slot for one part (`slot.render(painter, size, color, angle, opts)` = `render_turned`, answered by a compare against the last call's values; `PixelArt.last_hits` counts the answers). The character body keeps one per part (Character domain: `domain-character`, draw caches).
- `away_from_light(node)` gives the direction a drop shadow falls; every visual offsets its shadow by it.

## PixelCanvas gotchas

- A mask `PixelShape` (`bowed`) tests every pixel of its bounds and keeps a per-pixel mask, depth and normal; a
  `PixelConvexShape` (`rounded`, `ellipse`, `disc`) keeps one span per row and column, so fill, bevel and outline cost its edge.
  Prefer convex. A shape convex along both axes but neither a rounded rect nor an ellipse is built with `PixelConvexShape.new`
  (`vehicle_art.convex` does, once per geometry). `edge_pixels(k)` is pinned to the plain scan by
  `tests/art/shape_edges_match_plain_scan_test.gd`.
- `cast_shadows()` walks the whole canvas: a large canvas painted for every lighting step (a vehicle body) skips it and shades
  with bevels.
- `glowing(draw, area)` marks every pixel `draw` changed within `area` as emissive, comparing the image before and after. Pass a
  small `area` for a small drawing on a big canvas. Pinned by `tests/art/glowing_marks_changed_pixels_test.gd`.
- Read pixels in bulk through `coverage()` (a snapshot), not one `covered(x, y)` per pixel.
- `PixelShape.line_points` is the one line walk, also for a painter that blends or clips each point itself
  (Objects' `decay.gd`).
- `ArtSurfaceConfig.jitter(rng, col, k)` takes the canvas's `rng`, so a plank's or tile's own tone stays seeded.

Tests: `tests/art/`.
