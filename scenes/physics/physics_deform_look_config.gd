class_name PhysicsDeformLookConfig
## How a dent looks, for the Physics System (scenes/physics/deformation.gd): the fill's darkening
## and the blood mark a round leaves on an object. A
## `class_name` holder of `static var`s, read as `PhysicsDeformLookConfig.<name>`; there is no
## instance and no autoload.

## A bloody mark's colour on an object a bullet carried blood onto (alpha is scaled by how much it
## carried).
static var blood_mark_color: Color = Color(0.55, 0.04, 0.05)
## Radius (px) of that mark.
static var blood_mark_radius: float = 4.5
## Fill darkening -------------------------------------------------------------
## Max amount the fill color is darkened toward black at full accumulated damage.
static var darken_max: float = 0.35
## Accumulated damage at which fill darkening reaches `darken_max`.
static var darken_full: float = 100.0
