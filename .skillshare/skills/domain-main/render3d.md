# The 3D render mode in Main

Side file of `domain-main`.

`Settings.render_mode` is read in `start_match` (so a change applies at the next match, never to the one that runs) and put in the spec as `render`
(`MatchBuilder.spec`, interface 23). With `RENDER_3D` Main hides the `World` before it is built (not one frame of the 2D world is drawn), builds the
3D view first (`main_view3d.gd`: a `CanvasLayer` named `View3D` on `RenderConfig.canvas_layer`, below the HUD, with a `TextureRect` over a
`SubViewport` holding General's `CameraRig`, one hard-shadow sun and a flat ambient, and Art's `WorldMirror`) and mirrors the match once it is
built; `MatchBuilder.stage` builds no 2D lights for it. A 2D match builds none of this and is the game as it was. The hard shadow filter is a renderer
global: the view sets it and puts it back to the project's value when it leaves the tree. `_teardown_world` and the next `start_match` take the view away
(`_end_view3d`). The sim, the view cone and the AI are untouched; the 2D vision and debug overlays are not shown in 3D mode until the pixel-post job
draws them flat on the ground. Test: `tests/general/render_mode_setting_test.gd`. Interface 27.

