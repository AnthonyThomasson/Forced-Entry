class_name SoundDeafnessConfig
## Deafness (`docs/grenades.md` G14), for the `Sound` service: the muffle's cut-offs, attack and
## release, and the tinnitus's tail. A `class_name` holder of `static var`s, read as
## `SoundDeafnessConfig.<name>`; there is no instance and no autoload.

## While the `Sound.focus` character is deafened, game audio (every voice but the tinnitus) goes
## through a low-pass at this cut-off (Hz) ...
static var muffle_cutoff_hz: float = 650.0
## ... which is open (this cut-off) when it is not.
static var muffle_open_hz: float = 20_500.0
## How fast the muffle closes and lifts, in fractions of the way per second (a bang cuts the sound
## in at once, the hearing returns slowly).
static var muffle_attack: float = 12.0
static var muffle_release: float = 0.9
## The tinnitus follows the deafness: its last this-many seconds fade out with it, and a stun
## shorter than `tinnitus_full_s` brings it in quieter.
static var tinnitus_tail: float = 1.5
static var tinnitus_full_s: float = 3.0
