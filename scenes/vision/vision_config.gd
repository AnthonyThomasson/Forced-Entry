class_name VisionConfig
## The Vision domain's tuning (scenes/vision/): the switch, the look of the remembered world, the
## memory's resolution and the cone polygon's rays (`docs/player-vision.md`). A `class_name` holder
## of `static var`s, read as `VisionConfig.<name>`; there is no instance and no autoload. What a
## character sees by (its cone, range, bubble and the height it looks over) is the Character's
## `CharacterVisionConfig`, read through the viewer.

## Whether a view is made at all: Main's played match watches its human, a test world watches its
## player or the actor `TestSetup.view` names (the `vision.enabled` switch, off by default there).
static var enabled: bool = true
## The look of the remembered world, "Darkwood cool": greyed by `grey` (1 = fully grey), its
## contrast `contrast` about the value `pivot`, then scaled by `brightness` and `tint` (a colour
## multiplied in).
static var grey: float = 1.0
static var contrast: float = 0.9
static var pivot: float = 0.3
static var brightness: float = 0.55
static var tint := Color(0.88, 0.96, 1.12)
## How wide the edge of the cone is feathered, screen px, laid inside the edge.
static var feather: float = 16.0
## The memory's texels per world px (it drops to fit the engine's texture limit when the world is
## too big for it).
static var memory_scale: float = 2.0
## The cone polygon: the rays of its even fan across the cone and all round the near bubble; and
## three rays at each blocking corner, the angle either side of the corner's own, rad.
static var cone_rays: int = 64
static var bubble_rays: int = 48
static var corner_offset: float = 0.0002
## A ray that ends on a blocker runs on to where it leaves that one shape, at most `far_depth` in;
## a shape whose far face is not found is taken `far_bleed` in, px.
static var far_depth: float = 120.0
static var far_bleed: float = 14.0
## The cone is rebuilt at least this often, in physics frames, whatever the watch (`ViewWatch`) has
## seen change: a backstop for a change it cannot see. Between two rebuilds it holds the polygon it
## has, which a fresh rebuild would draw again, vertex for vertex.
static var rebuild_every: int = 10
