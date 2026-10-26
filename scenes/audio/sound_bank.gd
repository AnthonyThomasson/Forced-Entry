class_name SoundBank
## Audio domain: the sound library. A *profile* is a StringName that fully describes one sound —
## `shot/rifle`, `impact/metal/ricochet/heavy`, `impact/flesh/punch`, `footstep/wood/run`,
## `reload/rifle/in` — and `sound(profile, variant)` builds its recipe from the tables below
## and its families' (SoundFootsteps, SoundGuns, SoundImpacts), renders it through SoundSynth once
## and caches the stream (a static cache, like PixelArt's, so it survives scene reloads). Which
## profile an event gets is decided by the `*_profile` functions here and the families' profile
## functions, which render nothing.
##
## Pieces of a profile:
##   gun       a GunConfig id (`pistol`, `smg`, `rifle`); an unknown gun is voiced as the gun of its
##   band. material  what was struck: wood metal glass ceramic stone plastic fabric foliage
##             electronics flesh, `wall` (the empty material walls report) and `default` for
##             anything else.
##   outcome   what the bullet did: `blocked` (embedded), `penetrate` (went through), `ricochet`; a
##   fist is `punch`. band      the projectile's weight, from its penetration power
##             (`SoundLibraryConfig.light_power_max` / `heavy_power_min`): `light` (SMG), `medium`
##             (pistol), `heavy` (rifle).
##   surface   the floor underfoot (SoundSurface): wood tile stone concrete carpet outdoor.
##   gait      `walk` or `run`.
##   stage     a reload's `out` (the magazine released and drawn) or `in` (seated, then the action
##   racked). kind      a grenade's `stun` or `frag`: `throw/<kind>`, `grenade/<kind>/<surface>` (a
##             bounce, voiced by the floor it lands on), `explosion/<kind>`; and the one
##             `tinnitus/whine` a deafened listener hears.
##   vehicle   a vehicle's kind (`car`, `van`; an unknown one is voiced as a car):
##             `engine/<vehicle>` (a seamless loop the service pitches by the revs),
##             `ignition/<vehicle>`, `door/<vehicle>/<open|close|slide_open|slide_close>`; the
##             tyres' `skid/tyre` (a loop); and `crash/<material>/<band>`, the band by the closing
##             speed (SoundVehicleConfig.crash_medium_speed / crash_heavy_speed), `flesh` for a
##             character struck.

const BAND_NAMES: Array[String] = ["light", "medium", "heavy"]
## The grenades (`docs/grenades.md`, G14). The kinds a profile may name:
const GRENADE_KINDS: Array[String] = ["stun", "frag"]
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
const GRENADE_BODIES := {
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
const GRENADE_SURFACES := {
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
## The vehicles. engine: the loop's firing train, `rate` firings a second at idle (whole firings per
## `ENGINE_LOOP` s and a whole number of `pattern`s, so it loops without a seam; the service pitches
## it up with the revs), each a noise burst of `burst` s through `lp`, its level cycling through
## `pattern` (the cylinders, so it chugs rather than buzzes) and rung through the exhaust's
## resonances `pipe` ([Hz, level, decay s]); `noise` is how much of the raw burst is heard. crank:
## the starter's [strokes, gap s, whine Hz]; door: the pitch scale (a heavier door lower) and level
## of its clunks; slide: a sliding door. db trims each sound's level. The van is the bigger,
## slower-firing, deeper engine.
const ENGINE_LOOP := 1.0
const VEHICLES := {
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

## Rendered sounds: "profile#variant" -> { stream, level_db }. Written on the main thread only.
static var _cache: Dictionary = {}
## How many sounds were synthesized on the main thread (for tests: the service's pre-warm renders on
## a worker, so after launch only a sound nobody pre-warmed is).
static var main_thread_renders := 0


# --- Choosing a profile (no rendering) ------------------------------------------------------


## The band (`light` / `medium` / `heavy`) a projectile of penetration `power` is voiced in.
static func band(power: float) -> String:
	if power < SoundLibraryConfig.light_power_max:
		return "light"
	if power >= SoundLibraryConfig.heavy_power_min:
		return "heavy"
	return "medium"


## The throw profile of a grenade of `kind`; &"" for an unknown kind.
static func throw_profile(kind: StringName) -> StringName:
	return StringName("throw/" + String(kind)) if THROWS.has(String(kind)) else &""


## The clatter profile of a grenade of `kind` landing on `surface` (a SoundSurface name; an unknown
## surface is the open ground); &"" for an unknown kind.
static func grenade_profile(kind: StringName, surface: StringName) -> StringName:
	if not GRENADE_BODIES.has(String(kind)):
		return &""
	var s := String(surface) if GRENADE_SURFACES.has(String(surface)) else "outdoor"
	return StringName("grenade/%s/%s" % [kind, s])


## The explosion profile of a burst of `kind`; &"" for an unknown kind.
static func explosion_profile(kind: StringName) -> StringName:
	return StringName("explosion/" + String(kind)) if EXPLOSIONS.has(String(kind)) else &""


## The whine a deafened listener hears.
static func tinnitus_profile() -> StringName:
	return &"tinnitus/whine"


## A vehicle kind the bank voices: `kind` itself, or a car for an unknown one.
static func _vehicle_kind(kind: StringName) -> String:
	return String(kind) if VEHICLES.has(String(kind)) else "car"


## The engine loop of a vehicle of `kind`.
static func engine_profile(kind: StringName) -> StringName:
	return StringName("engine/" + _vehicle_kind(kind))


## The starter cranking and the engine catching, for a vehicle of `kind`.
static func ignition_profile(kind: StringName) -> StringName:
	return StringName("ignition/" + _vehicle_kind(kind))


## A door of a vehicle of `kind` at `stage` (`open`, `close`, `slide_open`, `slide_close`; a slide
## is voiced only for a kind with a sliding door). &"" for any other stage.
static func door_profile(kind: StringName, stage: StringName) -> StringName:
	var k := _vehicle_kind(kind)
	if (not DOOR_STAGES.has(String(stage))
			or (String(stage).begins_with("slide") and not VEHICLES[k]["slide"])):
		return &""
	return StringName("door/%s/%s" % [k, stage])


## The tyres sliding (a loop).
static func skid_profile() -> StringName:
	return &"skid/tyre"


## The crash band (`light` / `medium` / `heavy`) of an impact at closing speed `speed` (px/s).
static func _crash_band(speed: float) -> String:
	if speed >= SoundVehicleConfig.crash_heavy_speed:
		return "heavy"
	if speed >= SoundVehicleConfig.crash_medium_speed:
		return "medium"
	return "light"


## A vehicle striking `material` (a struck surface's; "" is a wall, `flesh` a character) at closing
## speed `speed`.
static func crash_profile(material: String, speed: float) -> StringName:
	var mat := ("wall"
			if material == ""
			else (material if SoundImpacts.MATERIALS.has(material) else "default"))
	return StringName("crash/%s/%s" % [mat, _crash_band(speed)])


## Every profile the bank can voice (what the pre-warm and the sound dump walk through).
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(SoundGuns.profiles())
	out.append_array(SoundImpacts.profiles())
	out.append_array(SoundFootsteps.profiles())
	for kind: String in GRENADE_KINDS:
		out.append(StringName("throw/" + kind))
		out.append(StringName("explosion/" + kind))
		for surface: String in GRENADE_SURFACES:
			out.append(StringName("grenade/%s/%s" % [kind, surface]))
	out.append(tinnitus_profile())
	for kind: String in VEHICLES:
		out.append(StringName("engine/" + kind))
		out.append(StringName("ignition/" + kind))
		for stage in DOOR_STAGES:
			if not stage.begins_with("slide") or VEHICLES[kind]["slide"]:
				out.append(StringName("door/%s/%s" % [kind, stage]))
	out.append(skid_profile())
	for mat: String in SoundImpacts.MATERIALS:
		for b: String in CRASH_BANDS:
			out.append(StringName("crash/%s/%s" % [mat, b]))
	return out


# --- Rendering ------------------------------------------------------------------------------


## The sound of `profile`, variant number `variant`: { stream: AudioStreamWAV, level_db: float }
## (the profile's own level trim in dB). Rendered the first time it is asked for, then cached. {}
## for a profile that does not exist.
static func sound(profile: StringName, variant: int = 0) -> Dictionary:
	var key := _key(profile, variant)
	if _cache.has(key):
		return _cache[key]
	var entry := render(profile, variant)
	if not entry.is_empty():
		_cache[key] = entry
	return entry


## The sound `sound` would cache for `profile`'s variant `variant`, rendered now and not cached: the
## same bytes every time. It touches nothing shared off the main thread, so a worker may call it
## (the service's pre-warm), then `file` the result on the main thread.
static func render(profile: StringName, variant: int = 0) -> Dictionary:
	var recipe := recipe_for(profile)
	if recipe.is_empty():
		return {}
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		main_thread_renders += 1
	return {
		"stream": SoundSynth.render(recipe, hash(_key(profile, variant))),
		"level_db": float(recipe.get("level_db", 0.0)),
	}


## Cache `entry`, a `render` of `profile`'s variant `variant`, unless that variant is cached already
## (it played before its pre-warm finished: the stream playing stays the one cached). Main thread
## only.
static func file(profile: StringName, variant: int, entry: Dictionary) -> void:
	var key := _key(profile, variant)
	if not entry.is_empty() and not _cache.has(key):
		_cache[key] = entry


## Whether `profile`'s variant `variant` is rendered and cached.
static func is_cached(profile: StringName, variant: int = 0) -> bool:
	return _cache.has(_key(profile, variant))


## The cache key of `profile`'s variant `variant`, which also seeds its render.
static func _key(profile: StringName, variant: int) -> String:
	return "%s#%d" % [profile, variant]


## The synthesis recipe of `profile` ({} if unknown): its family's (the profile's first part).
static func recipe_for(profile: StringName) -> Dictionary:
	var parts := String(profile).split("/")
	var out := {}
	match parts[0]:
		"shot", "reload":
			out = SoundGuns.recipe(parts)
		"impact":
			out = SoundImpacts.recipe(parts)
		"footstep":
			out = SoundFootsteps.recipe(parts)
		_:
			out = (_named_recipe(parts[0], parts[1])
					if parts.size() == 2
					else _parted_recipe(parts, profile))
	return out


## The recipe of a two-part profile, `family/id` ({} if unknown).
static func _named_recipe(family: String, id: String) -> Dictionary:
	var recipe := {}
	match family:
		"throw":
			if THROWS.has(id):
				recipe = _throw(id)
		"explosion":
			if EXPLOSIONS.has(id):
				recipe = _explosion(id)
		"tinnitus":
			if id == "whine":
				recipe = _tinnitus()
		"engine":
			if VEHICLES.has(id):
				recipe = _engine(id)
		"ignition":
			if VEHICLES.has(id):
				recipe = _ignition(id)
		"skid":
			if id == "tyre":
				recipe = _skid()
	return recipe


## The recipe of a profile of three parts or more (`p`, split from `profile`), {} if unknown.
static func _parted_recipe(p: PackedStringArray, profile: StringName) -> Dictionary:
	var recipe := {}
	match p[0]:
		"grenade":
			if p.size() == 3 and GRENADE_BODIES.has(p[1]) and GRENADE_SURFACES.has(p[2]):
				recipe = _grenade(p[1], p[2])
		"door":
			if (p.size() == 3
					and VEHICLES.has(p[1])
					and door_profile(StringName(p[1]), StringName(p[2])) == profile):
				recipe = _door(p[1], p[2])
		"crash":
			if p.size() == 3 and SoundImpacts.MATERIALS.has(p[1]) and CRASH_BANDS.has(p[2]):
				recipe = _crash(p[1], p[2])
	return recipe


## Forget every rendered sound (for tests).
static func clear_cache() -> void:
	_cache.clear()


## How many sounds are rendered and cached.
static func cached_count() -> int:
	return _cache.size()


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
	var b: Dictionary = GRENADE_BODIES[kind]
	var s: Dictionary = GRENADE_SURFACES[surface]
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


## A running engine at idle: one period of its firing train, every firing a burst rung through the
## exhaust's resonances, the cylinders each a little different (`pattern`) and never quite even
## (`spread`, `jitter`), so it chugs rather than buzzes. A seamless loop the service plays faster as
## the revs climb.
static func _engine(kind: String) -> Dictionary:
	var v: Dictionary = VEHICLES[kind]
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
	var v: Dictionary = VEHICLES[kind]
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
	var door: Array = VEHICLES[kind]["door"]
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
