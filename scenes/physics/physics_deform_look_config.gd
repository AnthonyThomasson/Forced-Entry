class_name PhysicsDeformLookConfig
## How a dent is drawn, for the Physics System (scenes/physics/deformation.gd): the cracks, the
## hole, the scorch halo, the fill's darkening, and the blood mark a round leaves on an object. A
## `class_name` holder of `static var`s, read as `PhysicsDeformLookConfig.<name>`; there is no
## instance and no autoload.

## A bloody mark's colour on an object a bullet carried blood onto (alpha is scaled by how much it
## carried).
static var blood_mark_color: Color = Color(0.55, 0.04, 0.05)
## Radius (px) of that mark.
static var blood_mark_radius: float = 4.5
## Cracks ---------------------------------------------------------------------
## Extra cracks per point of dent depth (added to a base of 2), and base crack length px.
static var crack_count: float = 0.4
static var crack_length: float = 7.0
## Line width of drawn cracks (px).
static var crack_width: float = 1.0
## Bullet hole / scorch -------------------------------------------------------
## Bullet-hole radius as a fraction of dent depth (min 1.5px).
static var hole_radius_scale: float = 0.4
## Base scorch-halo radius (px); grows with dent depth.
static var scorch_radius: float = 3.0
## Scorch-halo opacity (0–1).
static var scorch_alpha: float = 0.12
## Fill darkening -------------------------------------------------------------
## Max amount the fill color is darkened toward black at full accumulated damage.
static var darken_max: float = 0.35
## Accumulated damage at which fill darkening reaches `darken_max`.
static var darken_full: float = 100.0
