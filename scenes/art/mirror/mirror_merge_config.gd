class_name MirrorMergeConfig
## Art domain, the merged chunks of the still world (`still_merge.gd`, interface 27): which share of
## the picture one chunk covers and how much it holds. A `class_name` holder of `static var`s, read
## as `MirrorMergeConfig.<name>`.

## Whether the still world's meshes are drawn in merged chunks at all (off: each draws itself).
static var enabled: bool = true
## The side, px, of the square of ground one chunk takes its meshes from (by each mesh's middle): a
## screen of 2560 x 1440 holds a dozen or two.
static var cell: float = 768.0
## The vertices a chunk is full at, and the fewest meshes one is built of (fewer draw themselves).
static var chunk_vertices: int = 12_000
static var chunk_members: int = 3
