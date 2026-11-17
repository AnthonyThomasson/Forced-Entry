class_name ObjectStreetMeshConfig
## Objects domain, the 3D meshes of the street (`street_mesh.gd`; `domain-art/meshes.md`): the road
## sits `kerb` px below the pavement, so the pavement's edge is the kerb; the paint (lane dashes,
## crossings) is flat, `mark_lift` px over its surface. A `class_name` holder of `static var`s, read
## as `ObjectStreetMeshConfig.<name>` (ADR 0003). Lengths are 2D pixels, the art's units. Colours
## are the street painters' own (`ObjectArtStreetConfig`, `ObjectArtCrossingConfig`).

## How far the road lies below the pavement (px). The pavement is level with a room's floor.
static var kerb: float = 3.0
## How far paint floats over the road (px): thin enough to be flat, thick enough never to fight
## the road's own surface.
static var mark_lift: float = 0.3
## The lane's centre line: dashes `lane_dash` long and `lane_width` wide with `lane_gap` between,
## the first `lane_start` in from the road's end and the last `lane_end_clear` short of the other.
static var lane_dash: float = 26.0
static var lane_gap: float = 28.0
static var lane_width: float = 3.5
static var lane_start: float = 4.0
static var lane_end_clear: float = 34.0
## The kerb's band on the pavement's road side: the dark band `curb_band` wide, then a lighter line
## `curb_line` wide inside it (the colours of the 2D curb).
static var curb_band: float = 2.0
static var curb_line: float = 1.0
## How much lighter the kerb's inner line is than its band.
static var curb_line_lighten: float = 0.25
