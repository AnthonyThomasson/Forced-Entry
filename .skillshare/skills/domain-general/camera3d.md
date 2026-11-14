# The 3D camera rig (`scenes/general/camera_rig.gd`)

Side file of `domain-general`.

`CameraRig` (`camera_rig.gd`, interface 27) is the 3D view's camera: an orthographic `Camera3D` that frames what the sim's `Camera2D` frames. The
`Camera2D` stays the focus, zoom and shake source (Sound, the cull and the tests read it); the rig reads its `get_screen_center_position()` (focus
plus shake offset) and `zoom` each frame and places the camera on the ground point (x, 0, y) at `RenderConfig.pitch_degrees` (35.264, true isometric) and
its `yaw` (a property in degrees, 45 to start). **Q / E turn it** (`_turn`: while `Keybinds.get_camera_turn()` is held the yaw turns at `RenderConfig.turn_speed_degrees`, 90 a second, free of any snap and about the focus; none held, it stays). The rig binds `Pointer` to its camera and displayed rect in `bind`, and runs at `process_priority` 50, before the player's view (100) and every `GroundLayer` (110), which read it. It sizes the `SubViewport` it is bound to (`RenderConfig.internal_lines`
rows at a `reference_height` window: a picture pixel is `reference_height / internal_lines` screen pixels rounded to a whole number, 3, at any window size, with the rows that cover the window, times `oversample`, plus a 1 px margin) and snaps the focus to that pixel grid, shifting the shown rectangle back by the remainder, so a following
camera does not shimmer. `RenderConfig` holds `unit` (the one 2D-to-3D scale, Art's mirror reads it too), the camera and the view's canvas layer;
`RenderLightConfig` the interim sun and ambient. Test: `tests/general/camera_rig_frames_focus_test.gd`.


## The flat overlays (`ground_layer.gd`)

`GroundLayer` (a `CanvasLayer`, `class_name`) is where the 3D render mode draws what the hidden 2D world cannot: the player's view (its composite) and the debug overlays. While `GroundLayer.enabled` (Main's 3D view sets it) `ViewLayers.overlay(item)` and the view's composite call `GroundLayer.adopt(item, canvas_layer)`, which, once the item is in the tree and the frame's tree changes are over, moves it under a `GroundLayer` made beside it (named `GroundOverlays` on `RenderConfig.overlay_layer`, or `GroundVision` on `vision_layer` for the composite). A `CanvasLayer` is not a `CanvasItem`, so the hidden world does not hide what is under it, it lives and dies with its owner, and its `transform` is `Pointer.screen_transform` each frame (priority 110, after the rig), so the overlay's world-space drawing lies flat on the 3D floor at any yaw. In 2D it does nothing. An overlay that drew from the node's own origin must use `to_local` of its owner's position, as the world-space overlays do (a moved overlay's origin is the world's). Tests: `tests/general/ground_overlays_3d_test.gd` (Main whole, a played 3D match), `render_3d_turn_windowed_test.gd` (windowed). There the memory capture is off, so the composite dims the unseen ground by `RenderConfig.unseen_dim` (0.6; 1 is the 2D black) instead of blacking it; `tests/vision/composite_dims_unseen_in_3d_test.gd`.
