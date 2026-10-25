class_name BloodPoolConfig
## The death bleed-out pool (scenes/physics/blood/: BloodPool, BloodFlow): its cells and duration,
## and its flow (the cell size, the noise, the aim bias, the soft edge, the edge darkening).
## A `class_name` holder of `static var`s, read as `BloodPoolConfig.<name>`; there is no instance
## and no autoload.

## A body bleeding out where it came to rest after death (Physics.bleed_out): how many grid cells
## its flowing pool claims (area = cells * flow_cell_size²) and the seconds its edge takes to sweep
## out across them.
static var bleed_out_cells: int = 225
static var bleed_out_duration: float = 10.0
## Side (px) of a flow grid cell. Smaller = finer edge, more physics queries.
static var flow_cell_size: float = 4.0
## How strongly noise makes some directions cheap to flow into (fingers/bays) and others dear.
## 0 = an even disc; ~1 = strongly lobed.
static var flow_noise_strength: float = 0.9
## Noise frequency per cell; lower = broader lobes.
static var flow_noise_frequency: float = 0.12
## How much the flow favours the pool's random lean (0 none .. 1 strongly one way).
static var flow_aim_bias: float = 0.3
## Softness of the advancing edge, in cells of flow cost: how far behind the front a cell is still
## filling in. Larger = a wider, gentler fade at the edge.
static var flow_soft_edge: float = 3.0
## Brightness drop of rim cells vs. the deep centre (0 none .. 1 black).
static var flow_edge_darken: float = 0.25
