class_name ObjectArtWallConfig
## The wall cap's tile (wall_painter.gd): its length, its pattern and its grime. A `class_name`
## holder of `static var`s, read as `ObjectArtWallConfig.<name>`; there is no instance and no
## autoload.

## Wall cap tile length (world px) and pattern ("plaster" | "brick").
static var tile_px: int = 48
static var pattern: String = "plaster"
## The cap's even grime: this many darkened pixels a pixel.
static var grime_density: float = 0.1
