extends RefCounted
## The three style families the prop sets (sidewalk clutter, shop, noodle bar, stockroom) share, so
## variant A / B / C of every set reads as one look: A grimy steel, B neon-lit, C painted municipal.

const Kit := preload("res://sandboxes/showroom/downtown_district/paint_kit.gd")
const NAMES := { "a": "Grimy steel", "b": "Neon-lit", "c": "Painted municipal" }
const FAMILIES := {
	"a": {
		"body": Color(0.46, 0.47, 0.45), "top": Color(0.58, 0.58, 0.55),
		"accent": Color(0.62, 0.34, 0.17), "glass": Color(0.3, 0.4, 0.42),
		"wood": Color(0.5, 0.38, 0.24), "neon": Color(0, 0, 0, 0), "neon2": Color(0, 0, 0, 0),
		"dirt": 1.0,
	},
	"b": {
		"body": Color(0.16, 0.15, 0.21), "top": Color(0.23, 0.22, 0.3),
		"accent": Kit.NEON_CYAN, "glass": Color(0.1, 0.32, 0.38),
		"wood": Color(0.12, 0.11, 0.16), "neon": Kit.NEON_CYAN, "neon2": Kit.NEON_MAGENTA,
		"dirt": 0.5,
	},
	"c": {
		"body": Color(0.3, 0.48, 0.4), "top": Color(0.4, 0.58, 0.5),
		"accent": Color(0.92, 0.86, 0.66), "glass": Color(0.74, 0.84, 0.8),
		"wood": Color(0.84, 0.74, 0.5), "neon": Color(0, 0, 0, 0), "neon2": Color(0, 0, 0, 0),
		"dirt": 0.3,
	},
}


## The family of `opts.look` (`a`, `b` or `c`; `a` for anything else).
static func of(opts: Dictionary) -> Dictionary:
	return FAMILIES.get(String(opts.get("look", "a")), FAMILIES["a"])


## Whether the family `fam` has a neon of its own.
static func is_neon(fam: Dictionary) -> bool:
	return (fam["neon"] as Color).a > 0.0


## The run-down finish of the family: grime and rust in proportion to its `dirt`.
static func finish(c: PixelCanvas, fam: Dictionary) -> void:
	var dirt: float = fam["dirt"]
	Kit.grime(c, maxi(1, int(c.w * c.h / 220.0 * dirt)), 5, 0.22)
	Kit.rust(c, int(c.w * c.h / 300.0 * dirt))
