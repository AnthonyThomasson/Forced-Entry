class_name ObjectArtStreetConfig
## The street ring's look (street_painter.gd, street_marks.gd): its tiles and colours, the curb and
## lane paint, and the street marks' wear and cluster spacing. A `class_name` holder of `static
## var`s, read as `ObjectArtStreetConfig.<name>`; there is no instance and no autoload.

## The tiles (world px) and their colours: asphalt big, so its even grain has no period the eye
## picks up; sidewalk two by two slabs of `slab_px`.
static var asphalt_px: int = 256
static var sidewalk_px: int = 64
static var slab_px: float = 32.0
static var asphalt_color: Color = Color(0.24, 0.21, 0.17)
static var sidewalk_color: Color = Color(0.42, 0.38, 0.32)
## The curb drawn along a sidewalk's road side, and the lane dashes' paint.
static var curb_color: Color = Color(0.3, 0.27, 0.22)
static var lane_color: Color = Color(0.85, 0.82, 0.62, 0.6)
## The marks laid over a piece of street: on the road one cluster of 1-3 per
## `road_cluster_area` px² (cracks, patches, oil), on the sidewalk one of 1-2 per
## `walk_cluster_run` px of its length (cracks, stains, gum, weeds) and a cluster of odd
## slabs per `slab_cluster_run`; litter and puddles in the gutter, one cluster per
## `litter_cluster_run` px of curb.
static var road_wear: Array = [["crack", 3.0], ["patch", 1.5], ["oil", 2.0]]
static var walk_wear: Array = [["crack", 3.0], ["stain", 2.0], ["gum", 2.0], ["weeds", 1.0]]
static var road_cluster_area: float = 120_000.0
static var walk_cluster_run: float = 500.0
static var slab_cluster_run: float = 380.0
static var litter_cluster_run: float = 420.0
