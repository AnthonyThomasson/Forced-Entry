class_name ObjectArtWearConfig
## World-placed wear (wear_painter.gd, room_wear.gd): a cluster's marks, spread and inset, the floor
## and wall mark kinds and sizes, the plaster colour and the variants. A `class_name` holder of
## `static var`s, read as `ObjectArtWearConfig.<name>`; there is no instance and no autoload.

## A wear cluster's marks: 1 with this chance, else 2 with `two_chance`, else 3; each further
## mark this far (px) from the cluster's centre.
static var one_chance: float = 0.45
static var two_chance: float = 0.65
static var spread: Vector2 = Vector2(14, 40)
## Marks keep this far inside the room's rect (its edges are the walls' centre lines), and this far
## apart.
static var inset: float = 8.0
static var gap: float = 4.0
## The floor marks each floor pattern takes, by weight.
static var floor_kinds: Dictionary = {
	"planks": [["plank_gap", 3.0], ["scuffs", 2.0], ["stain", 2.0], ["burns", 1.0]],
	"parquet": [["strip_gap", 3.0], ["scuffs", 2.0], ["stain", 2.0], ["burns", 1.0]],
	"tiles": [["missing_cells", 3.0], ["crack", 2.0], ["stain", 2.0]],
	"checker": [["missing_cells", 3.0], ["crack", 2.0], ["stain", 2.0]],
	"mosaic": [["missing_cells", 3.0], ["crack", 1.0], ["stain", 2.0]],
	"carpet": [["worn", 3.0], ["stain", 3.0], ["burns", 2.0]],
	"concrete": [["crack", 3.0], ["oil", 2.0], ["stain", 2.0]],
}
## A free floor mark's footprint: `[min, max]` along and across (px).
static var sizes: Dictionary = {
	"crack": [Vector2(30, 9), Vector2(80, 16)], "stain": [Vector2(12, 10), Vector2(30, 24)],
	"oil": [Vector2(18, 12), Vector2(40, 28)], "worn": [Vector2(26, 20), Vector2(56, 40)],
	"burns": [Vector2(10, 10), Vector2(18, 18)], "scuffs": [Vector2(16, 10), Vector2(32, 20)],
}
## The wall marks, by weight, and each one's length range (px) along the wall.
static var wall_kinds: Array = [
	["peel", 3.0],
	["wall_stain", 2.0],
	["wall_crack", 2.0],
	["cable", 1.0],
]
static var wall_lengths: Dictionary = {
	"peel": Vector2(12, 36),
	"wall_stain": Vector2(10, 26),
	"wall_crack": Vector2(18, 48),
	"cable": Vector2(60, 200),
}
## The wall cap's plaster as the wall marks see it (what a peel's lip and a stain sit on).
static var plaster_color: Color = Color(0.52, 0.45, 0.33)
## The chance a cluster by a wall also marks that wall.
static var wall_chance: float = 0.7
## Random-detail variants per mark kind and size (`v`): enough that no two neighbours match, few
## enough to cache.
static var variants: int = 6
