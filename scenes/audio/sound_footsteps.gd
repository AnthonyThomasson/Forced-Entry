class_name SoundFootsteps
## Audio domain: the footsteps, one family of the sound library (SoundBank). A profile is
## `footstep/<surface>/<walk|run>`, the surface the floor underfoot (SoundSurface: wood tile stone
## concrete carpet outdoor). `profile` names one without rendering it; the bank renders and caches
## it, asking `recipe` for its recipe.

## Footsteps by surface, all deliberately low and dull (high-passed noise and ring tones sound
## tinny): the heel thump leads, the scuff is a soft low-passed noise. db = level trim, thump =
## [start Hz, end Hz, decay s, gain] (the heel), scuff = [low-pass Hz, high-pass Hz, decay s, gain]
## (the sole on the surface), ring = { freqs, amps, decays, gain } (a hard floor's click), again = a
## second, softer scuff that follows (gravel, grass).
const SURFACES := {
	"wood": {
		"db": -3.0,
		"thump": [102.0, 56.0, 0.052, 1.0],
		"scuff": [1300.0, 140.0, 0.020, 0.34],
	},
	"tile": {
		"db": -3.0,
		"thump": [112.0, 66.0, 0.042, 1.0],
		"scuff": [1300.0, 180.0, 0.015, 0.30],
	},
	"stone": {
		"db": -3.0,
		"thump": [115.0, 72.0, 0.034, 1.0],
		"scuff": [1300.0, 200.0, 0.016, 0.32],
	},
	"concrete": {
		"db": 0.0,
		"thump": [105.0, 64.0, 0.030, 1.0],
		"scuff": [2000.0, 220.0, 0.020, 0.45],
	},
	"carpet": {
		"db": -6.0,
		"thump": [95.0, 62.0, 0.030, 0.65],
		"scuff": [750.0, 0.0, 0.030, 0.45],
	},
	"outdoor": {
		"db": -2.0,
		"thump": [90.0, 58.0, 0.040, 0.9],
		"scuff": [1600.0, 180.0, 0.040, 0.5],
		"again": 0.028,
	},
}


## The footstep profile on `surface` (a SoundSurface name); an unknown surface is the open ground.
static func profile(surface: StringName, running: bool) -> StringName:
	var s := String(surface) if SURFACES.has(String(surface)) else "outdoor"
	return StringName("footstep/%s/%s" % [s, "run" if running else "walk"])


## The footstep profiles, in the library's order (the bank's `profiles` holds them).
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	for surface: String in SURFACES:
		out.append(StringName("footstep/%s/walk" % surface))
		out.append(StringName("footstep/%s/run" % surface))
	return out


## The recipe of a footstep profile split into its `parts` (`footstep`, surface, gait); {} if it
## names no step.
static func recipe(parts: PackedStringArray) -> Dictionary:
	if parts.size() == 3 and SURFACES.has(parts[1]) and (parts[2] == "walk" or parts[2] == "run"):
		return _footstep(parts[1], parts[2] == "run")
	return {}


## The recipe of a step on `surface`: the heel thump, a softer toe tap after it, the scuff and a
## faint cloth rustle.
static func _footstep(surface: String, running: bool) -> Dictionary:
	var s: Dictionary = SURFACES[surface]
	var thump: Array = s["thump"]
	var scuff: Array = s["scuff"]
	var punch := 1.2 if running else 1.0
	var quick := 0.85 if running else 1.0
	var pitch := 1.08 if running else 1.0
	# A step is two beats, not one: the heel lands, then the ball of the foot and toes tap down a
	# few ms later (sooner and flatter at a run). The toe is a little higher, shorter and softer
	# than the heel, in the same dull tone.
	var toe_at := 0.045 if running else 0.062
	var layers := [
		{ "type": "tone", "gain": thump[3] * punch, "freq": thump[0] * pitch,
			"freq_end": thump[1] * pitch, "sweep": 0.015, "decay": thump[2] * quick },
		{ "type": "noise", "gain": scuff[3] * punch, "lp": scuff[0], "hp": scuff[1],
			"decay": scuff[2] * quick, "attack": 0.0006 },
		{ "type": "tone", "gain": thump[3] * 0.4 * punch, "freq": thump[0] * 1.2 * pitch,
			"freq_end": thump[1] * 1.15 * pitch, "sweep": 0.01, "decay": thump[2] * 0.7 * quick,
			"delay": toe_at },
		{ "type": "noise", "gain": scuff[3] * 0.5 * punch, "lp": scuff[0], "hp": scuff[1],
			"decay": scuff[2] * 0.7 * quick, "delay": toe_at, "attack": 0.001 },
		# Cloth and the weight shifting: a faint low rustle under the whole step.
		{ "type": "noise", "gain": 0.1 * float(s.get("rustle", 1.0)), "lp": 1400.0, "hp": 250.0,
			"decay": 0.09, "delay": 0.012, "attack": 0.02 },
	]
	var length: float = maxf(thump[2], scuff[2]) * 6.0
	length = maxf(length, toe_at + scuff[2] * 5.0)
	if s.has("ring"):
		var ring: Dictionary = s["ring"]
		layers.append({
			"type": "modes", "gain": ring["gain"] * punch, "freqs": ring["freqs"],
			"amps": ring["amps"], "decays": ring["decays"], "detune": 0.03,
		})
		for d: float in ring["decays"]:
			length = maxf(length, d * 5.0)
	if s.has("again"):
		layers.append({
			"type": "noise", "gain": scuff[3] * 0.6 * punch, "lp": scuff[0] * 0.8, "hp": scuff[1],
			"decay": scuff[2] * quick, "delay": s["again"], "attack": 0.001,
		})
		length += float(s["again"])
	return {
		"length": clampf(length, 0.1, 0.4),
		"level_db": (-1.0 if running else -5.0) + float(s["db"]), "vary": 0.22, "layers": layers,
	}
