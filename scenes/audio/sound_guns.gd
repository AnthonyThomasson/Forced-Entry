class_name SoundGuns
## Audio domain: the guns, one family of the sound library (SoundBank): a gun's report and its
## reload. A profile is `shot/<gun>` or `reload/<gun>/<out|in>`, the gun a GunConfig id (`pistol`,
## `smg`, `rifle`); an unknown gun is voiced as the gun of its round's band (`SoundBank.band`).
## `shot_profile` and `reload_profile` name one without rendering it; the bank renders and caches
## it, asking `recipe` for its recipe.

## The shot recipe an unlisted gun borrows, by band.
const BAND_SHOT := { "light": "smg", "medium": "pistol", "heavy": "rifle" }
## Reloads, by gun: pitch scales every click (heavier = lower), db trims the level, seat = the pitch
## (Hz) of the faint tick under the magazine seating click, rack = seconds from the magazine seating
## to the action being racked.
const RELOADS := {
	"pistol": { "pitch": 1.0, "db": 0.0, "seat": 190.0, "rack": 0.30 },
	"smg": { "pitch": 1.1, "db": -1.0, "seat": 210.0, "rack": 0.30 },
	"rifle": { "pitch": 0.85, "db": 2.0, "seat": 150.0, "rack": 0.42 },
}
const RELOAD_STAGES: Array[String] = ["out", "in"]
## Gunshots. crack / bark = [decay s, low-pass Hz, gain] of the sharp snap and the mid-range bark;
## body = [start Hz, end Hz, decay s, gain] of the low thump that drops in pitch; tail = [decay s,
## low-pass Hz, gain] of the room's tail.
const SHOTS := {
	"pistol": {
		"length": 0.42, "level_db": 0.0, "crack": [0.011, 7500.0, 1.0],
		"bark": [0.030, 3200.0, 0.55], "body": [175.0, 58.0, 0.10, 0.85],
		"tail": [0.13, 1700.0, 0.35],
	},
	"smg": {
		"length": 0.28, "level_db": -3.0, "crack": [0.008, 9000.0, 1.0],
		"bark": [0.020, 3800.0, 0.50], "body": [210.0, 85.0, 0.055, 0.70],
		"tail": [0.07, 2100.0, 0.28],
	},
	"rifle": {
		"length": 0.80, "level_db": 2.0, "crack": [0.016, 9500.0, 1.2],
		"bark": [0.045, 2800.0, 0.70], "body": [125.0, 42.0, 0.15, 1.00],
		"tail": [0.26, 1300.0, 0.50],
	},
}


## The shot profile of `gun`; a gun without its own recipe borrows its band's from `power`.
static func shot_profile(gun: StringName, power: float = 1.0) -> StringName:
	var id := String(gun)
	if not SHOTS.has(id):
		id = BAND_SHOT[SoundBank.band(power)]
	return StringName("shot/" + id)


## The reload profile for `gun` at `stage` (&"out" or &"in"); a gun without its own recipe borrows
## its band's from `power`. &"" when `stage` is neither.
static func reload_profile(gun: StringName, stage: StringName, power: float = 1.0) -> StringName:
	if not RELOAD_STAGES.has(String(stage)):
		return &""
	var id := String(gun)
	if not RELOADS.has(id):
		id = BAND_SHOT[SoundBank.band(power)]
	return StringName("reload/%s/%s" % [id, stage])


## The gun profiles, in the library's order (the bank's `profiles` holds them): every shot, then
## every reload.
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	for gun: String in SHOTS:
		out.append(StringName("shot/" + gun))
	for gun: String in RELOADS:
		for stage in RELOAD_STAGES:
			out.append(StringName("reload/%s/%s" % [gun, stage]))
	return out


## The recipe of a `shot/...` or `reload/...` profile split into its `parts`; {} if it names no
## sound.
static func recipe(parts: PackedStringArray) -> Dictionary:
	if parts[0] == "shot":
		return _shot(parts[1]) if parts.size() == 2 and SHOTS.has(parts[1]) else {}
	if parts.size() == 3 and RELOADS.has(parts[1]) and RELOAD_STAGES.has(parts[2]):
		return _reload(parts[1], parts[2])
	return {}


## The recipe of `gun`'s report: the sharp crack, the mid-range bark, the low body thump and the
## room's tail.
static func _shot(gun: String) -> Dictionary:
	var g: Dictionary = SHOTS[gun]
	var crack: Array = g["crack"]
	var bark: Array = g["bark"]
	var body: Array = g["body"]
	var tail: Array = g["tail"]
	return {
		"length": g["length"], "level_db": g["level_db"], "drive": 2.0,
		"layers": [
			{
				"type": "noise",
				"gain": crack[2],
				"decay": crack[0],
				"lp": crack[1],
				"hp": 500.0,
				"attack": 0.0003,
			},
			{
				"type": "noise",
				"gain": bark[2],
				"decay": bark[0],
				"lp": bark[1],
				"hp": 150.0,
				"attack": 0.0006,
			},
			{
				"type": "tone",
				"gain": body[3],
				"freq": body[0],
				"freq_end": body[1],
				"sweep": 0.025,
				"decay": body[2],
			},
			{
				"type": "noise",
				"gain": tail[2],
				"decay": tail[0],
				"lp": tail[1],
				"hp": 120.0,
				"delay": 0.012,
				"attack": 0.006,
			},
		],
	}


## A reload in two beats, each kept to dry, quiet clicks. `out`: the release click and a faint tick
## of the magazine dropping free. `in`: a seat click, then a rack click.
static func _reload(gun: String, stage: String) -> Dictionary:
	var g: Dictionary = RELOADS[gun]
	var p: float = g["pitch"]
	var out := stage == "out"
	return {
		"length": 0.22 if out else 0.09 + float(g["rack"]) + 0.1,
		"level_db": float(g["db"]) + (-6.0 if out else -4.0),
		"vary": 0.06,
		"layers": _reload_out(p) if out else _reload_in(g, p),
	}


## A magazine going out at pitch `p`: one dry click as the catch lets go, and a faint tick of the
## magazine dropping free.
static func _reload_out(p: float) -> Array:
	return [
		{
			"type": "noise",
			"gain": 0.8,
			"decay": 0.004,
			"lp": 5000.0 * p,
			"hp": 1800.0,
			"attack": 0.0002,
		},
		{
			"type": "tone",
			"gain": 0.15,
			"freq": 140.0 * p,
			"freq_end": 90.0 * p,
			"sweep": 0.012,
			"decay": 0.025,
			"delay": 0.14,
		},
		{
			"type": "noise", "gain": 0.2, "decay": 0.008, "lp": 2500.0, "hp": 400.0,
			"delay": 0.14,
		},
	]


## A magazine of reload row `g` coming in at pitch `p`: two small clicks, the magazine seating, then
## the action racked. No rasp, ring or slam.
static func _reload_in(g: Dictionary, p: float) -> Array:
	var rack: float = g["rack"]
	return [
		{
			"type": "noise",
			"gain": 0.5,
			"decay": 0.007,
			"lp": 3800.0 * p,
			"hp": 1200.0,
			"delay": 0.09,
			"attack": 0.0003,
		},
		{
			"type": "tone", "gain": 0.12, "freq": float(g["seat"]),
			"freq_end": float(g["seat"]) * 0.6, "sweep": 0.01, "decay": 0.02, "delay": 0.09,
		},
		{
			"type": "noise",
			"gain": 0.6,
			"decay": 0.009,
			"lp": 4000.0 * p,
			"hp": 900.0,
			"delay": 0.09 + rack,
			"attack": 0.0003,
		},
	]
