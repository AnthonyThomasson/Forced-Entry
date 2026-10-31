class_name SoundDoors
## Audio domain: the doors, one family of the sound library (SoundBank, `docs/doors.md` DR12): what
## a door's leaf sounds like at each stage of its life, by the material it is made of. A profile is
## `leaf/<material>/<stage>`, the material a `DoorMaterialConfig.materials` id (`hollow`, `solid`,
## `steel`, `glass`) and the stage a `&"door"` event's (Objects): `open` (the swing, a creak: wood
## creaks, a steel door groans, a glass-panel door's frame creaks like wood), `shut` (the latch as
## it closes: a click and a thud; a steel door shuts with a solid wood door's, so it has no `shut`
## of its own), `burst` (the latch giving and the leaf slamming the wall), `down` (the splinter and
## thud of the fall, steel a heavy clang) and, for the glass-panel door only, `glass` (the panes
## shattering). The `profile` function names one without rendering it; the bank renders and caches
## it, asking `recipe` for its recipe. (A vehicle's door is the bank's `door/...` family,
## `SoundVehicles`.)

## The stages every material has, then the one only the glass-panel door has.
const STAGES: Array[String] = ["open", "shut", "burst", "down"]
const PANES_STAGE := "glass"
## The material whose `shut` a door of another material plays: a steel door shuts with the heavy
## wood door's latch (the click and the thud), not a clang.
const SHUT_AS := { "steel": "solid" }
## The materials. db: the trim of every sound of the door. pitch: the scale of its creak and its
## knocks (a heavier door lower). creak: the stick-slip of the swing, `rate` slips a second through
## the leaf's resonances `freqs` / `amps` / `decays`, `noise` of each slip heard raw, a whine
## gliding `whine` [from Hz, to Hz, gain] under it and `gain` how loud the slips are against that
## whine and the click before it. thud: the leaf coming home, [from Hz, to Hz,
## decay s, gain]. panel: the leaf's low panel resonances [Hz], their decay s and gain. ring: a
## steel door's clang, [Hz, gain, decay s] per partial (none for wood). splinters: how many chips of
## wood fly when it breaks (none for steel).
const MATERIALS := {
	"hollow": {
		"db": 0.0, "pitch": 1.1,
		"creak": {
			"gain": 9.0, "rate": 30.0, "lp": 2300.0, "noise": 0.1,
			"freqs": [340.0, 520.0, 780.0], "amps": [1.0, 0.6, 0.35],
			"decays": [0.035, 0.03, 0.02], "whine": [230.0, 300.0, 0.3],
		},
		"thud": [130.0, 68.0, 0.05, 0.8], "panel": [[170.0, 250.0], 0.045, 0.5],
		"ring": [], "splinters": 5,
	},
	"solid": {
		"db": 1.5, "pitch": 0.85,
		"creak": {
			"gain": 22.0, "rate": 22.0, "lp": 1900.0, "noise": 0.08,
			"freqs": [240.0, 380.0, 560.0], "amps": [1.0, 0.65, 0.35],
			"decays": [0.05, 0.04, 0.03], "whine": [160.0, 215.0, 0.35],
		},
		"thud": [105.0, 52.0, 0.08, 1.1], "panel": [[130.0, 195.0], 0.07, 0.6],
		"ring": [], "splinters": 4,
	},
	"steel": {
		"db": 2.0, "pitch": 0.7,
		"creak": {
			"gain": 18.0, "rate": 16.0, "lp": 2600.0, "noise": 0.05,
			"freqs": [150.0, 310.0, 470.0, 690.0], "amps": [1.0, 0.8, 0.5, 0.3],
			"decays": [0.09, 0.08, 0.06, 0.05], "whine": [120.0, 175.0, 0.45],
		},
		"thud": [95.0, 46.0, 0.09, 1.0], "panel": [[120.0, 185.0], 0.08, 0.5],
		"ring": [[420.0, 1.0, 0.22], [780.0, 0.7, 0.17], [1370.0, 0.4, 0.11], [2100.0, 0.2, 0.07]],
		"splinters": 0,
	},
	"glass": {
		"db": 0.0, "pitch": 1.0,
		"creak": {
			"gain": 9.0, "rate": 28.0, "lp": 2200.0, "noise": 0.1,
			"freqs": [320.0, 490.0, 740.0], "amps": [1.0, 0.6, 0.35],
			"decays": [0.035, 0.03, 0.02], "whine": [215.0, 280.0, 0.3],
		},
		"thud": [125.0, 64.0, 0.05, 0.75], "panel": [[160.0, 235.0], 0.045, 0.45],
		"ring": [], "splinters": 4,
	},
}
## The clip length (s) of each stage; the steel door's fall rings on to `STEEL_DOWN_LENGTH`.
const LENGTHS := { "open": 0.52, "shut": 0.3, "burst": 0.5, "down": 0.6, "glass": 0.85 }
const STEEL_DOWN_LENGTH := 0.9
## The level trim (dB) of each stage, on the material's own, and the saturation (tanh `drive`) of
## the loud ones: a creak is quiet, a latch softer than a slam, a burst the loudest.
const STAGE_DB := { "open": -7.0, "shut": -3.0, "burst": 0.0, "down": 1.0, "glass": -1.0 }
const STAGE_DRIVE := { "burst": 1.3, "down": 1.2 }
## When (s after the start) each splinter of a breaking wooden leaf lets go, in order.
const SPLINTER_AT: Array[float] = [0.0, 0.012, 0.031, 0.049, 0.07, 0.092]
## When (s) each shard of shattering glass tinkles, after the crack at 0 and its first rush.
const SHARD_AT: Array[float] = [
	0.03, 0.055, 0.08, 0.101, 0.137, 0.166, 0.2, 0.236, 0.281, 0.33, 0.39, 0.46, 0.55, 0.65,
]
## The pitches (Hz) the shards ring at, taken in turn.
const SHARD_HZ: Array[float] = [2850.0, 3640.0, 4410.0, 3170.0, 5120.0, 3920.0, 2480.0]


## A door leaf of `material` at `stage` (a `&"door"` event's). &"" for a material or a stage that
## has no sound: the panes' `glass` stage exists for the glass-panel door only. A `shut` is that of
## `SHUT_AS`'s material where it names one.
static func profile(material: String, stage: StringName) -> StringName:
	if not MATERIALS.has(material):
		return &""
	var s := String(stage)
	if not (STAGES.has(s) or (s == PANES_STAGE and material == "glass")):
		return &""
	if s == "shut":
		material = SHUT_AS.get(material, material)
	return StringName("leaf/%s/%s" % [material, s])


## The door profiles, in the library's order (the bank's `profiles` holds them): per material its
## four stages (a material that shuts as another has no `shut` of its own), then the panes
## shattering.
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	for material: String in MATERIALS:
		for stage in STAGES:
			if stage == "shut" and SHUT_AS.has(material):
				continue
			out.append(profile(material, StringName(stage)))
		if material == "glass":
			out.append(profile(material, StringName(PANES_STAGE)))
	return out


## The recipe of a `leaf/...` profile split into its `parts`; {} if it names no sound.
static func recipe(parts: PackedStringArray) -> Dictionary:
	if parts.size() != 3 or profile(parts[1], StringName(parts[2])) != StringName("/".join(parts)):
		return {}
	var m: Dictionary = MATERIALS[parts[1]]
	var length: float = (
		STEEL_DOWN_LENGTH if parts[1] == "steel" and parts[2] == "down" else LENGTHS[parts[2]]
	)
	var out := {
		"length": length,
		"level_db": float(m["db"]) + float(STAGE_DB[parts[2]]),
		"vary": 0.1,
		"drive": float(STAGE_DRIVE.get(parts[2], 0.0)),
	}
	match parts[2]:
		"open":
			out["layers"] = _creak(m)
		"shut":
			out["layers"] = _latch(m)
		"burst":
			out["layers"] = _burst(m)
		"down":
			out["layers"] = _fall(m)
		"glass":
			out["layers"] = _shatter()
	return out


## The swing: the handle's click as the latch lets go, then the leaf creaking, slip after slip
## through its resonances, with a whine gliding up under it (a steel door groans, lower and slower).
static func _creak(m: Dictionary) -> Array:
	var p: float = m["pitch"]
	var c: Dictionary = m["creak"]
	var whine: Array = c["whine"]
	var layers := [
		{
			"type": "noise", "gain": 0.3, "decay": 0.003, "lp": 3200.0 * p, "hp": 700.0,
			"attack": 0.0003,
		},
		{
			"type": "pulses", "gain": c["gain"], "delay": 0.03, "rate": c["rate"],
			"pattern": [1.0, 0.7, 0.9, 0.55],
			"spread": 0.25, "jitter": 0.35, "burst": 0.004, "lp": c["lp"], "hp": 90.0,
			"noise": c["noise"], "freqs": c["freqs"], "amps": c["amps"], "decays": c["decays"],
			"wobble": [3, 0.45],
		},
		{
			"type": "tone", "gain": whine[2], "freq": whine[0], "freq_end": whine[1],
			"sweep": 0.2, "decay": 0.16, "delay": 0.05,
		},
	]
	# A steel door's hinges groan with a faint ring of the sheet.
	layers.append_array(_ring(m, 0.12, 0.04))
	return layers


## The latch as it closes: a click, the latch seating, and the leaf's thud into the frame.
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
## panels (and a steel door's sheet clanging). Wood splinters at the strike.
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
	layers.append_array(_ring(m, 0.8, 0.03))
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
