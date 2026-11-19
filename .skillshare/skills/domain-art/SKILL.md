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
| `art_canvas_config.gd`, `art_surface_config.gd` | Tuning: `ArtCanvasConfig` is what every painting shares (`pixel_size`, `light_from`, the drop shadow's alpha and the cast shadow); `ArtSurfaceConfig` is how a surface is shaded (the `tones(base)` ramp, finish densities). A domain's own proportions and colours stay in its own config (`ObjectArt*Config`, `CharacterArtConfig`); a painter knob reads `opts.get(key, <DomainConfig>.<painter>_<key>)`. |

## Painters

A painter is a script with `static func paint(canvas, base, material, opts)`. It draws in a **canonical frame** (front toward +y,
width across the front) on a canvas with no light (`canvas.light` is `Vector2.ZERO`: the 3D lights shade the mesh). Painters live in their own domain: Objects (`objects/art/`, `domain-objects`), Character
(`character/body/art/`), Items (`items/art/`, the gun and grenade painters share `weapon_art.gd`), Vehicles (`vehicle/art/`,
shared `vehicle_art.gd`, `domain-vehicle`).

## Rendering

- `render_flat` — the painter's albedo for the 3D render: no light, canonical, one texture per piece (`flat-paint.md`); a decal
  passes the `facing` it lies at and gets the picture turned in quarter turns. The surface finish rides in `opts.material`,
  handed to the painter as `material`.
- `emissive_flat` — the twin of `render_flat`'s texture holding only what the painter drew `glowing`; null when nothing glows.
  Kept from the same paint, so it costs no second paint.

Invariants:

- The cache is static (survives scene reloads), keyed by painter path + inputs + orientation. A piece's random detail is seeded
  by its inputs *without* orientation, so it does not change as the piece turns. `warm(requests)` paints complete flat requests
  on one worker under the cache mutex (concurrent painter scripts are not safe); `finish_warming` waits and creates their textures
  on the main thread. A `render_flat` never waits for the warm: it files the image the worker has painted for its key, else paints synchronously (the worker skips a cached key). Main starts the
  district warm through `WorldGen.prewarm`; headless skips it. Pixel equivalence: `prewarm_paints_shared_textures_test.gd`.
- A painter's big look (a character style, a gun's `looks` row) travels in `opts.look` as the int from `handle(look)`, never as
  a dict: the caches key by the options. `look_of(opts)` reads it back. Character and Items painters use it.

## The 3D mirror (`mirror/`, interface 27)

In the 3D render (#193, the only render) the 2D world is not drawn: `WorldMirror` (a `Node3D`, `mirror(root)`) follows every `PhysicsBody2D` under `root` as
a proxy per collision shape (a box, a cylinder, a character's capsule; floors flat slabs) at 2D `(x, y)` -> 3D `(x * unit, 0, y * unit)`, the one scale
`RenderConfig.unit` (General). It reads bodies duck-typed (the groups `characters`, `vehicles`, `doors`, `floors`; `wall_thickness`, `art_color`, `color`,
`faction`), never a domain's class. The update rule is the spike's lesson: write only when the shape's 2D transform changed, skip a sleeping
`RigidBody2D` (read once more as it falls asleep), check a freed shape untyped (`is_instance_valid` on a Variant), add a spawned body or floor on the next
frame (its `_ready` builds its shapes first; a floor joins `floors` there), drop a despawned body's proxies. A shape added to or removed from a mirrored body
(a hit furniture piece's rebuilt collider) re-mirrors it, unless its mesh says `follows_shapes() -> true` (a wall's: it replaces the one segment that changed); a proxy (or an own mesh, when every shape of its body is) is hidden while its shape is disabled (a seated character) or its body's own `visible` is false; a mesh keeps itself in step by `mirror_update`, `remirror` and `on_body_died` (`mesh-hook.md`).
A body whose twin is a static body (a wall, a floor, an anchored or wall-hung piece) has its mesh carried by the twin (`_try_carry`: a child of it, no transform of its own, `mesh_of(body)`; the mirror waits for a twin that is still to come, `TwinSpace.is_waiting`; `MirrorConfig.carry_meshes` off follows it as before); the rules below still run on it. A body on `ViewLayers.MOVING` is hidden while the cone does not reach it (`MirrorVisionConfig`, `vision-hook.md`).
`builders` (hook key -> `Callable(node) -> Node3D` in 3D units: a kind, `FURNITURE` for every `ObjectArt` piece, or a finer key for one art id; `FLOOR` for the floors) is the hook a domain's own mesh plugs into
(`meshes.md`); `track(node, builder)` and `track_group(group, builder)` mirror a drawn thing that is no physics body (a dropped item, debris, a bullet) by the same rules;
`MirrorConfig` holds the proxy heights and colours. **Giving a domain's things a 3D mesh: `meshes.md`** (the kit, units, colours from the tones, cache keys, heights, where meshes live); the hook's keys and rules, and the vision-mask globals: `mesh-hook.md`.
Tests: `tests/art/mirror_follows_bodies_test.gd`, `mirror_follows_rebuilt_colliders_test.gd`, `mirror_hides_seated_character_test.gd`, `mirror_mesh_hook_test.gd`, `mirror_hook_keys_test.gd`, `mirror_mesh_lifecycle_test.gd`, `mesh_kit_suite.gd`, `mesh_cache_suite.gd`, `mesh_nodes_suite.gd`. Shaders compile only windowed, so a change to a shader needs one windowed run (`tools/run_tests.sh --windowed`).

## The pixel post (`post/`, interface 27)

The 3D picture is made to read as pixel art (#193 rule 6): drawn at a low internal resolution (a picture pixel is an art pixel, General's `RenderConfig.texel_match`) and shown with nearest
filtering, through two things Art owns, tuned in `PixelPostConfig` (ADR 0003). **`ToonMaterial.shared()`** (made by `make()`; its per-instance uniforms fill the engine's buffer, `project.godot` raises `rendering/limits/global_shader_variables/buffer_size` far past 4096 (test `art/shader_instance_buffer`): a 5v5 match uses ~2100) is the one `ShaderMaterial` (`toon.gdshader`) every mesh of
the 3D view shares, a colour per instance (`base_color`, an instance uniform): the dusk's ambient plus each light's amount (N.L times its fall-off and shadow) stepped into `bands` bands (3), tinted
by the light and capped (`ToonLightConfig`, `ToonLight`; `textured-toon.md`). **`PixelPost.attach(camera, oversample)`** adds the
outline quad (`outline.gdshader`) under the view's camera: a dark line where the depth's second difference steps (a silhouette, `silhouette_px` wide) or the normal
creases (`crease_px`), so a floor seen at an angle stays clean. `turn_supersample` and `supersample` are both 1: 2 for the turn flickers more on textured art (averaging nearest-sampled art adds colours; `art/pixel_post_shimmer`), the mechanism (`View3D` renders larger and averages down while turning) stays. A face of a mesh-kit mesh carries its own colour in the vertex colour (`COLOR`, times the instance's `base_color`). **Global shader uniforms** (`ToonMask`) are the player's view in 3D (Vision sets them, `docs/player-vision.md` V12), read by the three toon shaders (one `toon_common.gdshaderinc`: never restate `light()`) and the outline pass, so a mesh needs no per-mesh edit (`vision-hook.md`). Tests: `tests/art/mirror_proxies_use_toon_material_test.gd`, `tests/general/pixel_post_view_test.gd`; the look itself is only judged windowed
(`general/render_3d_match_windowed`, `art/pixel_post_shimmer`, `art/toon_vision_hook_windowed`, `vision/vision_mask_3d_windowed`, `art/toon_tex_windowed`).

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
