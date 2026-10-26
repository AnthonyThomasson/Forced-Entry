class_name ObjectArtLightConfig
## What a piece gives as light (interface 20; object_lights.gd, read by the Lighting domain): the
## light specs per kind, a cheap screen's glow, the neon pair and the neon share. A `class_name`
## holder of `static var`s, read as `ObjectArtLightConfig.<name>`; there is no instance and no
## autoload.

## One row per kind of light a piece gives: its `energy`, its pool's `radius` (px, out along the
## pool's long axis; a `wide` pool is half as deep, a `tube` a third), `shape` (`round`, `wide`: a
## screen's spill across its front, `tube`: along a neon tube), how far `ahead` (px) of the piece's
## front edge it stands (a screen's spill; none: the piece's centre), the rhythms it is drawn from
## by weight (`[[mode, weight], ...]`: steady, buzz, failing, blink, shimmer, pulse), `room_light`
## (it lights its room, so the room needs no ceiling fixture) and `height` (`overhead`: above the
## heads, a lamp's bulb, a street lamp's head, shadowed by the walls only and pooling downward;
## `low` when absent: shadowed by the walls and the tall pieces). Its colour is what the piece draws
## glowing (its neon, its screen, its bulb). `trim` is a piece's neon trim or under-glow; a tube's
## `radius` is its length × `tube_reach`.
static var specs: Dictionary = {
	"lamp": {
		"energy": 0.95, "radius": 160.0, "shape": &"round", "height": &"overhead",
		"rhythm": [[&"steady", 6.0], [&"buzz", 1.5], [&"pulse", 1.0], [&"failing", 1.5]],
		"room_light": true,
	},
	"tv": {
		"energy": 0.8,
		"radius": 110.0,
		"shape": &"wide",
		"ahead": 26.0,
		"rhythm": [[&"shimmer", 1.0]],
	},
	"desk": {
		"energy": 0.6,
		"radius": 105.0,
		"shape": &"wide",
		"ahead": -12.0,
		"rhythm": [[&"shimmer", 1.0]],
	},
	"monitor_wall": {
		"energy": 0.9,
		"radius": 128.0,
		"shape": &"wide",
		"ahead": 30.0,
		"rhythm": [[&"shimmer", 1.0]],
	},
	"server_rack": {
		"energy": 0.5,
		"radius": 65.0,
		"shape": &"round",
		"ahead": 8.0,
		"rhythm": [[&"blink", 1.0], [&"pulse", 1.0]],
	},
	"rig": { "energy": 0.4, "radius": 80.0, "shape": &"round", "rhythm": [[&"shimmer", 1.0]] },
	"surgical": {
		"energy": 1.1, "radius": 160.0, "shape": &"round", "height": &"overhead",
		"rhythm": [[&"steady", 1.0]], "room_light": true,
	},
	"tool_cart": {
		"energy": 0.4,
		"radius": 60.0,
		"shape": &"round",
		"rhythm": [[&"shimmer", 1.0]],
	},
	"scanner": {
		"energy": 0.6,
		"radius": 90.0,
		"shape": &"wide",
		"ahead": 9.0,
		"rhythm": [[&"pulse", 1.0]],
	},
	"hotplate": { "energy": 0.6, "radius": 60.0, "shape": &"round", "rhythm": [[&"pulse", 1.0]] },
	"neon_tube": {
		"energy": 0.85, "tube_reach": 1.7, "shape": &"tube",
		"rhythm": [[&"steady", 4.0], [&"failing", 3.5], [&"buzz", 2.5]],
	},
	"cobra": {
		"energy": 1.0, "radius": 130.0, "shape": &"round", "height": &"overhead",
		"rhythm": [[&"steady", 3.0], [&"failing", 1.0]],
	},
	"sign": {
		"energy": 1.0, "radius": 130.0, "shape": &"round", "height": &"overhead",
		"rhythm": [[&"blink", 3.0], [&"buzz", 2.0]],
	},
	"trim": {
		"energy": 0.45,
		"radius": 45.0,
		"shape": &"round",
		"rhythm": [[&"steady", 4.0], [&"buzz", 1.0]],
	},
}
## The glow of a cheap screen (a TV, a monitor, an appliance's display) without a neon of its own.
static var decay_screen_color: Color = Color(0.45, 0.95, 0.42)
## The neon pair: a piece with a `neon` option takes a trim or screen in one of them.
static var neon_cyan: Color = Color(0.15, 0.92, 1.0)
static var neon_magenta: Color = Color(1.0, 0.2, 0.72)
## The share of each kind of light-giving piece that takes a neon trim or screen
## (`ObjectArt.neon_for`): `tv` an appliance with a TV panel, `desk` a table with a monitor on it,
## the new rooms' pieces by their `kind` (`monitor_wall`, `server_rack`, `rig`, `tool_cart`), the
## rest by their painter id. A kind not listed never does.
static var neon_share: Dictionary = {
	"tv": 0.6, "desk": 0.5, "lamp": 0.45, "fixture": 0.5, "counter": 0.35, "cabinet": 0.3,
	"shelf": 0.35, "bed": 0.3, "appliance": 0.25, "monitor_wall": 0.6, "server_rack": 0.5,
	"rig": 0.6, "tool_cart": 0.4,
}
