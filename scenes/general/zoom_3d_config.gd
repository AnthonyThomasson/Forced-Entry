class_name Zoom3dConfig
## The 3D render's zoom in whole steps (General domain, `zoom_steps.gd`, `camera_controller.gd`;
## #193 phase 2b). A `class_name` holder of `static var`s, read as `Zoom3dConfig.<name>` (ADR 0003),
## so a test may `set_static` them. 2D keeps `CameraConfig`'s continuous zoom.

## The 3D render's zoom steps, smallest first (#193 phase 2b, G15): a picture pixel is a whole
## number of screen pixels, one art pixel at 1x, so the 3D view zooms in these steps only (the wheel
## steps between them and the automatic zoom, the fit of the spectator's framing too, snaps to one).
## 1x, 2x and 3x are the art at its own size, doubled and tripled; the 0.5 below them is the
## spectator's room to frame a spread-out match (a picture pixel of two art pixels), the way out the
## 2D view's 0.4 to 2.0 framing range gave. Drop it to have no zoom below 1.
static var steps: PackedFloat32Array = PackedFloat32Array([0.5, 1.0, 2.0, 3.0])
## How far past a boundary between two steps the automatic zoom (the spectator's fit, a vehicle's
## zoom-out) must go, as a fraction of the zoom, before the 3D view changes step: 0.15 is 15%, so a
## vehicle whose speed hovers at a boundary holds its step. A fit that falls below its step shows
## the smaller step at once (nobody is left off the screen); only rising waits for the margin.
static var hysteresis: float = 0.15
## Seconds the wheel's gathered fraction of a notch (a trackpad's scroll) is kept: a pause longer
## than this starts the next scroll from nothing.
static var notch_idle: float = 0.3
