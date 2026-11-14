27. **Main → Art: `WorldMirror`, and General's `CameraRig`: the 3D render** (`art/mirror/`, `general/camera_rig.gd`; Main's `main_view3d.gd`
    builds them; ADR 0013). In the 3D render mode (`Settings.render_mode`, 14) the sim stays 2D and a 3D view mirrors it: Main never draws
    the 2D world, it follows every drawn 2D body in a 3D world seen through an orthographic camera.
    - **The mode:** `Main.start_match` reads `Settings.render_mode` (`RENDER_2D` `"2d"`, the default, or `RENDER_3D` `"3d"`) when a match starts
      and puts it in the spec as `render` (23; a spec of the caller's that names `render` keeps it): a change applies at the next match, never to the one that runs. With 3D, Main hides the `World` before
      it is built, so not one frame of the 2D world is drawn, `MatchBuilder.stage` builds no 2D lights (20), and Main builds the 3D view
      (`View3D`, a `CanvasLayer` on `RenderConfig.canvas_layer`, below the HUD: a `TextureRect` showing a `SubViewport` with the rig, one sun
      over a flat ambient, and the mirror); the sim (bodies, nav, AI, the view cone) is untouched, and the 2D vision and debug overlays, drawn
      under the hidden `World`, are not shown until the ground-plane overlay layer of the pixel-post job.
    - **`WorldMirror`** (`art/mirror/world_mirror.gd`, `class_name`, a `Node3D` made by `WorldMirror.new()`; Art imports nothing but
      General's `RenderConfig`, and reads the bodies duck-typed: the groups `characters`, `vehicles`, `doors` and `floors`, and the properties
      `wall_thickness`, `art_color`, `color`, `faction`, `size`):
      - `mirror(root: Node) -> void` gives every `PhysicsBody2D` under `root` a proxy per enabled collision shape and every `floors` member a flat
        slab; 2D `(x, y)` is 3D `(x * unit, 0, y * unit)` with `unit` = `RenderConfig.unit`, **the one scale** (heights scale with it). A body that
        spawns later is mirrored on the next frame, one that leaves the tree loses its proxies, a collider rebuilt under a body re-mirrors it, a
        character who dies is hidden.
      - The proxy: a box (walls full height, doors their leaf, furniture a height from its footprint, vehicles low), a cylinder for a round
        non-character, a capsule for a character; one shared mesh per shape kind and one shared material (`mirror_proxy.gdshader`) with a colour
        per instance, from the body's `art_color` / `color`, a faction's name hash for a character, else a hash of the node's name. Heights and
        colours are `MirrorConfig` (Art's holder; heights in 2D px).
      - **The update rule** (each frame, by `_process`, or `update()` by hand): a moving body (`CharacterBody2D`, `AnimatableBody2D`,
        `RigidBody2D`) has its shape's transform read and the proxy **written only when it changed**; a sleeping `RigidBody2D` is **skipped** (read
        once more as it falls asleep, for its last step); a body that never moves is written once. A freed shape is checked untyped
        (`is_instance_valid` on a Variant). Read-outs for tests and probes: `count` (proxies), `followed` (moving proxies read last update),
        `written`, `proxies_of(body) -> Array[Node3D]`.
      - **The mesh hook** (phase 2's `meshkit` and the domains' meshes plug in here): `builders: Dictionary`, body kind -> `Callable(body:
        Node2D) -> Node3D`, set before `mirror()`; the kinds are `MirrorProxy.WALL`, `DOOR`, `CHARACTER`, `VEHICLE`, `FURNITURE`. A node it returns
        replaces the kind's per-shape proxies and follows the **body's** whole transform (a local frame whose origin is the body's, turned about
        the up axis by the 2D turn); null keeps the proxy. A floor is not a body and has no hook yet, and floors are mirrored when `mirror()` runs (they do not spawn mid-match).
    - **`CameraRig`** (`general/camera_rig.gd`, `class_name`, a `Node3D` that owns an orthographic `Camera3D` as `camera`): `bind(source: Camera2D,
      viewport: SubViewport, rect: Control = null)` follows the sim's `Camera2D`, which stays the focus, zoom and shake source (Sound, the cull and
      the tests read it): each frame the camera frames `source.get_screen_center_position()` (focus plus shake offset) at `source.zoom` (the ortho
      size is the screen's height in 2D px over the zoom, times `unit`: 1 screen px to a world px at zoom 1), at the pitch `RenderConfig.pitch_degrees`
      (35.264: true isometric) and `yaw` (a property in degrees, `RenderConfig.yaw_degrees` to start; the camera-turn controls set it). The rig sizes the
      `SubViewport` to `RenderConfig.internal_lines` rows (0: the window's) plus a 1 px margin, snaps the focus to that pixel grid along the camera's
      right and up and shifts and sizes `rect` back by the remainder, so following does not shimmer. `texel() -> float` is the world units a picture
      pixel covers.
    - **Tuning:** `RenderConfig` (General: `unit`, `pitch_degrees`, `yaw_degrees`, `distance`, `near`, `far`, `internal_lines`, `canvas_layer`),
      `RenderLightConfig` (General, the interim sun and ambient until the lighting job moves them to Lighting) and `MirrorConfig` (Art).
    - **Not yet:** the mouse and keys stay world-relative (the turn-control job gives `Pointer` its 3D body, 26); there is no pixel post and the
      2D vision and debug overlays are hidden in 3D mode (the pixel-post job); the meshes are proxies (phase 2).
