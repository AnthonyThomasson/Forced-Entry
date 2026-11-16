---
name: domain-art
description: Use when editing scenes/art/, writing or debugging a painter (furniture, walls, floors, characters, held items, vehicles), or tuning the shared pixel-art look.
---

# Art domain (`scenes/art/`)

A leaf: the procedural pixel-art engine. It knows nothing of furniture, characters or items; each domain owns its painters and
renders them through here. Depends only on Godot's `Image` (and, for the 3D mirror, General's `RenderConfig`). Interfaces: 12 (Objects / Character / Items / Vehicles → Art, the mesh kit too), 13
(a sandbox's own painter, as an assets ticket's showroom has) and 27 (the 3D mirror).

| File | Role |
|---|---|
| `pixel_art.gd` (`PixelArt`) | The cached renderer. |
| `pixel_canvas.gd` (`PixelCanvas`) | The drawing surface: RGBA image plus coverage and height layers; shading, finishes, `glowing`. |
| `pixel_shape.gd` (`PixelShape`), `pixel_convex_shape.gd` (`PixelConvexShape`) | The shapes a canvas fills. |
| `mirror/` (`WorldMirror`, `MirrorProxy`, `MirrorConfig`) | The 3D mirror of the 2D bodies (below). |
| `post/` (`PixelPostConfig`, `ToonMaterial`, `ToonMask`, `PixelPost`, `toon.gdshader`, `toon_tex.gdshader`, `decal.gdshader`, `outline.gdshader`, `*.gdshaderinc`) | The pixel post of the 3D render: the toon material (the one every mesh shares, with phase 3's vision-mask globals), the textured toon and the outline pass (below). |
| `mesh/` (`MeshKit`, `MeshCache`, `MeshNodes`, `MeshPool`, `MeshKitConfig`) | The mesh kit: code-built low-poly solids, the mesh cache, the node and decal helpers every domain's 3D meshes are built from (`meshes.md`). |
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
- `render_flat` — the painter's albedo for the 3D render: no light, canonical, one texture per piece (`flat-paint.md`).
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

## The 3D mirror (`mirror/`, interface 27)

In the 3D render mode (#193) the 2D world is not drawn: `WorldMirror` (a `Node3D`, `mirror(root)`) follows every `PhysicsBody2D` under `root` as
a proxy per collision shape (a box, a cylinder, a character's capsule; floors flat slabs) at 2D `(x, y)` -> 3D `(x * unit, 0, y * unit)`, the one scale
`RenderConfig.unit` (General). It reads bodies duck-typed (the groups `characters`, `vehicles`, `doors`, `floors`; `wall_thickness`, `art_color`, `color`,
`faction`), never a domain's class. The update rule is the spike's lesson: write only when the shape's 2D transform changed, skip a sleeping
`RigidBody2D` (read once more as it falls asleep), check a freed shape untyped (`is_instance_valid` on a Variant), add a spawned body or floor on the next
frame (its `_ready` builds its shapes first; a floor joins `floors` there), drop a despawned body's proxies. A shape added to or removed from a mirrored body
(a hit furniture piece's rebuilt collider) re-mirrors it, unless its mesh says `follows_shapes() -> true` (a wall's: it replaces the one segment that changed); a proxy (or an own mesh, when every shape of its body is) is hidden while its shape is disabled (a seated character) or its body's own `visible` is false; a mesh keeps itself in step by `mirror_update`, `remirror` and `on_body_died` (`mesh-hook.md`).
`builders` (hook key -> `Callable(node) -> Node3D` in 3D units: a kind, `FURNITURE` for every `ObjectArt` piece, or a finer key for one art id; `FLOOR` for the floors) is the hook a domain's own mesh plugs into
(`meshes.md`); `track(node, builder)` and `track_group(group, builder)` mirror a drawn thing that is no physics body (a dropped item, debris, a bullet) by the same rules;
`MirrorConfig` holds the proxy heights and colours. **Giving a domain's things a 3D mesh: `meshes.md`** (the kit, units, colours from the tones, cache keys, heights, where meshes live); the hook's keys and rules, and the vision-mask globals: `mesh-hook.md`.
Tests: `tests/art/mirror_follows_bodies_test.gd`, `mirror_follows_rebuilt_colliders_test.gd`, `mirror_hides_seated_character_test.gd`, `mirror_mesh_hook_test.gd`, `mirror_hook_keys_test.gd`, `mirror_mesh_lifecycle_test.gd`, `mesh_kit_suite.gd`, `mesh_cache_suite.gd`, `mesh_nodes_suite.gd`. Shaders compile only windowed, so a change to a shader needs one windowed run (`tools/run_tests.sh --windowed`).

## The pixel post (`post/`, interface 27)

The 3D picture is made to read as pixel art (#193 rule 6): drawn at a low internal resolution (a picture pixel is an art pixel, General's `RenderConfig.texel_match`) and shown with nearest
filtering, through two things Art owns, tuned in `PixelPostConfig` (ADR 0003). **`ToonMaterial.shared()`** (made by `make()`) is the one `ShaderMaterial` (`toon.gdshader`) every mesh of
the 3D view shares, a colour per instance (`base_color`, an instance uniform): the dusk's ambient plus each light's amount (N.L times its fall-off and shadow) stepped into `bands` bands (3), tinted
by the light and capped (`ToonLightConfig`, `ToonLight`; `textured-toon.md`). **`PixelPost.attach(camera, oversample)`** adds the
outline quad (`outline.gdshader`) under the view's camera: a dark line where the depth's second difference steps (a silhouette, `silhouette_px` wide) or the normal
creases (`crease_px`), so a floor seen at an angle stays clean. `turn_supersample` and `supersample` are both 1: 2 for the turn flickers more on textured art (averaging nearest-sampled art adds colours; `art/pixel_post_shimmer`), the mechanism (`View3D` renders larger and averages down while turning) stays. A face of a mesh-kit mesh carries its own colour in the vertex colour (`COLOR`, times the instance's `base_color`). Three **global shader uniforms** (`ToonMask`:
`vision_mask`, `vision_mask_xf`, `vision_unseen`; default "everything visible") are phase 3's vision-mask hook, read by `toon.gdshader`, `toon_tex.gdshader` and the kit's `decal.gdshader` (one `toon_common.gdshaderinc`: never restate `light()`), so the
vision job needs no per-mesh edit (`meshes.md`). Tests: `tests/art/mirror_proxies_use_toon_material_test.gd`, `tests/general/pixel_post_view_test.gd`; the look itself is only judged windowed
(`general/render_3d_match_windowed`, `art/pixel_post_shimmer`, `art/toon_vision_hook_windowed`, `art/toon_tex_windowed`).

The outline's colour is the surface's own darkened, not one near black: a silhouette takes the nearer side's colour (`outline_darken` 0.15 on the world, `figure_darken` 0.35 on a figure so an outfit reads at zoom 1), a crease its own pixel's; a mesh marked `MeshNodes.figure` (a character's parts: `figure`, an instance uniform the toon material writes as roughness into the normal buffer's alpha) gets the silhouette only, no creases (`figure_creases` brings them back), as a body's faceted limbs, a pixel or two wide, would crease at every facet. Test: `art/pixel_post_outline_windowed` (windowed, `OUTLINE_SHOTS=<dir>` saves the shots).

**The textured toon** (`MeshNodes.textured`, `toon_tex.gdshader`): the 2D art on a mesh; the rules are `textured-toon.md`.

## The wall fade (#193 rule 9, interface 27)

`WallFade` (`mirror/wall_fade.gd`, tuned in `WallFadeConfig`) thins the walls, doors and tall pieces between the camera and the player, or every character when spectating, so nobody is hidden; the rest stay whole. Rules, seams, tests and limits: `wall-fade.md`.

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
