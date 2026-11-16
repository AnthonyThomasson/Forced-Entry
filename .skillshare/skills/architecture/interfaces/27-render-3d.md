27. **Main → Art: `WorldMirror`, and General's `CameraRig`: the 3D render** (`art/mirror/`, `general/camera_rig.gd`; Main's `main_view3d.gd`
    builds them; ADR 0013). In the 3D render mode (`Settings.render_mode`, 14) the sim stays 2D and a 3D view mirrors it: Main never draws
    the 2D world, it follows every drawn 2D body in a 3D world seen through an orthographic camera.
    - **The mode:** `Main.start_match` reads `Settings.render_mode` (`RENDER_2D` `"2d"`, the default, or `RENDER_3D` `"3d"`) and puts it in the spec as `render` (23; a spec that
      names `render` keeps it): a change applies at the next match. With 3D, Main hides the `World` before it is built, `MatchBuilder.stage` builds no 2D lights (20; 
      Vision's capture `SubViewport` is stopped, 25), and Main builds the 3D view (`View3D`, a `CanvasLayer`
      on `RenderConfig.canvas_layer` below the HUD: a `TextureRect` showing a `SubViewport` with the rig, one sun over a flat ambient, and the mirror); the sim is untouched, and the vision and
      debug overlays draw flat on the ground (below).
    - **`WorldMirror`** (`art/mirror/world_mirror.gd`, `class_name`, a `Node3D` made by `WorldMirror.new()`; Art imports nothing but
      General's `RenderConfig`, and reads the bodies duck-typed: the groups `characters`, `vehicles`, `doors` and `floors`, and the properties
      `wall_thickness`, `art_color`, `color`, `faction`, `size`):
      - `mirror(root: Node) -> void` gives every `PhysicsBody2D` under `root` a proxy per collision shape and every `floors` member a flat slab;
        2D `(x, y)` is 3D `(x * unit, 0, y * unit)` with `unit` = `RenderConfig.unit`, **the one scale** (heights scale with it). A body or floor
        that spawns later is mirrored on the next frame, one that leaves the tree loses its proxies, a changed collision shape re-mirrors its body (not a wall: its mesh follows the shapes itself), a body that dies is hidden unless its mesh stays. A proxy or own mesh is hidden while its shapes are all disabled (a seated character) or its body's `visible`
        is false (not `is_visible_in_tree`).
      - The proxy: a box (walls full height, doors their leaf, furniture a height from its footprint, vehicles low), a cylinder for a round non-character, a capsule for a character; one shared
        mesh per shape kind in the shared toon material, a colour per instance from `art_color` / `color`, a faction's name hash, else the node's name's. Heights, colours: `MirrorConfig`.
      - **The update rule** (each frame, by `_process`, or `update()` by hand): a moving body (`CharacterBody2D`, `AnimatableBody2D`, `RigidBody2D`) has its shape's transform read and the
        proxy **written only when it changed**; a sleeping `RigidBody2D` is **skipped** (read once more as it falls asleep); a body that never moves is written once; a freed shape is checked
        untyped (`is_instance_valid` on a Variant). Read-outs: `count`, `followed`, `written`, `proxies_of(body) -> Array[Node3D]`.
      - **The mesh hook** (full rules `domain-art/mesh-hook.md`): `builders: Dictionary`, a key -> `Callable(node: Node2D) -> Node3D` in **3D units**, set before
        `mirror()` (Main's `_register_meshes()`). Keys: a kind (`MirrorProxy.WALL`, `DOOR`, `CHARACTER`, `VEHICLE`, `FURNITURE`, `FLOOR`) or a finer key that wins
        (`MirrorProxy.furniture_key(art)`, `floor_key(art)`). The node replaces the body's proxies and follows it; null or no key keeps the proxy. `track(node, builder)` and
        `track_group(group, builder)` do the same for drawn things that are no physics body (dropped items, bullets). A mesh node's own hooks (`mirror_update`, `on_body_died`, `remirror`, `follows_shapes`, `built(body, mesh)`): `render-3d-meshes.md`.
    - **`CameraRig`** (`general/camera_rig.gd`, `class_name`, a `Node3D` that owns an orthographic `Camera3D` as `camera`): `bind(source: Camera2D,
      viewport: SubViewport, rect: Control = null)` follows the sim's `Camera2D`, which stays the focus, zoom and shake source (Sound, the cull and
      the tests read it): each frame the camera frames `source.get_screen_center_position()` (focus plus shake offset) at `source.zoom` (ortho size: the screen's height in 2D px over the zoom, times
      `unit`), at the pitch `RenderConfig.pitch_degrees` (80, near top-down) and `yaw` (degrees, `RenderConfig.yaw_degrees` 0 to start: north up). **Q / E turn it a quarter:** a press of a camera-turn key
      (`Keybinds.camera_turns_pressed()`) steps `yaw` `CameraTurnConfig.step_degrees` (90), eased, ending exactly on N, E, S or W (`turning()`).
      It binds `Pointer` (26) to its camera and the picture's rect (larger than the window), sizes the `SubViewport` so a picture pixel is a whole number of screen
      pixels (`texel_match`: `round(zoom)`, at most `max_lines` rows; the window plus 1 px, times `oversample`). In 3D the controller's zoom is a whole step of `Zoom3dConfig.steps`, and snaps the focus to
      that grid along the camera's right and up, shifting `rect` back by the remainder, so following does not shimmer. `texel() -> float` is the world units a picture
      pixel covers; `internal_size() -> Vector2i` the picture's size in pixels (margin included).
    - **The pixel post** (Art `art/post/`, `PixelPostConfig`): the view's meshes share one toon `ShaderMaterial` (`ToonMaterial.make()`; a colour per instance) whose light is the dusk's (20, `domain-art/textured-toon.md`: the ambient plus each light stepped into `PixelPostConfig.bands` bands, capped); `PixelPost.attach(camera, oversample)` adds a full-screen
      outline quad under the camera (a dark line where the depth steps, `silhouette_px` wide, or the normal creases, `crease_px`; `PixelPost.refresh(node, oversample)`). `View3D` shows the picture
      through a nearest-filtered `TextureRect`; it can render `supersample` (at rest) or `turn_supersample` (turning) times larger and average down through a filtered stage (`View3D.shown`), both 1: 2 flickers more on textured art.
    - **The flat overlays** (`GroundLayer`, `general/ground_layer.gd`, interim until phase 3; `domain-general/camera3d.md`): while
      `GroundLayer.enabled` (Main's view sets it) `ViewLayers.overlay` and the view's composite move the player's view and every debug overlay under a `CanvasLayer`
      (`vision_layer`; `overlay_layer`) whose `transform` is `Pointer.screen_transform`: they lie flat on the 3D floor at any yaw, over the picture and under the HUD
      (`OverlayRegistry.overlays_of`). Outside the cone the composite dims the ground by `unseen_dim`, not black.
    - **Wall fade** (rule 9, `domain-art/wall-fade.md`): Art's `WallFade` (Main's `View3D` makes it, `listen(mirror)`) fades the walls, doors and tall furniture
      between the camera and the player (spectating: every character). It reads, duck-typed: `WorldMirror.built(body, mesh)` (a builder made `mesh` for `body`),
      General's `CameraController.focus_targets() -> Array[Node2D]` (the camera's own list: read only) and Objects' `WallMesh.segments() -> Dictionary` (index -> instance, its child decals fade with it) with its `segment_replaced(index, part)`.
    - **Tuning:** `RenderConfig` (General: the camera, `texel_match`, `max_lines`, `canvas_layer`, `vision_layer`, `overlay_layer`, `unseen_dim`; `CameraTurnConfig`, `Zoom3dConfig`),
      `RenderLightConfig` (General, the backdrop; the lights are Lighting's, 20), `MirrorConfig`, `PixelPostConfig` and `ToonLightConfig` (Art).
    - **The dusk's globals** (`ToonLight`, set by Lighting): `set_ambient`, `set_sky`, `clear`.
    - **The vision hook** (phase 3's mask): global shader uniforms, `ToonMask.set_mask(texture, world_rect_px, unseen_brightness)` / `clear()`; default everything visible.
    - **The 2D art on the meshes** (ADR 0013 addendum): a mesh wears its painter's unlit render (`PixelArt.render_flat`, `domain-art/flat-paint.md`) through `MeshNodes.textured` (`domain-art/textured-toon.md`). 2D stays a render mode.
    - **Which domain has meshes** and who plugs each in (`ObjectMeshes` ... `PhysicsMeshes`): `render-3d-meshes.md`; a body with no builder keeps its proxy.
