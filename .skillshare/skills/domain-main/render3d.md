# The 3D render mode in Main

Side file of `domain-main`.

`Settings.render_mode` is read in `start_match` (so a change applies at the next match, never to the one that runs) and put in the spec as `render`
(`MatchBuilder.spec`, interface 23). With `RENDER_3D` Main hides the `World` before it is built (not one frame of the 2D world is drawn), builds the
3D view first (`main_view3d.gd`: a `CanvasLayer` named `View3D` on `RenderConfig.canvas_layer`, below the HUD, with a `TextureRect` over a
`SubViewport` holding General's `CameraRig`, one hard-shadow sun, Art's `WorldMirror` and the pixel post: the picture is rendered at `RenderConfig.internal_lines` rows at the reference window height and shown nearest-filtered, with the toon material and the outline quad of Art's `post/`) and mirrors the match once it is
built; `MatchBuilder.stage` builds no 2D lights for it (the painters' textures and occluders remain until the 2D render is deleted; the vision memory's capture is stopped in 3D, `PlayerView.capture_on`, interface 25). A 2D match builds none of this and is the game as it was. The hard shadow filter is a renderer
global: the view sets it and puts it back to the project's value when it leaves the tree. `_teardown_world` and the next `start_match` take the view away
(`_end_view3d`). The sim, the view cone and the AI are untouched; the player's view and the debug overlays are drawn flat on the ground over the 3D view: the view sets `GroundLayer.enabled`, so each overlay is moved under a `GroundLayer` (`domain-general/camera3d.md`) that follows `Pointer.screen_transform`. `_base_spec` names `render` from the setting, as MatchBuilder's own default would beat it. Tests: `tests/general/pixel_post_view_test.gd`, `tests/vision/capture_stops_in_3d_test.gd`, `tests/general/render_mode_setting_test.gd`, `render_spec_builds_no_2d_lights_test.gd` (a spec's `render` beats the setting; no 2D lights in 3D). Interface 27.

