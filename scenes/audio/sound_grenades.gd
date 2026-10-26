class_name SoundGrenades
## Audio domain: the grenades, one family of the sound library (SoundBank, `docs/grenades.md`): a
## grenade's throw, its bounce on the floor, its burst, and the whine a deafened listener hears. A
## profile is `throw/<kind>`, `grenade/<kind>/<surface>` (the floor it lands on, SoundSurface),
## `explosion/<kind>` (kind `stun` or `frag`) or `tinnitus/whine`. `throw_profile`,
## `bounce_profile`, `explosion_profile` and `tinnitus_profile` name one without rendering it; the
## bank renders and caches it, asking `recipe` for its recipe.

## The grenades (`docs/grenades.md`, G14). The kinds a profile may name:
const KINDS: Array[String] = ["stun", "frag"]
## The throw: the lever springs off with a metal ping (ping = [pitch scale, gain]: the stun's
## canister is lighter) and the arm whips the grenade away in a whoosh (whoosh = gain). db trims the
## level.
const THROWS := {
	"frag": { "db": -2.0, "ping": [1.0, 0.55], "whoosh": 1.0 },
	"stun": { "db": -3.0, "ping": [0.82, 0.4], "whoosh": 0.9 },
}
## The bursts. frag: a big, low blast with a long tail (a crack, the boom and the sub-bass under it,
## the roar and a rumble that rolls on, debris pattering down). stun: the opposite, a sharp, very
## loud bang that is over at once (a crack, a ringing shell of high partials and a short thump). db
## trims the level.
const EXPLOSIONS := {
	"frag": { "db": 2.0 },
	"stun": { "db": 3.0 },
}
## The body of a grenade: the partials it rings at when it strikes a floor (Hz, level, decay s). A
## frag is a heavier iron shell, a stun a thin aluminium canister.
const BODIES := {
	"frag": {
		"db": 0.0,
		"modes": [740.0, 1560.0, 2480.0],
		"amps": [1.0, 0.7, 0.45],
		"decays": [0.07, 0.05, 0.035],
	},
	"stun": {
		"db": -2.0,
		"modes": [1050.0, 2300.0, 3500.0],
		"amps": [1.0, 0.7, 0.5],
		"decays": [0.05, 0.035, 0.025],
	},
}
## What a floor does to a grenade landing on it, by SoundSurface name: db = level trim, thud =
## [start Hz, end Hz, decay s, gain] (the floor taking the weight), knock = [low-pass Hz, high-pass
## Hz, decay s, gain] (the crack of contact), ring = how much of the shell's ring survives (a hard
## floor leaves it, carpet and grass swallow it).
const SURFACES := {
	"wood": {
		"db": 0.0,
		"thud": [180.0, 90.0, 0.035, 0.9],
		"knock": [2200.0, 300.0, 0.012, 0.5],
		"ring": 0.6,
	},
	"tile": {
		"db": 2.0,
		"thud": [210.0, 110.0, 0.030, 0.6],
		"knock": [5000.0, 600.0, 0.008, 0.8],
		"ring": 1.0,
	},
	"stone": {
		"db": 2.0,
		"thud": [200.0, 100.0, 0.030, 0.7],
		"knock": [4200.0, 500.0, 0.009, 0.8],
		"ring": 0.9,
	},
	"concrete": {
		"db": 1.0,
		"thud": [170.0, 85.0, 0.030, 0.8],
		"knock": [3800.0, 400.0, 0.010, 0.7],
		"ring": 0.55,
	},
	"carpet": {
		"db": -8.0,
		"thud": [120.0, 70.0, 0.040, 0.8],
		"knock": [900.0, 0.0, 0.020, 0.3],
		"ring": 0.08,
	},
	"outdoor": {
		"db": -3.0,
		"thud": [140.0, 80.0, 0.040, 0.8],
		"knock": [1800.0, 200.0, 0.020, 0.45],
		"ring": 0.2,
	},
}
## The tinnitus whine is a seamless loop (the voice runs for as long as the listener is deaf): its
## tones are whole numbers of cycles in `TINNITUS_LOOP` s, the pair a few Hz apart beating against
## each other.
const TINNITUS_LOOP := 0.8
const TINNITUS_TONES := [[4300.0, 1.0], [4305.0, 0.9], [6850.0, 0.35]]


## The throw profile of a grenade of `kind`; &"" for an unknown kind.
static func throw_profile(kind: StringName) -> StringName:
	return StringName("throw/" + String(kind)) if THROWS.has(String(kind)) else &""


## The clatter profile of a grenade of `kind` landing on `surface` (a SoundSurface name; an unknown
## surface is the open ground); &"" for an unknown kind.
static func bounce_profile(kind: StringName, surface: StringName) -> StringName:
	if not BODIES.has(String(kind)):
		return &""
	var s := String(surface) if SURFACES.has(String(surface)) else "outdoor"
	return StringName("grenade/%s/%s" % [kind, s])


## The explosion profile of a burst of `kind`; &"" for an unknown kind.
static func explosion_profile(kind: StringName) -> StringName:
	return StringName("explosion/" + String(kind)) if EXPLOSIONS.has(String(kind)) else &""


## The whine a deafened listener hears.
static func tinnitus_profile() -> StringName:
	return &"tinnitus/whine"


## The grenade profiles, in the library's order (the bank's `profiles` holds them): per kind its
## throw, its burst and its bounce on each surface, then the whine.
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: String in KINDS:
		out.append(StringName("throw/" + kind))
		out.append(StringName("explosion/" + kind))
		for surface: String in SURFACES:
			out.append(StringName("grenade/%s/%s" % [kind, surface]))
	out.append(tinnitus_profile())
	return out


## The recipe of a `throw/...`, `grenade/...`, `explosion/...` or `tinnitus/...` profile split
## into its `parts`; {} if it names no sound.
static func recipe(parts: PackedStringArray) -> Dictionary:
	var out := {}
	var id := parts[1] if parts.size() == 2 else ""
	match parts[0]:
		"throw":
			if THROWS.has(id):
				out = _throw(id)
		"explosion":
			if EXPLOSIONS.has(id):
				out = _explosion(id)
		"tinnitus":
			if id == "whine":
				out = _tinnitus()
		"grenade":
			if parts.size() == 3 and BODIES.has(parts[1]) and SURFACES.has(parts[2]):
				out = _grenade(parts[1], parts[2])
	return out


## A grenade leaving the hand: the lever springs off with a ping and the arm whips it away in a
## rising whoosh.
static func _throw(kind: String) -> Dictionary:
	var t: Dictionary = THROWS[kind]
	var ping: Array = t["ping"]
	var scale: float = ping[0]
	var gain: float = t["whoosh"]
	return {
		"length": 0.45, "level_db": t["db"], "vary": 0.1,
		"layers": [
			{
				"type": "modes", "gain": ping[1],
				"freqs": [3300.0 * scale, 5100.0 * scale, 7400.0 * scale], "amps": [1.0, 0.6, 0.35],
				"decays": [0.05, 0.035, 0.02], "detune": 0.02,
			},
			{
				"type": "noise", "gain": gain, "attack": 0.10, "decay": 0.09, "lp": 2600.0,
				"hp": 600.0, "delay": 0.02,
			},
			{
				"type": "noise",
				"gain": gain * 0.5,
				"attack": 0.14,
				"decay": 0.12,
				"lp": 900.0,
				"hp": 150.0,
				"delay": 0.04,
			},
		],
	}


## A grenade of `kind` landing on `surface`: the floor's thud and the crack of contact, the shell's
## ring (as much as the floor leaves), and a smaller second tick as it rattles over.
static func _grenade(kind: String, surface: String) -> Dictionary:
	var b: Dictionary = BODIES[kind]
	var s: Dictionary = SURFACES[surface]
	return {
		"length": 0.4, "level_db": float(b["db"]) + float(s["db"]), "vary": 0.12,
		"layers": _grenade_contact(b, s) + _grenade_rattle(b, s),
	}


## A grenade of body `b` striking surface `s`: the floor's thud, the crack of contact and the
## shell's ring, as much as the floor leaves.
static func _grenade_contact(b: Dictionary, s: Dictionary) -> Array:
	var thud: Array = s["thud"]
	var knock: Array = s["knock"]
	var ring: float = s["ring"]
	return [
		{
			"type": "tone",
			"gain": thud[3],
			"freq": thud[0],
			"freq_end": thud[1],
			"sweep": 0.015,
			"decay": thud[2],
		},
		{
			"type": "noise",
			"gain": knock[3],
			"lp": knock[0],
			"hp": knock[1],
			"decay": knock[2],
			"attack": 0.0003,
		},
		{
			"type": "modes",
			"gain": 0.55 * ring,
			"freqs": b["modes"],
			"amps": b["amps"],
			"decays": b["decays"],
			"detune": 0.03,
		},
	]


## The smaller second tick of a grenade of body `b` rattling over surface `s`.
static func _grenade_rattle(b: Dictionary, s: Dictionary) -> Array:
	var knock: Array = s["knock"]
	var ring: float = s["ring"]
	return [
		{
			"type": "noise",
			"gain": knock[3] * 0.4,
			"lp": knock[0],
			"hp": knock[1],
			"decay": knock[2],
			"delay": 0.07,
			"attack": 0.0003,
		},
		{
			"type": "modes",
			"gain": 0.2 * ring,
			"freqs": b["modes"],
			"amps": b["amps"],
			"decays": b["decays"],
			"delay": 0.07,
			"detune": 0.03,
		},
	]


## A burst of `kind`. The frag fills the second (the longest a profile may run), the stun's bang is
## over in under half of it.
static func _explosion(kind: String) -> Dictionary:
	var level := float(EXPLOSIONS[kind]["db"])
	if kind == "frag":
		return { "length": 0.97, "level_db": level, "drive": 2.2, "layers": _frag_burst() }
	return { "length": 0.42, "level_db": level, "drive": 3.5, "layers": _stun_bang() }


## A frag's burst: a crack, the boom and a sub-bass, a roar and a rumble, debris pattering down.
static func _frag_burst() -> Array:
	return [
		{
			"type": "noise", "gain": 1.0, "decay": 0.018, "lp": 8000.0, "hp": 250.0,
			"attack": 0.0005,
		},
		{
			"type": "tone", "gain": 1.6, "freq": 105.0, "freq_end": 32.0, "sweep": 0.09,
			"decay": 0.30,
		},
		{
			"type": "tone", "gain": 1.2, "freq": 52.0, "freq_end": 26.0, "sweep": 0.15,
			"decay": 0.55,
		},
		{
			"type": "noise", "gain": 1.1, "decay": 0.30, "lp": 520.0, "hp": 30.0,
			"attack": 0.008, "delay": 0.005,
		},
		{
			"type": "noise", "gain": 0.6, "decay": 0.12, "lp": 2200.0, "hp": 200.0,
			"attack": 0.003,
		},
		{
			"type": "noise", "gain": 0.55, "decay": 0.20, "lp": 380.0, "hp": 20.0,
			"attack": 0.08, "delay": 0.12,
		},
		{
			"type": "noise", "gain": 0.18, "decay": 0.22, "lp": 3500.0, "hp": 700.0,
			"attack": 0.05, "delay": 0.2,
		},
	]


## A stun's bang: sharp, bright (a ring of high partials) and soon over.
static func _stun_bang() -> Array:
	return [
		{
			"type": "noise", "gain": 1.5, "decay": 0.012, "lp": 11_000.0, "hp": 1800.0,
			"attack": 0.0002,
		},
		{
			"type": "noise", "gain": 1.0, "decay": 0.05, "lp": 9000.0, "hp": 900.0,
			"attack": 0.0004,
		},
		{
			"type": "modes",
			"gain": 0.55,
			"freqs": [2900.0, 4300.0, 6100.0],
			"amps": [1.0, 0.8, 0.5],
			"decays": [0.09, 0.06, 0.04],
			"detune": 0.02,
		},
		{
			"type": "tone", "gain": 0.55, "freq": 150.0, "freq_end": 70.0, "sweep": 0.02,
			"decay": 0.05,
		},
		{
			"type": "noise", "gain": 0.35, "decay": 0.12, "lp": 4500.0, "hp": 600.0,
			"attack": 0.004, "delay": 0.015,
		},
	]


## The ringing in the ears: a thin whine that loops without a seam for as long as it is played.
static func _tinnitus() -> Dictionary:
	var layers := []
	for tone: Array in TINNITUS_TONES:
		layers.append({
			"type": "tone",
			"gain": tone[1],
			"freq": tone[0],
			"freq_end": tone[0],
			"decay": 100_000.0,
		})
	return { "length": TINNITUS_LOOP, "level_db": -6.0, "loop": true, "layers": layers }
