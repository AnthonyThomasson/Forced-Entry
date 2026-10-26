class_name SoundVehicles
## Audio domain: the vehicles, one family of the sound library (SoundBank, `docs/vehicles.md`): a
## vehicle's engine loop, its ignition, its doors, the tyres' skid and its crashes. A profile is
## `engine/<kind>`, `ignition/<kind>`, `door/<kind>/<open|close|slide_open|slide_close>` (kind `car`
## or `van`; an unknown one is voiced as a car), `skid/tyre` or `crash/<material>/<band>` (the
## material a `SoundImpacts.MATERIALS` entry, `flesh` for a character struck; the band by the
## closing speed, SoundVehicleConfig.crash_medium_speed / crash_heavy_speed). The `*_profile`
## functions name one without rendering it; the bank renders and caches it, asking `recipe` for its
## recipe.

## The vehicles. engine: the loop's firing train, `rate` firings a second at idle (whole firings per
## `ENGINE_LOOP` s and a whole number of `pattern`s, so it loops without a seam; the service pitches
## it up with the revs), each a noise burst of `burst` s through `lp`, its level cycling through
## `pattern` (the cylinders, so it chugs rather than buzzes) and rung through the exhaust's
## resonances `pipe` ([Hz, level, decay s]); `noise` is how much of the raw burst is heard. crank:
## the starter's [strokes, gap s, whine Hz]; door: the pitch scale (a heavier door lower) and level
## of its clunks; slide: a sliding door. db trims each sound's level. The van is the bigger,
## slower-firing, deeper engine.
const ENGINE_LOOP := 1.0
const KINDS := {
	"car": {
		"db": 0.0, "rate": 28.0, "pattern": [1.0, 0.72, 0.9, 0.66], "burst": 0.006, "lp": 1800.0,
		"noise": 0.6,
		"pipe": [
			[64.0, 0.55, 0.05], [128.0, 0.8, 0.035], [210.0, 0.9, 0.025], [340.0, 0.75, 0.018],
			[560.0, 0.45, 0.012], [900.0, 0.2, 0.008],
		],
		"crank": [4, 0.105, 290.0], "door": [1.0, 0.0], "slide": false,
	},
	"van": {
		"db": 1.0, "rate": 20.0, "pattern": [1.0, 0.86, 0.95, 0.8], "burst": 0.009, "lp": 1200.0,
		"noise": 0.4,
		"pipe": [
			[44.0, 0.8, 0.06], [88.0, 0.9, 0.045], [146.0, 0.85, 0.03], [235.0, 0.6, 0.02],
			[390.0, 0.35, 0.014], [640.0, 0.15, 0.01],
		],
		"crank": [5, 0.12, 230.0], "door": [0.82, 1.0], "slide": true,
	},
}
const DOOR_STAGES: Array[String] = ["open", "close", "slide_open", "slide_close"]
## A crash by how hard it was, from the closing speed: db trims the level, body scales the vehicle's
## mass thumping home, crunch the sheet metal folding, length the clip (s); glass = shards tinkling
## after it, debris = bits pattering.
const CRASH_BANDS := {
	"light": {
		"db": -6.0,
		"body": 0.7,
		"crunch": 0.55,
		"length": 0.4,
		"glass": 0.0,
		"debris": 0.0,
	},
	"medium": {
		"db": 0.0, "body": 1.0, "crunch": 1.0, "length": 0.55, "glass": 0.0, "debris": 0.6,
	},
	"heavy": { "db": 4.0, "body": 1.5, "crunch": 1.4, "length": 0.75, "glass": 1.0, "debris": 1.0 },
}


## The engine loop of a vehicle of `kind`.
static func engine_profile(kind: StringName) -> StringName:
	return StringName("engine/" + _kind(kind))


## The starter cranking and the engine catching, for a vehicle of `kind`.
static func ignition_profile(kind: StringName) -> StringName:
	return StringName("ignition/" + _kind(kind))


## A door of a vehicle of `kind` at `stage` (`open`, `close`, `slide_open`, `slide_close`; a slide
## is voiced only for a kind with a sliding door). &"" for any other stage.
static func door_profile(kind: StringName, stage: StringName) -> StringName:
	var k := _kind(kind)
	if (not DOOR_STAGES.has(String(stage))
			or (String(stage).begins_with("slide") and not KINDS[k]["slide"])):
		return &""
	return StringName("door/%s/%s" % [k, stage])


## The tyres sliding (a loop).
static func skid_profile() -> StringName:
	return &"skid/tyre"


## A vehicle striking `material` (a struck surface's; "" is a wall, `flesh` a character) at closing
## speed `speed`.
static func crash_profile(material: String, speed: float) -> StringName:
	var mat := ("wall"
			if material == ""
			else (material if SoundImpacts.MATERIALS.has(material) else "default"))
	return StringName("crash/%s/%s" % [mat, _crash_band(speed)])


## The vehicle profiles, in the library's order (the bank's `profiles` holds them): per kind its
## engine, its ignition and its doors, then the skid, then every crash.
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	for kind: String in KINDS:
		out.append(StringName("engine/" + kind))
		out.append(StringName("ignition/" + kind))
		for stage in DOOR_STAGES:
			if not stage.begins_with("slide") or KINDS[kind]["slide"]:
				out.append(StringName("door/%s/%s" % [kind, stage]))
	out.append(skid_profile())
	for mat: String in SoundImpacts.MATERIALS:
		for b: String in CRASH_BANDS:
			out.append(StringName("crash/%s/%s" % [mat, b]))
	return out


## The recipe of an `engine/...`, `ignition/...`, `door/...`, `skid/...` or `crash/...` profile
## split into its `parts` (`profile` the whole of it, for a door's stage); {} if it names no sound.
static func recipe(parts: PackedStringArray, profile: StringName) -> Dictionary:
	var out := {}
	var id := parts[1] if parts.size() == 2 else ""
	match parts[0]:
		"engine":
			if KINDS.has(id):
				out = _engine(id)
		"ignition":
			if KINDS.has(id):
				out = _ignition(id)
		"skid":
			if id == "tyre":
				out = _skid()
		"door":
			if (parts.size() == 3
					and KINDS.has(parts[1])
					and door_profile(StringName(parts[1]), StringName(parts[2])) == profile):
				out = _door(parts[1], parts[2])
		"crash":
			if (parts.size() == 3
					and SoundImpacts.MATERIALS.has(parts[1])
					and CRASH_BANDS.has(parts[2])):
				out = _crash(parts[1], parts[2])
	return out


## A vehicle kind the bank voices: `kind` itself, or a car for an unknown one.
static func _kind(kind: StringName) -> String:
	return String(kind) if KINDS.has(String(kind)) else "car"


## The crash band (`light` / `medium` / `heavy`) of an impact at closing speed `speed` (px/s).
static func _crash_band(speed: float) -> String:
	if speed >= SoundVehicleConfig.crash_heavy_speed:
		return "heavy"
	if speed >= SoundVehicleConfig.crash_medium_speed:
		return "medium"
	return "light"


## A running engine at idle: one period of its firing train, every firing a burst rung through the
## exhaust's resonances, the cylinders each a little different (`pattern`) and never quite even
## (`spread`, `jitter`), so it chugs rather than buzzes. A seamless loop the service plays faster as
## the revs climb.
static func _engine(kind: String) -> Dictionary:
	var v: Dictionary = KINDS[kind]
	var freqs := []
	var amps := []
	var decays := []
	for pipe: Array in v["pipe"]:
		freqs.append(pipe[0])
		amps.append(pipe[1])
		decays.append(pipe[2])
	var rate: float = v["rate"]
	return {
		"length": ENGINE_LOOP, "level_db": -2.0 + float(v["db"]), "loop": true, "drive": 1.4,
		"layers": [
			{ "type": "pulses", "rate": rate, "pattern": v["pattern"], "spread": 0.08,
				"jitter": 0.025, "burst": v["burst"], "lp": v["lp"], "hp": 25.0,
				"noise": v["noise"], "freqs": freqs, "amps": amps, "decays": decays,
				"wobble": [2, 0.05] },
			# The block's hum at the firing rate and its double: whole cycles of the loop, so they
			# join without a seam.
			{ "type": "tone", "gain": 0.06, "freq": rate, "decay": 100_000.0 },
			{ "type": "tone", "gain": 0.05, "freq": rate * 2.0, "decay": 100_000.0 },
			# The valves ticking over, faint and high.
			{
				"type": "pulses",
				"rate": rate * 2.0,
				"burst": 0.0015,
				"lp": 5200.0,
				"hp": 1800.0,
				"noise": 0.05,
				"spread": 0.3,
			},
		],
	}


## The key turned: the starter cranks a few strokes (a geared whine that slows at each compression),
## the engine catches with a stumble of firings that race up and settle back to idle.
static func _ignition(kind: String) -> Dictionary:
	var v: Dictionary = KINDS[kind]
	var crank: Array = v["crank"]
	var strokes: int = crank[0]
	var gap: float = crank[1]
	var layers := _cranking(v)
	layers.append_array(_catching(v, strokes * gap))
	return { "length": 0.98, "level_db": -2.0 + float(v["db"]), "drive": 1.3, "layers": layers }


## The starter of vehicle row `v` cranking its strokes: each a burst of noise, the geared whine
## slowing at the compression, and its low knock.
static func _cranking(v: Dictionary) -> Array:
	var crank: Array = v["crank"]
	var strokes: int = crank[0]
	var gap: float = crank[1]
	var whine: float = crank[2]
	var low: float = v["pipe"][0][0]
	var layers := []
	for i in strokes:
		var stroke := i * gap
		layers.append({
			"type": "noise",
			"gain": 0.45,
			"attack": 0.02,
			"decay": gap * 0.35,
			"lp": 2400.0,
			"hp": 260.0,
			"delay": stroke,
		})
		layers.append({
			"type": "tone", "gain": 0.3, "freq": whine * 1.1, "freq_end": whine * 0.85,
			"sweep": gap * 0.6, "decay": gap * 0.45, "delay": stroke,
		})
		layers.append({
			"type": "tone",
			"gain": 0.4,
			"freq": low * 1.6,
			"freq_end": low * 1.1,
			"sweep": 0.02,
			"decay": 0.04,
			"delay": stroke,
		})
	return layers


## The engine of vehicle row `v` catching once the starter has cranked for `cranked` s: firings
## close up as it revs, then open out to the idle's beat.
static func _catching(v: Dictionary, cranked: float) -> Array:
	var low: float = v["pipe"][0][0]
	var layers := []
	var at := cranked + 0.02
	var idle := 1.0 / float(v["rate"])
	var k := 0
	while at < 0.93:
		var rev := clampf(float(k) / 7.0, 0.0, 1.0)
		var settle := clampf((at - (cranked + 0.25)) / 0.3, 0.0, 1.0)
		var spacing := lerpf(lerpf(idle * 1.6, idle * 0.62, rev), idle * 0.95, settle)
		var level := lerpf(lerpf(0.6, 1.2, rev), 0.75, settle) * (0.85 if k % 2 == 1 else 1.0)
		layers.append({
			"type": "tone",
			"gain": level,
			"freq": low * 2.2,
			"freq_end": low * 1.2,
			"sweep": 0.012,
			"decay": 0.03,
			"delay": at,
		})
		layers.append({
			"type": "noise",
			"gain": level * 0.6,
			"decay": float(v["burst"]) * 1.5,
			"lp": float(v["lp"]),
			"hp": 50.0,
			"delay": at,
		})
		at += spacing
		k += 1
	return layers


## A door of `kind`, in a reload's register: dry mechanical clicks over a low thunk, nothing that
## creaks or rings. `open`: the handle's click, the latch letting go with a knock, and the door
## coming off its seal in a soft low thump. `close`: the slam, the door's weight thumping home with
## the body's low panels, the latch clicking shut into it and a dull knock of the trim. A sliding
## door's `slide_open` rolls back on its runners into the stop, its `slide_close` is the heavy thunk
## of it shutting with the catch clicking home.
static func _door(kind: String, stage: String) -> Dictionary:
	var door: Array = KINDS[kind]["door"]
	var p: float = door[0]
	var db: float = door[1]
	match stage:
		"open":
			return {
				"length": 0.3, "level_db": -5.0 + db, "vary": 0.08,
				"layers": _door_latch(p) + _door_seal(p),
			}
		"close":
			return {
				"length": 0.42, "level_db": -1.0 + db, "vary": 0.06, "drive": 1.2,
				"layers": _door_slam(p),
			}
		"slide_open":
			return {
				"length": 0.68, "level_db": -3.0 + db, "vary": 0.06,
				"layers": _slide_rattle() + _slide_release() + _slide_run(),
			}
		"slide_close":
			return {
				"length": 0.5, "level_db": 0.0 + db, "vary": 0.06, "drive": 1.3,
				"layers": _slide_shut(),
			}
	return {}


## A door at pitch `p` opening: the handle's click, then the latch letting go.
static func _door_latch(p: float) -> Array:
	return [
		# The handle's click, then the latch letting go: two dry clicks, a knock under the
		# second.
		{
			"type": "noise",
			"gain": 0.35,
			"decay": 0.003,
			"lp": 4500.0 * p,
			"hp": 1500.0,
			"attack": 0.0002,
		},
		{
			"type": "noise",
			"gain": 0.4,
			"decay": 0.004,
			"lp": 1900.0 * p,
			"hp": 400.0,
			"delay": 0.035,
			"attack": 0.0003,
		},
		{
			"type": "tone",
			"gain": 0.75,
			"freq": 140.0 * p,
			"freq_end": 80.0 * p,
			"sweep": 0.012,
			"decay": 0.03,
			"delay": 0.035,
		},
		{ "type": "modes", "gain": 0.3, "freqs": [190.0 * p, 255.0 * p], "amps": [1.0, 0.5],
			"decays": [0.03, 0.02], "delay": 0.035, "detune": 0.02 },
	]


## A door at pitch `p` coming off its seal.
static func _door_seal(p: float) -> Array:
	return [
		# The door coming off its seal: a soft, low thump as it swings free.
		{
			"type": "tone",
			"gain": 0.6,
			"freq": 100.0 * p,
			"freq_end": 58.0 * p,
			"sweep": 0.02,
			"decay": 0.05,
			"delay": 0.06,
		},
		{
			"type": "noise",
			"gain": 0.25,
			"attack": 0.004,
			"decay": 0.03,
			"lp": 420.0 * p,
			"hp": 60.0,
			"delay": 0.06,
		},
	]


## A door at pitch `p` slammed shut.
static func _door_slam(p: float) -> Array:
	return [
		# The door's weight thumping home and the body's low panels taking it.
		{
			"type": "tone",
			"gain": 1.2,
			"freq": 125.0 * p,
			"freq_end": 48.0 * p,
			"sweep": 0.02,
			"decay": 0.09,
		},
		{ "type": "modes", "gain": 0.7, "freqs": [150.0 * p, 230.0 * p],
			"amps": [1.0, 0.55], "decays": [0.07, 0.045], "detune": 0.02 },
		{
			"type": "noise",
			"gain": 0.9,
			"decay": 0.014,
			"lp": 1100.0 * p,
			"hp": 80.0,
			"attack": 0.0004,
		},
		# The latch clicking shut into the slam, and a dull knock of the trim after it.
		{
			"type": "noise",
			"gain": 0.3,
			"decay": 0.003,
			"lp": 4000.0 * p,
			"hp": 1400.0,
			"delay": 0.012,
			"attack": 0.0002,
		},
		{
			"type": "tone",
			"gain": 0.3,
			"freq": 180.0 * p,
			"freq_end": 120.0 * p,
			"sweep": 0.01,
			"decay": 0.02,
			"delay": 0.05,
		},
	]


## A sliding door's runners rattling as it rolls back.
static func _slide_rattle() -> Array:
	var rattle := []
	for i in 11:
		rattle.append({
			"type": "noise", "gain": 0.16 + 0.05 * (i % 3), "decay": 0.003, "lp": 2600.0,
			"hp": 500.0, "delay": 0.07 + 0.037 * i + 0.006 * (i % 2),
		})
	return rattle


## A sliding door's catch letting go.
static func _slide_release() -> Array:
	return [
		{
			"type": "noise",
			"gain": 0.5,
			"decay": 0.004,
			"lp": 6000.0,
			"hp": 1800.0,
			"attack": 0.0002,
		},
		{
			"type": "tone",
			"gain": 0.4,
			"freq": 140.0,
			"freq_end": 85.0,
			"sweep": 0.015,
			"decay": 0.03,
			"delay": 0.02,
		},
	]


## A sliding door rolling back on its runners and into the stop.
static func _slide_run() -> Array:
	return [
		# The runners: a low rumble with a rattle in it, rolling for the length of the
		# track.
		{
			"type": "noise",
			"gain": 0.75,
			"attack": 0.12,
			"decay": 0.16,
			"lp": 650.0,
			"hp": 70.0,
			"delay": 0.04,
		},
		# Into the stop.
		{
			"type": "tone",
			"gain": 0.7,
			"freq": 115.0,
			"freq_end": 60.0,
			"sweep": 0.015,
			"decay": 0.04,
			"delay": 0.5,
		},
		{
			"type": "noise",
			"gain": 0.5,
			"decay": 0.01,
			"lp": 2600.0,
			"hp": 200.0,
			"delay": 0.5,
		},
	]


## A sliding door shutting.
static func _slide_shut() -> Array:
	return [
		# The heavy door running into its frame, the body's low panels taking it, and the
		# catch clicking home.
		{
			"type": "tone",
			"gain": 1.3,
			"freq": 105.0,
			"freq_end": 42.0,
			"sweep": 0.022,
			"decay": 0.1,
		},
		{
			"type": "modes",
			"gain": 0.7,
			"freqs": [130.0, 210.0],
			"amps": [1.0, 0.6],
			"decays": [0.08, 0.05],
			"detune": 0.02,
		},
		{
			"type": "noise",
			"gain": 1.0,
			"decay": 0.016,
			"lp": 1000.0,
			"hp": 70.0,
			"attack": 0.0004,
		},
		{
			"type": "noise",
			"gain": 0.35,
			"decay": 0.004,
			"lp": 4000.0,
			"hp": 1300.0,
			"delay": 0.02,
			"attack": 0.0002,
		},
	]


## Tyres sliding over the ground: a screech (the rubber's stick-slip ringing the carcass at a few
## close pitches that beat and swell) over a hiss. A seamless loop the service plays as loud as the
## slide.
static func _skid() -> Dictionary:
	return {
		"length": 1.0, "level_db": -3.0, "loop": true,
		"layers": [
			{
				"type": "pulses", "rate": 0.0, "lp": 3500.0, "hp": 500.0, "noise": 0.05,
				"freqs": [990.0, 1380.0, 1985.0, 2710.0], "amps": [1.0, 0.55, 0.35, 0.18],
				"decays": [0.035, 0.03, 0.022, 0.015], "wobble": [3, 0.3],
			},
			{
				"type": "pulses", "gain": 0.6, "rate": 0.0, "lp": 4000.0, "hp": 600.0,
				"freqs": [1060.0, 1490.0], "amps": [1.0, 0.5], "decays": [0.03, 0.025],
				"wobble": [5, 0.4],
			},
		],
	}


## A vehicle striking `material` (`flesh`: a character) in crash band `band_id`: the vehicle's mass
## thumping home (and a boom under a hard one), the sheet metal folding and its panels ringing, the
## struck thing's own crack and ring; a hard one throws glass and bits after it. A character struck
## is a dull, heavy thud on the bonnet instead.
static func _crash(material: String, band_id: String) -> Dictionary:
	var m: Dictionary = SoundImpacts.MATERIALS[material]
	var b: Dictionary = CRASH_BANDS[band_id]
	var body: float = b["body"]
	var layers := [
		{
			"type": "tone",
			"gain": 1.3 * body,
			"freq": 95.0,
			"freq_end": 38.0,
			"sweep": 0.03,
			"decay": 0.07 + 0.03 * body,
		},
	]
	if material == "flesh":
		layers.append_array(_crash_thud())
		return {
			"length": float(b["length"]) * 0.7,
			"level_db": float(b["db"]) - 2.0,
			"vary": 0.1,
			"layers": layers,
		}
	layers.append_array(_crash_fold(b))
	layers.append_array(_crash_struck(m))
	layers.append_array(_crash_after(b))
	return {
		"length": b["length"],
		"level_db": float(b["db"]) + float(m["db"]) * 0.5,
		"vary": 0.1,
		"drive": 1.5,
		"layers": layers,
	}


## A character struck: a dull, heavy thud on the bonnet.
static func _crash_thud() -> Array:
	var layers := []
	layers.append({
		"type": "tone", "gain": 1.0, "freq": 115.0, "freq_end": 55.0, "sweep": 0.02,
		"decay": 0.07,
	})
	layers.append({
		"type": "noise", "gain": 0.7, "decay": 0.03, "lp": 900.0, "hp": 80.0, "attack": 0.001,
	})
	layers.append({
		"type": "modes",
		"gain": 0.6,
		"freqs": [170.0, 380.0],
		"amps": [1.0, 0.6],
		"decays": [0.06, 0.04],
	})
	return layers


## The vehicle of crash band `b` folding: a boom under a hard one, the sheet metal crunching and its
## panels ringing.
static func _crash_fold(b: Dictionary) -> Array:
	var body: float = b["body"]
	var crunch: float = b["crunch"]
	var layers := []
	if body > 1.0:
		layers.append({
			"type": "tone",
			"gain": 0.8 * (body - 0.5),
			"freq": 56.0,
			"freq_end": 30.0,
			"sweep": 0.05,
			"decay": 0.1,
		})
	layers.append({
		"type": "noise",
		"gain": 1.6 * crunch,
		"decay": 0.03,
		"lp": 4500.0,
		"hp": 250.0,
		"attack": 0.0004,
	})
	layers.append({
		"type": "noise",
		"gain": 1.0 * crunch,
		"attack": 0.01,
		"decay": 0.03 + 0.02 * crunch,
		"lp": 2500.0,
		"hp": 200.0,
		"delay": 0.02,
	})
	layers.append({
		"type": "modes", "gain": 0.8, "freqs": [170.0, 380.0, 690.0], "amps": [1.0, 0.8, 0.55],
		"decays": [0.035 + 0.03 * body, 0.03 + 0.02 * body, 0.025], "detune": 0.03,
	})
	return layers


## The struck material `m`'s own ring and crack.
static func _crash_struck(m: Dictionary) -> Array:
	var layers := []
	var freqs := []
	for f: float in m["modes"]:
		freqs.append(f * 0.85)
	if not freqs.is_empty():
		layers.append({
			"type": "modes",
			"gain": 0.5 if m["hard"] else 0.25,
			"freqs": freqs,
			"amps": m["amps"],
			"decays": m["decays"].map(func(d): return minf(float(d), 0.05)),
			"detune": 0.03,
		})
	layers.append({
		"type": "noise",
		"gain": 0.6,
		"decay": float(m["grit"]) * 2.0,
		"lp": float(m["lp"]),
		"hp": 150.0,
		"attack": 0.0005,
	})
	return layers


## What a crash of band `b` throws after it: glass and bits.
static func _crash_after(b: Dictionary) -> Array:
	var layers := []
	for i in roundi(2.0 * float(b["glass"])):
		layers.append({
			"type": "modes", "gain": 0.12, "freqs": [3200.0, 4700.0, 6100.0],
			"amps": [1.0, 0.7, 0.5], "decays": [0.018, 0.013, 0.01], "delay": 0.05 + 0.07 * i,
			"detune": 0.08,
		})
	for i in roundi(3.0 * float(b["debris"])):
		layers.append({
			"type": "noise",
			"gain": 0.15,
			"decay": 0.01,
			"lp": 3000.0,
			"hp": 600.0,
			"delay": 0.15 + 0.09 * i,
		})
	return layers
