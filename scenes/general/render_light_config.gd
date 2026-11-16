class_name RenderLightConfig
## The 3D view's backdrop (General domain, Main's `main_view3d.gd` reads it). What lights the 3D
## world is the Lighting domain's (`WorldLighting3D`, `Lighting3DConfig`, #193 phase 3). A
## `class_name` holder of `static var`s, read as `RenderLightConfig.<name>`.

## What shows where nothing is drawn.
static var background_color: Color = Color(0.07, 0.06, 0.09)
