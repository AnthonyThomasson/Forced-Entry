class_name ObjectArtDecorConfig
## Decor (scenes/objects/art/): the plant, the lamp, the mirror frame and the small props' colours.
## A `class_name` holder of `static var`s, read as `ObjectArtDecorConfig.<name>`; there is no
## instance and no autoload. A piece's catalogue `art_opts` overrides a painter knob for that piece
## only, keyed by the knob's name without its painter prefix (`table_inset` → `inset`).

## Leaves a plant gets (a dying plant has few), its pot and soil colors, and how far its leaves have
## wilted to `plant_dead_color` (0 green .. 1 dead brown).
static var plant_leaves: int = 5
static var plant_pot_color: Color = Color(0.42, 0.26, 0.16)
static var plant_soil_color: Color = Color(0.16, 0.11, 0.07)
static var plant_wilt: float = 1.0
static var plant_dead_color: Color = Color(0.42, 0.32, 0.16)
## The lamp: a dented tin shade over a bare bulb; the bulb's glow (drawn glowing).
static var lamp_tin_color: Color = Color(0.4, 0.34, 0.24)
static var lamp_glow_color: Color = Color(1.0, 0.85, 0.45)
## A mirror's frame.
static var fixture_frame_color: Color = Color(0.4, 0.32, 0.2)
## Colors for the small props dressing surfaces (desks, nightstands, counters, workbenches) and
## the assorted contents of shelves, washers and coat racks. Lists are picked from at random.
static var prop_colors: Dictionary = {
	"paper": Color(0.575, 0.533, 0.456),
	"ink": Color(0.412, 0.398, 0.377),
	"glow": Color(0.45, 0.95, 0.42),
	"plastic_dark": Color(0.16, 0.14, 0.11),
	"plastic_light": Color(0.5, 0.45, 0.36),
	"metal": Color(0.66, 0.68, 0.72),
	"ceramic": Color(0.94, 0.93, 0.9),
	"glaze": Color(0.35, 0.55, 0.7),
	"coffee": Color(0.32, 0.2, 0.12),
	"wood_light": Color(0.82, 0.66, 0.44),
	"leaf": Color(0.3, 0.58, 0.3),
	"accent": Color(0.9, 0.75, 0.2),
	"books": [
		Color(0.42, 0.24, 0.14), Color(0.3, 0.3, 0.22), Color(0.5, 0.4, 0.22),
		Color(0.26, 0.2, 0.16), Color(0.55, 0.5, 0.38), Color(0.36, 0.18, 0.12),
	],
	"fruit": [
		Color(0.95, 0.55, 0.15),
		Color(0.85, 0.15, 0.15),
		Color(0.95, 0.85, 0.25),
		Color(0.45, 0.7, 0.2),
	],
	"flowers": [
		Color(0.95, 0.35, 0.45),
		Color(0.98, 0.85, 0.3),
		Color(0.6, 0.4, 0.85),
		Color(0.98, 0.6, 0.25),
	],
	"shoes": [
		Color(0.42, 0.24, 0.14), Color(0.3, 0.3, 0.22), Color(0.5, 0.4, 0.22),
		Color(0.26, 0.2, 0.16), Color(0.55, 0.5, 0.38), Color(0.36, 0.18, 0.12),
	],
	"coats": [
		Color(0.42, 0.24, 0.14), Color(0.3, 0.3, 0.22), Color(0.5, 0.4, 0.22),
		Color(0.26, 0.2, 0.16), Color(0.55, 0.5, 0.38), Color(0.36, 0.18, 0.12),
	],
	"towels": [
		Color(0.42, 0.24, 0.14), Color(0.3, 0.3, 0.22), Color(0.5, 0.4, 0.22),
		Color(0.26, 0.2, 0.16), Color(0.55, 0.5, 0.38), Color(0.36, 0.18, 0.12),
	],
}
