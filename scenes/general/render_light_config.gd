class_name RenderLightConfig
## The 3D view's light (General domain, Main's `main_view3d.gd` reads it): one directional light
## with hard shadows over a flat ambient, the interim of phases 1 and 2 of #193 (G9). The lighting
## job of phase 3 turns the dusk into this and moves it to the Lighting domain. A `class_name`
## holder of `static var`s, read as `RenderLightConfig.<name>`.

## The sun's rotation in degrees (pitch, yaw, roll): down onto the floor from a quarter off the
## camera's side, so walls throw a readable shadow.
static var sun_rotation: Vector3 = Vector3(-50.0, -17.0, 0.0)
## The sun's strength and tint.
static var sun_energy: float = 1.0
static var sun_color: Color = Color(1.0, 0.96, 0.9)
## The flat ambient every surface gets, whatever it faces: a colour and its strength.
static var ambient_color: Color = Color(0.55, 0.56, 0.62)
static var ambient_energy: float = 1.0
## What shows where nothing is drawn.
static var background_color: Color = Color(0.07, 0.06, 0.09)
## How far from the camera the sun's shadow reaches, and its biases, in 3D units (px-scale
## geometry needs a bias of about a pixel).
static var shadow_max_distance: float = 1600.0
static var shadow_bias: float = 0.6
static var shadow_normal_bias: float = 1.5
