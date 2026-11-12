26. **Any domain → General: `Pointer`** (`general/pointer.gd`, `class_name`, static; one place a screen point and a world point are
    converted and the pointer is read)
    - **Context:** every method takes a node of the world (`node`) and reads that node's viewport, so a second viewport (the player's
      view's memory and mask, a test's sub-viewport) converts by its own view. In 2D it is backed by the viewport's canvas transform
      (the active `Camera2D`'s view; the identity with no camera, and with no viewport at all). #193's 3D view swaps the bodies for a
      camera ray meeting the ground plane; no caller changes.
    - **Convert:** `world_of(node, screen) -> Vector2`, `screen_of(node, world) -> Vector2`, `screen_transform(node) -> Transform2D`
      (world to screen; what the player's view copies into the viewports it renders through) and `visible_world_rect(node) -> Rect2`
      (the world the viewport shows; empty with no viewport). No code outside `Pointer` calls `get_canvas_transform()` to convert
      between screen and world: a test that asserts a viewport's canvas transform equals the main one reads the transform itself.
    - **Read the pointer:** `screen_mouse(node) -> Vector2` (the camera's look-ahead, the command menu's non-mouse fallback) and
      `world_mouse(node) -> Vector2` (the player's aim). Both return the injected point while one is set, else the real mouse.
    - **Inject (Testing, 13):** `Pointer.inject(screen)` stands a screen point in for the mouse until `Pointer.release()`. It never
      warps the real mouse, and an input event keeps its own position. The injected point is one static; `TestWorld.restore` releases
      it, so no test leaks it into the next. `CommandServer`'s `aim` still warps the real mouse (to `Pointer.screen_of`).
    - **Not covered:** `Sound`'s camera reads (the 3D listener is #193). No tunables.
