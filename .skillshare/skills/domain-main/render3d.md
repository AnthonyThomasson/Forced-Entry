# The 3D render in Main

Side file of `domain-main`.

The 3D render is the only render (ADR 0013; there is no render mode and no `render` key in a match spec). `start_match` hides the `World` before it is built (not one frame of
the 2D world is drawn) and builds the 3D view first (`main_view3d.gd`: a `CanvasLayer` named `View3D` on `RenderConfig.canvas_layer`, below the HUD, with a `TextureRect` over a
`SubViewport` holding General's `CameraRig`, the Lighting domain's dusk, Art's `WorldMirror` and the pixel post: a picture pixel is `round(zoom)` screen pixels (one art pixel at a whole zoom, `RenderConfig.texel_match`, at most `max_lines` rows) and the picture is shown nearest-filtered, with the toon material and the outline quad of Art's `post/`) and mirrors the match once it is
built (`mirror_world`) and lights it (`light_world`); `MatchBuilder.stage` builds no 2D lights, and the player's view builds two masks the shaders read (interface 25), no 2D picture. The hard shadow filter is a renderer
global: the view sets it and puts it back to the project's value when it leaves the tree. `_teardown_world` and the next `start_match` take the view away
(`_end_view3d`). The setup flow pre-warms the district's and the furniture's flat art at launch (`WorldGen.prewarm(true)`; headless skips it). The sim, the view cone and the AI are untouched; the player's view is drawn by the toon shaders (`domain-vision`, V12) and the debug overlays flat on the ground over the 3D view: each overlay is moved under a `GroundLayer` (`domain-general/camera3d.md`) that follows `Pointer.screen_transform`.

A test world is shown by the same view in a window (`TestSession._show_picture`, interface 13): the in-game runner and `--shots` runs, unless the test builds its own (`TestSetup.own_picture()`: a `Main` run whole, a view made by hand). Tests: `tests/general/pixel_post_view_test.gd`, `settings_file_test.gd` (a saved `render_mode` is skipped), `ground_overlays_3d_test.gd`. Interface 27.
