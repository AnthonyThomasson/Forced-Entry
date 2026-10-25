class_name PhysicsDeformConfig
## Deformation's shape (interface 4's defaults), for the Physics System (scenes/physics/): the
## collider rebuild, the impact cap, the dents, the chunks and the silhouette's resolution. How a
## dent is drawn is `PhysicsDeformLookConfig`. A `class_name` holder of `static var`s, read as
## `PhysicsDeformConfig.<name>`; there is no instance and no autoload.

## Rebuild the struck object's / wall segment's collider to follow the deformed shape.
static var update_collider: bool = true
## Max impacts remembered per object / per wall segment (oldest dropped past this).
static var max_impacts: int = 24
## Dents ----------------------------------------------------------------------
## Dent depth in px per point of dealt damage (a hit's depth = damage × this, capped).
static var depth_per_damage: float = 0.3
## Cap on a single impact's dent depth (px).
static var max_depth: float = 5.0
## How far along the surface a dent/notch spreads from the impact point (px).
static var radius: float = 7.0
## Thickness of solid a dent must leave in front of the object's opposite face (px), so
## repeated hits cave inward but never punch through and grow out the back.
static var back_margin: float = 2.0
## Solid core kept at the shape's center, as a fraction of its half-extent: no dented point
## may enter it, so opposite dents can't meet and fold the silhouette inside out. Big
## furniture never dents this deep, so it only binds on a small body (a character).
static var core_fraction: float = 0.3
## Missing pieces (chunks) ----------------------------------------------------
## Dealt damage at or above which an impact carves a "missing piece" instead of a dent.
static var chunk_damage: float = 18.0
## Extra depth multiplier for a chunk carve vs a normal dent's depth.
static var chunk_depth: float = 1.6
## How much wider a chunk's reach is than `radius`.
static var chunk_reach_scale: float = 2.2
## Random ± jitter fraction applied to a chunk carve so the bite looks torn.
static var chunk_jitter: float = 0.35
## Silhouette resolution ------------------------------------------------------
## Perimeter sample counts: points around a circle, and points per rect edge.
static var circle_points: int = 44
static var rect_points_per_edge: int = 12
