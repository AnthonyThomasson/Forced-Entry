class_name SoundImpacts
## Audio domain: the impacts, one family of the sound library (SoundBank): a bullet or a fist
## striking a material. A profile is `impact/<material>/<outcome>/<band>` (outcome `blocked`,
## `penetrate` or `ricochet`, the band the round's weight, `SoundBank.band`) or
## `impact/<material>/punch`. `profile` names one without rendering it; the bank renders and caches
## it, asking `recipe` for its recipe. Its `MATERIALS` are also what a vehicle's crash strikes
## (SoundBank's crashes).

## Penetration outcomes a bullet impact is voiced for (a punch is its own thing).
const OUTCOMES: Array[StringName] = [&"blocked", &"penetrate", &"ricochet"]
## How a projectile's weight colours an impact: crack loudness, pitch scale (heavier = lower), a
## level trim in dB, how much low body it carries (`body`: the thump every hit has) and `sub`: an
## extra deep boom under it that only the heavier rounds have.
const BANDS := {
	"light": { "crack": 0.55, "pitch": 1.15, "db": -4.0, "body": 0.8, "sub": 0.0 },
	"medium": { "crack": 1.0, "pitch": 1.0, "db": 0.0, "body": 1.0, "sub": 0.35 },
	"heavy": { "crack": 1.4, "pitch": 0.78, "db": 4.0, "body": 1.7, "sub": 0.8 },
}
## What a struck material sounds like. hard = rings and throws a bullet back with a ping (soft
## materials whip instead); thump = how much low body a hit has (0 = none, 1 = all); modes / amps /
## decays = the partials it rings at (Hz, relative level, decay s); lp = the cut-off of its noise
## (Hz); grit = how long the crack of the hit lasts (s); heft = optional extra weight (default 0):
## more low body, a longer thud, the struck ring turned down (a ricochet still rings); db = its
## level trim (the synth normalizes every sound, so quiet materials say so here).
const MATERIALS := {
	"wood": {
		"hard": false, "db": 0.0, "thump": 0.6, "modes": [210.0, 380.0, 690.0],
		"amps": [1.0, 0.6, 0.4], "decays": [0.045, 0.03, 0.02], "lp": 2800.0, "grit": 0.020,
	},
	"metal": {
		"hard": true, "db": 2.0, "thump": 0.15, "heft": 0.9,
		"modes": [620.0, 1480.0, 2330.0, 3410.0], "amps": [1.0, 0.8, 0.6, 0.4],
		"decays": [0.22, 0.18, 0.14, 0.10], "lp": 7000.0, "grit": 0.008,
	},
	"glass": {
		"hard": true, "db": 0.0, "thump": 0.05, "modes": [1900.0, 3100.0, 4700.0],
		"amps": [1.0, 0.7, 0.5], "decays": [0.16, 0.12, 0.09], "lp": 9500.0, "grit": 0.006,
	},
	"ceramic": {
		"hard": true, "db": 0.0, "thump": 0.2, "modes": [950.0, 1900.0, 2900.0],
		"amps": [1.0, 0.7, 0.45], "decays": [0.09, 0.07, 0.05], "lp": 7000.0, "grit": 0.010,
	},
	"composite": {
		"hard": true, "db": 0.0, "thump": 0.55, "modes": [380.0, 820.0, 1450.0],
		"amps": [1.0, 0.55, 0.3], "decays": [0.05, 0.035, 0.025], "lp": 4200.0, "grit": 0.014,
	},
	"stone": {
		"hard": true, "db": 0.0, "thump": 0.4, "modes": [420.0, 880.0, 1500.0],
		"amps": [1.0, 0.6, 0.4], "decays": [0.06, 0.045, 0.03], "lp": 6000.0, "grit": 0.014,
	},
	"plastic": {
		"hard": false, "db": -2.0, "thump": 0.35, "modes": [330.0, 720.0], "amps": [1.0, 0.5],
		"decays": [0.04, 0.03], "lp": 3500.0, "grit": 0.012,
	},
	"fabric": {
		"hard": false, "db": -4.0, "thump": 0.8, "modes": [110.0, 190.0], "amps": [1.0, 0.5],
		"decays": [0.03, 0.02], "lp": 900.0, "grit": 0.025,
	},
	"foliage": {
		"hard": false,
		"db": -5.0,
		"thump": 0.1,
		"modes": [],
		"amps": [],
		"decays": [],
		"lp": 2400.0,
		"grit": 0.060,
	},
	"electronics": {
		"hard": true, "db": 0.0, "thump": 0.2, "modes": [780.0, 1700.0, 2900.0],
		"amps": [1.0, 0.7, 0.5], "decays": [0.07, 0.05, 0.04], "lp": 5500.0, "grit": 0.010,
	},
	"flesh": {
		"hard": false, "db": -1.0, "thump": 1.0, "modes": [95.0, 160.0], "amps": [1.0, 0.6],
		"decays": [0.05, 0.035], "lp": 1300.0, "grit": 0.030,
	},
	"wall": {
		"hard": true, "db": 0.0, "thump": 0.5, "modes": [150.0, 300.0, 520.0],
		"amps": [1.0, 0.6, 0.4], "decays": [0.04, 0.03, 0.02], "lp": 3200.0, "grit": 0.025,
	},
	"default": {
		"hard": false, "db": 0.0, "thump": 0.4, "modes": [260.0, 540.0], "amps": [1.0, 0.5],
		"decays": [0.04, 0.03], "lp": 3000.0, "grit": 0.015,
	},
}


## The impact profile for a hit on `material` with `outcome` (`blocked` / `penetrate` / `ricochet` /
## `punch`) by a projectile of `power`; &"" when `outcome` is none of those.
static func profile(material: String, outcome: StringName, power: float = 1.0) -> StringName:
	var mat := "wall" if material == "" else (material if MATERIALS.has(material) else "default")
	if outcome == &"punch":
		return StringName("impact/%s/punch" % mat)
	if not OUTCOMES.has(outcome):
		return &""
	return StringName("impact/%s/%s/%s" % [mat, outcome, SoundBank.band(power)])


## The impact profiles, in the library's order (the bank's `profiles` holds them): per material,
## its punch, then each outcome in each band.
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	for mat: String in MATERIALS:
		out.append(StringName("impact/%s/punch" % mat))
		for outcome in OUTCOMES:
			for b in SoundBank.BAND_NAMES:
				out.append(StringName("impact/%s/%s/%s" % [mat, outcome, b]))
	return out


## The recipe of an `impact/...` profile (`p`, split), {} if unknown.
static func recipe(p: PackedStringArray) -> Dictionary:
	if p.size() == 3 and p[2] == "punch" and MATERIALS.has(p[1]):
		return _impact(p[1], "punch", "medium")
	if (p.size() == 4
			and MATERIALS.has(p[1])
			and OUTCOMES.has(StringName(p[2]))
			and BANDS.has(p[3])):
		return _impact(p[1], p[2], p[3])
	return {}


## The recipe of a hit on `material` with `outcome` by a round of weight `band_id`: the material's
## ring, the crack, the low body thump every hit has, and what the outcome adds (a crunch through, a
## ping or whine off).
static func _impact(material: String, outcome: String, band_id: String) -> Dictionary:
	var m: Dictionary = MATERIALS[material]
	var b: Dictionary = BANDS[band_id]
	var s := _strike(b, m, outcome)
	var layers := []
	var length := _impact_ring(layers, m, s, outcome)
	var crack: float = s["crack"]
	var grit: float = m["grit"]
	var lp: float = m["lp"]
	layers.append({
		"type": "noise", "gain": (0.35 if outcome == "punch" else 0.7) * crack,
		"decay": grit + 0.004, "lp": lp, "hp": 120.0, "attack": 0.0004,
	})
	length = maxf(length, _impact_weight(layers, m, s))
	match outcome:
		"penetrate":
			length = maxf(length, _impact_through(layers, m, s))
		"ricochet":
			length = maxf(length, _impact_ricochet(layers, m["hard"], s))
		"punch":
			if material == "flesh":
				layers.append({
					"type": "noise", "gain": 0.5, "decay": 0.018, "lp": 3500.0, "hp": 600.0,
				})
	return {
		"length": clampf(length, 0.12, 0.9),
		"level_db": (-6.0 if outcome == "punch" else float(b["db"])) + float(m["db"]),
		"layers": layers,
	}


## How a round of band `b` (or a fist, `outcome` "punch") strikes material `m`: its `pitch`,
## `crack`, `body` and `sub` (the band's, or a punch's own), and the material's `heft` (none for a
## punch).
static func _strike(b: Dictionary, m: Dictionary, outcome: String) -> Dictionary:
	if outcome == "punch":
		return { "pitch": 1.0, "crack": 1.0, "body": 0.8, "sub": 0.0, "heft": 0.0 }
	return {
		"pitch": float(b["pitch"]), "crack": float(b["crack"]), "body": float(b["body"]),
		"sub": float(b["sub"]), "heft": float(m.get("heft", 0.0)),
	}


## Add the ring of material `m` struck as `s` (a `_strike`) in `outcome` to `layers`; returns the
## clip length it needs (at least 0.12 s).
static func _impact_ring(layers: Array, m: Dictionary, s: Dictionary, outcome: String) -> float:
	var hard: bool = m["hard"]
	var heft: float = s["heft"]
	var pitch: float = s["pitch"]
	# How hard the material rings in this outcome: a ricochet off something hard keeps ringing, one
	# off something soft barely does, a punch only taps it.
	var ring_gain := 0.35
	var ring_time := 1.0
	match outcome:
		"penetrate":
			ring_gain = 0.28
			ring_time = 0.8
		"ricochet":
			ring_gain = 1.0 if hard else 0.45
			ring_time = 1.6 if hard else 0.8
		"punch":
			ring_gain = 0.4
	if hard and outcome != "ricochet":
		ring_gain *= 0.7  # a hard thing struck without glancing off rings less than it thuds
		ring_gain *= 1.0 - 0.35 * heft
	var length := 0.12
	var freqs: Array = []
	var decays: Array = []
	# The rings take only half the band's pitch shift: a light round must not turn a hard material
	# into a tinkle.
	var ring_pitch := 1.0 + (pitch - 1.0) * 0.5
	for f: float in m["modes"]:
		freqs.append(f * ring_pitch)
	for d: float in m["decays"]:
		decays.append(d * ring_time)
		length = maxf(length, d * ring_time * 4.0 + 0.04)
	if not freqs.is_empty():
		layers.append({
			"type": "modes",
			"gain": ring_gain,
			"freqs": freqs,
			"amps": m["amps"],
			"decays": decays,
			"detune": 0.03,
		})
	return length


## Add the weight every hit has, whatever it struck, to `layers`: a low thump (the material `m`
## only decides how much of it), and under a heavier round (`s`, a `_strike`) a deep boom as well.
## This is what makes a strong hit land as one rather than ring thinly. Returns the clip length the
## boom needs (0 without one).
static func _impact_weight(layers: Array, m: Dictionary, s: Dictionary) -> float:
	var thump: float = m["thump"]
	var pitch: float = s["pitch"]
	var body: float = s["body"]
	var heft: float = s["heft"]
	var sub: float = s["sub"]
	layers.append({
		"type": "tone", "gain": (0.65 + 0.35 * thump) * body * (1.0 + 0.8 * heft),
		"freq": 150.0 * pitch, "freq_end": 55.0 * pitch, "sweep": 0.018,
		"decay": 0.06 + 0.03 * thump + 0.03 * body + 0.04 * heft,
	})
	if sub <= 0.0:
		return 0.0
	layers.append({
		"type": "tone", "gain": sub * (0.8 + 0.4 * thump), "freq": 72.0 * pitch,
		"freq_end": 40.0 * pitch, "sweep": 0.03, "decay": 0.07 + 0.05 * sub,
	})
	return 0.14 + 0.06 * sub


## Add what a round (`s`, a `_strike`) going through material `m` adds to `layers`: a crunch of what
## it broke, a hiss of air behind it, a deeper thud. Returns the clip length it needs.
static func _impact_through(layers: Array, m: Dictionary, s: Dictionary) -> float:
	var crack: float = s["crack"]
	var pitch: float = s["pitch"]
	var grit: float = m["grit"]
	var lp: float = m["lp"]
	var thump: float = m["thump"]
	layers.append({
		"type": "noise", "gain": 0.6 * crack, "decay": grit * 2.0 + 0.01, "lp": lp * 0.7,
		"hp": 120.0, "delay": 0.004, "attack": 0.001,
	})
	layers.append({
		"type": "noise", "gain": 0.15 * crack, "decay": 0.05, "lp": 7000.0, "hp": 2500.0,
		"delay": 0.012, "attack": 0.004,
	})
	layers.append({
		"type": "tone", "gain": 0.35 + 0.4 * thump, "freq": 120.0 * pitch,
		"freq_end": 48.0 * pitch, "sweep": 0.02, "decay": 0.08, "delay": 0.006,
	})
	return 0.22


## Add what a round (`s`, a `_strike`) glancing off adds to `layers`: a sharp tick, then off a
## `hard` material its whine, else a whip. Returns the clip length it needs.
static func _impact_ricochet(layers: Array, hard: bool, s: Dictionary) -> float:
	var crack: float = s["crack"]
	var pitch: float = s["pitch"]
	layers.append({
		"type": "noise",
		"gain": 0.5 * crack,
		"decay": 0.005,
		"lp": 9500.0,
		"hp": 2500.0,
	})
	if hard:
		# The whine of a spinning, flattened round: high, falling.
		layers.append({
			"type": "tone", "gain": 0.35, "freq": 4300.0 * pitch,
			"freq_end": 1500.0 * pitch, "sweep": 0.11, "decay": 0.22,
		})
		return 0.7
	layers.append({
		"type": "noise",
		"gain": 0.5 * crack,
		"decay": 0.05,
		"lp": 9000.0,
		"hp": 2500.0,
		"attack": 0.003,
	})
	return 0.2
