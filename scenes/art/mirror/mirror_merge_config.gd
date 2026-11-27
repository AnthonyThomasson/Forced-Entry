class_name MirrorMergeConfig
## Art domain, the merged chunks of the still world (`still_merge.gd`, interface 27): which share of
## the picture one chunk covers and how the building of them is spread over frames. A `class_name`
## holder of `static var`s, read as `MirrorMergeConfig.<name>`.

## Whether the still world's meshes are drawn in merged chunks at all (off: each draws itself).
static var enabled: bool = true
## The side, px, of the square of ground one chunk takes its meshes from (by each mesh's middle): a
## screen of 2560 x 1440 holds a dozen or two.
static var cell: float = 768.0
## How many frames after it was carried a mesh is first asked to join a chunk: by then it has its
## tint, its light, its layers (the sun's pass) and a body at rest sleeps.
static var settle_frames: int = 20
## The frames between two rounds over the meshes waiting to join.
static var round_frames: int = 45
## How many waiting meshes a frame looks at, and the vertices a chunk is full at: as the view is
## built (`build_all`), and in play, where a frame builds one chunk at most (4000 is about 1 ms).
static var looked_per_frame: int = 120
static var chunk_vertices: int = 12_000
static var play_vertices: int = 4_000
## The fewest meshes a chunk is built of: fewer draw themselves (and wait for company).
static var chunk_members: int = 3
## How many rounds a mesh that cannot join yet (a piece still rolling) is asked again.
static var rounds: int = 12
