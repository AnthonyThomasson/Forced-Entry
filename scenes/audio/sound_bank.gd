class_name SoundBank
## Audio domain: the sound library. A *profile* is a StringName that fully describes one sound —
## `shot/rifle`, `impact/metal/ricochet/heavy`, `impact/flesh/punch`, `footstep/wood/run`,
## `reload/rifle/in` — and `sound(profile, variant)` asks the profile's family for its recipe
## (`recipe_for`, by the profile's first part), renders it through SoundSynth once and caches the
## stream (a static cache, like PixelArt's, so it survives scene reloads). Each family holds its
## tables, its name rule (the `*_profile` functions, which render nothing) and its recipes:
## SoundGuns (`shot`, `reload`), SoundImpacts (`impact`), SoundFootsteps (`footstep`),
## SoundGrenades (`throw`, `grenade`, `explosion`, `tinnitus`) and SoundVehicles (`engine`,
## `ignition`, `door`, `skid`, `crash`). The bank keeps the round-weight `band` the guns and the
## impacts are voiced in, the list of every profile and the cache.
##
## Pieces of a profile:
## - gun: a GunConfig id (`pistol`, `smg`, `rifle`); an unknown gun is voiced as the gun of its
##   band.
## - material: what was struck: wood metal glass ceramic stone plastic fabric foliage electronics
##   flesh, `wall` (the empty material walls report) and `default` for anything else.
## - outcome: what the bullet did: `blocked` (embedded), `penetrate` (went through), `ricochet`; a
##   fist is `punch`.
## - band: the projectile's weight, from its penetration power (`SoundLibraryConfig.light_power_max`
##   / `heavy_power_min`): `light` (SMG), `medium` (pistol), `heavy` (rifle).
## - surface: the floor underfoot (SoundSurface): wood tile stone concrete carpet outdoor.
## - gait: `walk` or `run`.
## - stage: a reload's `out` (the magazine released and drawn) or `in` (seated, then the action
##   racked).
## - kind: a grenade's `stun` or `frag`: `throw/<kind>`, `grenade/<kind>/<surface>` (a bounce,
##   voiced by the floor it lands on), `explosion/<kind>`; and the one `tinnitus/whine` a deafened
##   listener hears.
## - vehicle: a vehicle's kind (`car`, `van`; an unknown one is voiced as a car): `engine/<vehicle>`
##   (a seamless loop the service pitches by the revs), `ignition/<vehicle>`,
##   `door/<vehicle>/<open|close|slide_open|slide_close>`; the tyres' `skid/tyre` (a loop); and
##   `crash/<material>/<band>`, the band by the closing speed (SoundVehicleConfig.crash_medium_speed
##   / crash_heavy_speed), `flesh` for a character struck.

const BAND_NAMES: Array[String] = ["light", "medium", "heavy"]

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


## Every profile the bank can voice (what the pre-warm and the sound dump walk through).
static func profiles() -> Array[StringName]:
	var out: Array[StringName] = []
	out.append_array(SoundGuns.profiles())
	out.append_array(SoundImpacts.profiles())
	out.append_array(SoundFootsteps.profiles())
	out.append_array(SoundGrenades.profiles())
	out.append_array(SoundVehicles.profiles())
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
		"throw", "grenade", "explosion", "tinnitus":
			out = SoundGrenades.recipe(parts)
		"engine", "ignition", "door", "skid", "crash":
			out = SoundVehicles.recipe(parts, profile)
	return out


## Forget every rendered sound (for tests).
static func clear_cache() -> void:
	_cache.clear()


## How many sounds are rendered and cached.
static func cached_count() -> int:
	return _cache.size()
