class_name SoundConfig
## The sound system's master switch and its mix (scenes/audio/): the master and category levels,
## the jitter, the voices and the ranges. A `class_name` holder of `static var`s — read as
## `SoundConfig.<name>`; there is no instance and no autoload (the autoload is `Sound`, the
## service). The library is `SoundLibraryConfig`, deafness `SoundDeafnessConfig` and the vehicles'
## sounds `SoundVehicleConfig`.
##
## Every sound is synthesized in code (SoundSynth) from a recipe SoundBank builds for a *profile*,
## then played by the `Sound` service through a small pool of positional voices. A sound belongs to
## one of eleven categories — `shot`, `impact`, `footstep`, `reload`, the grenades' `throw`,
## `grenade` (a bounce), `explosion` and `tinnitus`, and the vehicles' `engine` (a loop per running
## vehicle), `vehicle` (ignition, doors, crashes) and `skid` (a loop per sliding vehicle) — and the
## per-category tables below are keyed by those names.

## Master switch: off = the `Sound` service synthesizes, plays and posts nothing.
static var enabled: bool = true
## Overall trim (dB) added to every voice.
static var master_db: float = 0.0
## Trim (dB) per category, on top of each profile's own level.
static var category_db: Dictionary = {
	&"shot": 0.0, &"impact": -2.0, &"footstep": -8.0, &"reload": -6.0, &"throw": -6.0,
	&"grenade": -4.0, &"explosion": 3.0, &"tinnitus": -4.0, &"engine": -9.0, &"vehicle": -2.0,
	&"skid": -7.0,
}
## Random pitch swing either side of 1 (0.06 = ±6%) on every play, so a burst of identical events
## does not sound like one sample machine-gunned.
static var pitch_jitter: float = 0.06
## Random volume swing (dB) either side of the level, on every play.
static var volume_jitter_db: float = 1.5
## Per-category multiplier on those two swings. Steps are heard over and over, so they swing wider
## (a repeating sound is what makes a walk sound mechanical).
static var category_jitter_scale: Dictionary = { &"footstep": 1.7 }
## Most voices a category may have sounding at once; past it the oldest of that category is cut off.
static var category_voices: Dictionary = {
	&"shot": 6, &"impact": 8, &"footstep": 8, &"reload": 3, &"throw": 3, &"grenade": 4,
	&"explosion": 3, &"tinnitus": 1, &"engine": 4, &"vehicle": 6, &"skid": 3,
}
## Distance (px, at camera zoom 1) beyond which a category cannot be heard. The AI's own hearing
## radius (`hearing_radius`, 900) is the reference for how far a human-scale sound carries.
## A burst carries farther than a shot; the tinnitus is in the listener's own head, so it is never
## out of range.
static var category_range: Dictionary = {
	&"shot": 2400.0, &"impact": 1400.0, &"footstep": 900.0, &"reload": 800.0, &"throw": 900.0,
	&"grenade": 1000.0, &"explosion": 3200.0, &"tinnitus": 1.0e6, &"engine": 1400.0,
	&"vehicle": 1800.0, &"skid": 1600.0,
}
## True = the range grows as the camera zooms out (and shrinks as it zooms in), because Godot's 2D
## attenuation is measured in world px and a zoomed-out spectator would otherwise hear nothing.
static var range_follows_zoom: bool = true
