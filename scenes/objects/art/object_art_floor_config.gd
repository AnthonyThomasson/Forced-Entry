class_name ObjectArtFloorConfig
## Floor tiles (floor_painter.gd): the plank, parquet, tile, mosaic and slab sizes, the glare chance
## and the floor's seam, grout and grime dirt. A `class_name` holder of `static var`s, read as
## `ObjectArtFloorConfig.<name>`; there is no instance and no autoload.

## Floor pattern sizes (world px): plank width + board length, parquet square, glazed tile
## (also the checker cell), mosaic tile, concrete slab.
static var plank_px: int = 8
static var plank_length: int = 64
static var parquet_px: int = 16
static var tile_px: int = 24
static var mosaic_px: int = 8
static var slab_px: int = 128
## Chance that a glazed floor tile catches a glare streak.
static var glare_chance: float = 0.2
## A run-down floor's even dirt: what is packed into the seams between plank rows and round tiles,
## and the fine grime of single pixels over a tile (this many a pixel; a quarter of them pale dust).
static var seam_dirt: Color = Color(0.06, 0.05, 0.04)
static var grout_dirt: Color = Color(0.1, 0.08, 0.05)
static var grime_density: float = 0.07
static var grime_dark: Color = Color(0.12, 0.08, 0.04)
static var grime_pale: Color = Color(0.7, 0.62, 0.5)
