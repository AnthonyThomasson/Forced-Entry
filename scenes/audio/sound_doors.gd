class_name SoundDoors
## Audio domain: the doors, one family of the sound library (SoundBank, `docs/doors.md` DR12): what
## a door's leaf sounds like at each stage of its life. Every door, whatever its material, opens
## and shuts with the one latch sound, `leaf/latch` (a click, the latch seating and the leaf's
## thud: the solid wood door's `shut`), and bursts open with the one burst sound, `leaf/burst` (the
## latch cracking and the leaf slamming the wall, wood splintering: the solid wood door's). What
## differs by material is the fall, `leaf/<material>/down` (the splinter and thud of it, a steel
## door's a heavy clang) and, for the glass-panel door only, `leaf/glass/glass` (the panes
## shattering). The `profile` function names one without rendering it; the bank renders and caches
## it, asking `recipe` for its recipe. (A vehicle's door is the bank's `door/...` family,
## `SoundVehicles`.)

## The profiles every door plays, whatever its material: the latch (a `&"door"` event's `open` and
## `shut`) and the burst.
const LATCH := &"leaf/latch"
const BURST := &"leaf/burst"
## The material whose row the latch and the burst are voiced from: the solid wood door's.
const LEAF_MATERIAL := "solid"
## The materials. db: the trim of every sound of the door. pitch: the scale of its knocks (a heavier
## door lower). thud: the leaf coming home, [from Hz, to Hz, decay s, gain]. panel: the leaf's low
## panel resonances [Hz], their decay s and gain. ring: a steel door's clang, [Hz, gain, decay s]
## per partial (none for wood). splinters: how many chips of wood fly when it breaks (none for
## steel).
const MATERIALS := {
	"hollow": {
		"db": 0.0, "pitch": 1.1,
		"thud": [130.0, 68.0, 0.05, 0.8], "panel": [[170.0, 250.0], 0.045, 0.5],
		"ring": [], "splinters": 5,
	},
	"solid": {
		"db": 1.5, "pitch": 0.85,
		"thud": [105.0, 52.0, 0.08, 1.1], "panel": [[130.0, 195.0], 0.07, 0.6],
		"ring": [], "splinters": 4,
	},
	"steel": {
		"db": 2.0, "pitch": 0.7,
		"thud": [95.0, 46.0, 0.09, 1.0], "panel": [[120.0, 185.0], 0.08, 0.5],
		"ring": [[420.0, 1.0, 0.22], [780.0, 0.7, 0.17], [1370.0, 0.4, 0.11], [2100.0, 0.2, 0.07]],
		"splinters": 0,
	},
	"glass": {
		"db": 0.0, "pitch": 1.0,
		"thud": [125.0, 64.0, 0.05, 0.75], "panel": [[160.0, 235.0], 0.045, 0.45],
		"ring": [], "splinters": 4,
	},
}
## The clip length (s) of each sound; the steel door's fall rings on to `STEEL_DOWN_LENGTH`.
const LENGTHS := { "latch": 0.3, "burst": 0.5, "down": 0.6, "glass": 0.85 }
const STEEL_DOWN_LENGTH := 0.9
## The level trim (dB) of each sound, on the material's own, and the saturation (tanh `drive`) of
## the loud ones: a latch is softer than a slam, a burst the loudest.
const SOUND_DB := { "latch": -3.0, "burst": 0.0, "down": 1.0, "glass": -1.0 }
const SOUND_DRIVE := { "burst": 1.3, "down": 1.2 }
## When (s after the start) each splinter of a breaking wooden leaf lets go, in order.
const SPLINTER_AT: Array[float] = [0.0, 0.012, 0.031, 0.049, 0.07, 0.092]
## When (s) each shard of shattering glass tinkles, after the crack at 0 and its first rush.
const SHARD_AT: Array[float] = [
	0.03, 0.055, 0.08, 0.101, 0.137, 0.166, 0.2, 0.236, 0.281, 0.33, 0.39, 0.46, 0.55, 0.65,
]
## The pitches (Hz) the shards ring at, taken in turn.
const SHARD_HZ: Array[float] = [2850.0, 3640.0, 4410.0, 3170.0, 5120.0, 3920.0, 2480.0]


## The sound of a door leaf of `material` at `stage` (a `&"door"` event's): the one latch for `open`
## and `shut`, the one burst for `burst`, the material's own `down`, and the panes' `glass` for the
## glass-panel door only. &"" for a material or a stage that has no sound.
static func profile(material: String, stage: StringName) -> StringName:
	if not MATERIALS.has(material):
		return &""
	match String(stage):
		"open", "shut":
			return LATCH
		"burst":
			return BURST
		"down":
			return StringName("leaf/%s/down" % material)
		"glass":
			return &"leaf/glass/glass" if material == "glass" else &""
	return &""


## The door profiles, in the library's order (the bank's `profiles` holds them): the latch, the
## burst, per material its fall, then the panes shattering.
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = [LATCH, BURST]
	for material: String in MATERIALS:
		out.append(profile(material, &"down"))
	out.append(profile("glass", &"glass"))
	return out


## The recipe of a `leaf/...` profile split into its `parts`; {} if it names no sound.
static func recipe(parts: PackedStringArray) -> Dictionary:
	var named := StringName("/".join(parts))
	if not profiles().has(named):
		return {}
	var sound := String(parts[parts.size() - 1])
	var material: String = parts[1] if parts.size() == 3 else LEAF_MATERIAL
	var m: Dictionary = MATERIALS[material]
	var length: float = (
		STEEL_DOWN_LENGTH if material == "steel" and sound == "down" else LENGTHS[sound]
	)
	var out := {
		"length": length,
		"level_db": float(m["db"]) + float(SOUND_DB[sound]),
		"vary": 0.1,
		"drive": float(SOUND_DRIVE.get(sound, 0.0)),
	}
	match sound:
		"latch":
			out["layers"] = _latch(m)
		"burst":
			out["layers"] = _burst(m)
		"down":
			out["layers"] = _fall(m)
		"glass":
			out["layers"] = _shatter()
	return out


## The latch, as a door opens and as it closes: a click, the latch seating, and the leaf's thud
## into the frame.
static func _latch(m: Dictionary) -> Array:
	var p: float = m["pitch"]
	var layers := [
		{
			"type": "noise", "gain": 0.4, "decay": 0.003, "lp": 4200.0 * p, "hp": 1300.0,
			"attack": 0.0002,
		},
		{
			"type": "noise", "gain": 0.35, "decay": 0.004, "lp": 2000.0 * p, "hp": 500.0,
			"delay": 0.022, "attack": 0.0003,
		},
	]
	layers.append_array(_thud(m, 0.012, 0.9))
	return layers


## A burst: the latch giving with a sharp crack, then the leaf slamming the wall, its weight and its
## panels. Wood splinters at the strike.
static func _burst(m: Dictionary) -> Array:
	var p: float = m["pitch"]
	var layers := [
		{
			"type": "noise", "gain": 0.7, "decay": 0.006, "lp": 4000.0 * p, "hp": 900.0,
			"attack": 0.0002,
		},
	]
	layers.append_array(_thud(m, 0.03, 1.5))
	layers.append({
		"type": "noise", "gain": 0.8, "decay": 0.016, "lp": 1100.0 * p, "hp": 80.0,
		"delay": 0.03, "attack": 0.0004,
	})
	layers.append_array(_splinters(m, 0.03, 0.5))
	return layers


## The fall: the leaf coming off its hinges and the chips of wood flying, then the heavy thud of it
## on the floor and the dull rattle after it; a steel door lands with a heavy clang that rings on.
static func _fall(m: Dictionary) -> Array:
	var p: float = m["pitch"]
	var layers := _splinters(m, 0.0, 0.9)
	layers.append_array(_thud(m, 0.11, 1.7))
	layers.append({
		"type": "noise", "gain": 0.7, "decay": 0.02, "lp": 900.0 * p, "hp": 60.0,
		"delay": 0.11, "attack": 0.0005,
	})
	# the leaf settling: a smaller knock and a rattle of the hardware
	layers.append({
		"type": "tone", "gain": 0.35, "freq": 150.0 * p, "freq_end": 90.0 * p, "sweep": 0.01,
		"decay": 0.03, "delay": 0.24,
	})
	layers.append({
		"type": "noise", "gain": 0.12, "decay": 0.02, "lp": 2400.0, "hp": 800.0, "delay": 0.25,
	})
	layers.append_array(_ring(m, 1.5, 0.11, 2.2))
	return layers


## The panes shattering: a sharp crack, a rush of glass and the shards tinkling down after it.
static func _shatter() -> Array:
	var layers := [
		{
			"type": "noise", "gain": 1.0, "decay": 0.012, "lp": 9000.0, "hp": 2200.0,
			"attack": 0.0002,
		},
		{
			"type": "noise", "gain": 0.5, "decay": 0.12, "lp": 7000.0, "hp": 1800.0,
			"delay": 0.01, "attack": 0.002,
		},
		{
			"type": "modes", "gain": 0.4, "freqs": [2100.0, 3300.0, 4600.0, 5900.0],
			"amps": [1.0, 0.8, 0.6, 0.4], "decays": [0.09, 0.07, 0.05, 0.04], "detune": 0.04,
		},
		# the frame's knock under the crack
		{
			"type": "tone", "gain": 0.5, "freq": 140.0, "freq_end": 80.0, "sweep": 0.015,
			"decay": 0.04,
		},
	]
	for i in SHARD_AT.size():
		var hz: float = SHARD_HZ[i % SHARD_HZ.size()]
		layers.append({
			"type": "modes", "gain": 0.32 * (1.0 - float(i) / (SHARD_AT.size() * 1.4)),
			"freqs": [hz, hz * 1.52], "amps": [1.0, 0.45], "decays": [0.04, 0.025],
			"delay": SHARD_AT[i], "detune": 0.03,
		})
	return layers


## The leaf's weight arriving `at` s into the sound: the thud of it, and the low panels taking it,
## `weight` times a plain knock.
static func _thud(m: Dictionary, at: float, weight: float) -> Array:
	var p: float = m["pitch"]
	var t: Array = m["thud"]
	var panel: Array = m["panel"]
	return [
		{
			"type": "tone", "gain": t[3] * weight, "freq": t[0], "freq_end": t[1],
			"sweep": 0.02, "decay": t[2], "delay": at,
		},
		{
			"type": "modes", "gain": panel[2] * weight, "freqs": panel[0], "amps": [1.0, 0.55],
			"decays": [panel[1], panel[1] * 0.65], "delay": at, "detune": 0.02,
		},
		{
			"type": "noise", "gain": 0.45 * weight, "decay": 0.012, "lp": 1000.0 * p,
			"hp": 80.0, "delay": at, "attack": 0.0004,
		},
	]


## Chips of wood flying `at` s in, `gain` loud: short dry cracks one after another (none for a steel
## door).
static func _splinters(m: Dictionary, at: float, gain: float) -> Array:
	var layers := []
	for i in int(m["splinters"]):
		layers.append({
			"type": "noise", "gain": gain * (0.5 - 0.05 * i), "decay": 0.004 + 0.0015 * i,
			"lp": 3600.0 - 280.0 * i, "hp": 700.0, "delay": at + SPLINTER_AT[i],
			"attack": 0.0002,
		})
	return layers


## A steel door's sheet ringing `at` s in as layers: its partials (`gain` loud, their decays
## stretched by `stretch`); none for a wooden door.
static func _ring(m: Dictionary, gain: float, at: float, stretch := 1.0) -> Array:
	var freqs := []
	var amps := []
	var decays := []
	for partial: Array in m["ring"]:
		freqs.append(partial[0])
		amps.append(partial[1])
		decays.append(float(partial[2]) * stretch)
	if freqs.is_empty():
		return []
	return [{
		"type": "modes", "gain": gain, "freqs": freqs, "amps": amps, "decays": decays,
		"delay": at, "detune": 0.02,
	}]
