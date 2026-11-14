extends RefCounted
## Spike of #193 (the isometric 3D render): the showroom's tunables in one place. Production code
## has none of this yet; the later jobs move what the spike picks into static holders (ADR 0003).

## 3D units per 2D pixel: the one scale of the mirror, (x, y) -> (x, 0, y) * UNIT.
const UNIT := 1.0
## The camera pitches the showroom compares (degrees of elevation): 2:1 dimetric (the pixel-art
## staple), the ticket's "about 30", and the true isometric the default picks.
const PITCH_DIMETRIC := 26.565
const PITCH_THIRTY := 30.0
const PITCH_ISOMETRIC := 35.264
const YAW_START := 45.0
## Held Q / E turns the camera this many degrees a second.
const TURN_SPEED := 90.0
## Heights (3D units) of what a 2D body mirrors as: walls full height, a door's leaf, a standing
## character, and the clamp of a piece of furniture (taller where a name says so).
const WALL_HEIGHT := 96.0
const DOOR_HEIGHT := 84.0
const CHARACTER_HEIGHT := 58.0
const FURNITURE_MIN := 22.0
const FURNITURE_MAX := 70.0
## The camera's distance from its focus along its axis, and the clip range around it.
const CAMERA_DISTANCE := 900.0
const CAMERA_NEAR := 300.0
const CAMERA_FAR := 1500.0
## The pixel posts: internal height (lines; 0 = the window's, smooth and unposted), tone bands
## (0 = a smooth ramp), outline thickness in internal pixels (0 = none), the depth step and the
## normal step that draw an outline.
const POSTS := {
	"raw": {
		"title": "Raw 3D", "lines": 0, "bands": 0, "outline": 0.0, "depth": 0.0, "normal": 0.0,
		"note": "full-resolution smooth shading, no outline: what the plain 3D look is",
	},
	"A": {
		"title": "Post A", "lines": 216, "bands": 3, "outline": 1.0, "depth": 0.004,
		"normal": 0.45, "note": "216 lines (3x at 1152x648), 3 tone bands, 1 px outline",
	},
	"B": {
		"title": "Post B", "lines": 162, "bands": 4, "outline": 1.0, "depth": 0.004,
		"normal": 0.45, "note": "162 lines (4x, chunkier), 4 tone bands, 1 px outline",
	},
	"C": {
		"title": "Post C", "lines": 324, "bands": 3, "outline": 2.0, "depth": 0.004,
		"normal": 0.45, "note": "324 lines (2x, fine), 3 tone bands, 2 px heavy outline",
	},
}
## The sets the showroom steps through, in picker order: a post and a pitch each.
const SETS := [
	{ "post": "raw", "pitch": PITCH_ISOMETRIC },
	{ "post": "A", "pitch": PITCH_ISOMETRIC },
	{ "post": "A", "pitch": PITCH_THIRTY },
	{ "post": "A", "pitch": PITCH_DIMETRIC },
	{ "post": "B", "pitch": PITCH_ISOMETRIC },
	{ "post": "C", "pitch": PITCH_ISOMETRIC },
]


## The set's title for the label: "Post A, pitch 35.3 deg".
static func title_of(set_index: int) -> String:
	var row: Dictionary = SETS[set_index]
	return "%s, pitch %.1f°" % [POSTS[row["post"]]["title"], row["pitch"]]


## The tone ramp the toon shader steps through, from `ArtSurfaceConfig.tones`: each entry
## `(mul, lift)` gives `base * mul + (1 - base) * lift` (a darkened tone is a multiplier, a
## lightened one a lift), in the order shadow, dark, base, light, highlight.
static func ramp() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(1.0 - ArtSurfaceConfig.tone_shadow, 0.0),
		Vector2(1.0 - ArtSurfaceConfig.tone_dark, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, ArtSurfaceConfig.tone_light),
		Vector2(1.0, ArtSurfaceConfig.tone_highlight),
	])
