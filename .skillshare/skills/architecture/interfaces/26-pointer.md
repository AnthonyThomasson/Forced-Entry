26. **Any domain → General: `Pointer`** (`general/pointer.gd`, `class_name`, static; one place a screen point and a world point are
    converted and the pointer is read)
    - **Context:** every method takes a node of the world (`node`) and reads that node's viewport, so a second viewport (the player's
      view's memory and mask, a test's sub-viewport) converts by its own view. With no 3D rig bound (a headless test world, a second viewport) it is backed by the viewport's canvas transform
      (the active `Camera2D`'s view; the identity with no camera, and with no viewport at all). In the 3D render (27, the game's only one) the rig binds
      itself (`bind_3d(camera, rect, screen)`, released by `unbind_3d`) and a node of the viewport the sim's `Camera2D` serves converts
      through the orthographic camera instead: a screen point is the camera ray that meets the ground plane `y = 0`, and the ground's
      place on the screen is the camera's exact ground-to-screen affine at its yaw, pitch and zoom, read through the DISPLAYED rect of
      the 3D view (never the picture's internal size, so the picture's pixel size changes nothing), worked out once a frame by the rig
      (`refresh_3d`, after it places the camera), so a call mid-frame reads that frame's camera. A node of any other viewport
      still converts by its own canvas transform; no caller changes.
    - **Convert:** `world_of(node, screen) -> Vector2`, `screen_of(node, world) -> Vector2`, `screen_transform(node) -> Transform2D`
      (world to screen; what the player's view copies into the viewports it renders through) and `visible_world_rect(node) -> Rect2`
      (the world the viewport shows; empty with no viewport). No code outside `Pointer` calls `get_canvas_transform()` to convert
      between screen and world: a test that asserts a viewport's canvas transform equals the main one reads the transform itself.
    - **With a rig bound (`Pointer.is_3d(node)`):** `screen_transform` is that affine (world to screen, whose columns are the screen step of one px of
      ground along +x and +y), `world_of` its inverse (the ray meets the ground), `visible_world_rect` the rect that bounds the four
      screen corners on the ground (a turned view shows a diamond of ground, so it is larger than the screen over the zoom).
      `world_vector(node, screen_vector) -> Vector2` is a screen step as the ground step that shows as it (the transform's linear part
      inverted) and `world_direction(node, screen_dir) -> Vector2` the same turned into a direction of the input's length, returned
      untouched when no rig is bound: **screen-relative controls** (the human's WASD, the spectator's pan keys and screen-edge pan,
      the camera's look-ahead toward the mouse) read the world direction through them; a seated driver's keys never do (the vehicle's
      throttle and steer, `docs/vehicles.md` V5).
    - **Read the pointer:** `screen_mouse(node) -> Vector2` (the camera's look-ahead, the command menu's non-mouse fallback) and
      `world_mouse(node) -> Vector2` (the floor point under the mouse). Both return the injected point while one is set, else the real mouse.
    - **Aim in 3D (#194 D8):** `aim_hit(node, ignore := null) -> Dictionary` (needs the rig: `is_3d`; `{}` otherwise): the cursor's line of sight (the camera's own direction through the ground point
      under the mouse: an orthographic view's rays are parallel) cast into the twin space (29), the player's own body (`ignore`) looked through, and so is every twin whose mesh the wall fade holds faded (`FadedTwins.holds(body id, plan point)`, interface 27: the fade dithers the mesh only, the twin stays solid, so the cursor over floor seen through a faded wall is over that floor and the shot flies level, not up at the wall's face; held from more than half faded, a moving piece's footprint lags up to `poll_frames`). `{ kind: &"body", plan, height }` where it meets a character's
      twin first (hovering a head is the head: `height` px above the floor, `plan` the 2D point of the hit); `{ kind: &"cover", plan, height }` where it first meets a piece, wall, door or vehicle, a
      character behind it or not (D8a: that point on it); `{}` for bare floor or nothing. The player controller turns it into `movement.aim_point` and
      `movement.aim_height` (the floor point and `AIM_LEVEL` for `{}`: the shot flies level at the muzzle's height). A body hit moves `aim_point` onto the body, so Space's nearest-to-mouse then reads
      that point.
    - **Inject (Testing, 13):** `Pointer.inject(screen)` stands a screen point in for the mouse until `Pointer.release()`. It never
      warps the real mouse, and an input event keeps its own position. The injected point is one static; `TestWorld.restore` releases
      it, so no test leaks it into the next. `CommandServer`'s `aim` still warps the real mouse (to `Pointer.screen_of`). It works with a rig bound as without: the aim, fire, Space's
      nearest-to-mouse, the command menu and the spectator inspector read the point through `Pointer`.
    - **Not covered:** `Sound`'s camera reads (the 3D listener is #193). No tunables.
