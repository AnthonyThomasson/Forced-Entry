# The 3D camera rig (`scenes/general/camera_rig.gd`)

Side file of `domain-general`.

`CameraRig` (`camera_rig.gd`, interface 27) is the 3D view's camera: an orthographic `Camera3D` that frames what the sim's `Camera2D` frames. The
`Camera2D` stays the focus, zoom and shake source (Sound, the cull and the tests read it); the rig reads its `get_screen_center_position()` (focus
plus shake offset) and `zoom` each frame and places the camera on the ground point (x, 0, y) at `RenderConfig.pitch_degrees` (35.264, true isometric) and
its `yaw` (a property in degrees, 45 to start; the camera-turn jobs set it). It sizes the `SubViewport` it is bound to (`RenderConfig.internal_lines`
rows, the window's when 0, plus a 1 px margin) and snaps the focus to that pixel grid, shifting the shown rectangle back by the remainder, so a following
camera does not shimmer. `RenderConfig` holds `unit` (the one 2D-to-3D scale, Art's mirror reads it too), the camera and the view's canvas layer;
`RenderLightConfig` the interim sun and ambient. Test: `tests/general/camera_rig_frames_focus_test.gd`.

