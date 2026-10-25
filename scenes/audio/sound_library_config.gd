class_name SoundLibraryConfig
## The sound library's tuning (scenes/audio/: SoundBank, SoundSynth, the `Sound` service): the
## sample rate and peak, the variants per profile, the round-weight bands, the seed and the prewarm.
## A `class_name` holder of `static var`s, read as `SoundLibraryConfig.<name>`; there is no instance
## and no autoload.

## Sample rate (Hz) sounds are rendered at.
static var sample_rate: int = 22_050
## Louder than this (0..1) never leaves the synth: every sound is normalized to it.
static var peak: float = 0.9
## Distinct renders per profile; each play picks one at random, so repeats differ.
static var variants: int = 2
## Renders per profile for the categories that want more than `variants`: a step is heard far more
## often than a shot, so it has more different takes to draw from.
static var category_variants: Dictionary = {
	&"footstep": 6, &"grenade": 3, &"tinnitus": 1, &"engine": 1, &"skid": 1,
}
## A projectile's penetration power below this is "light" (SMG); the bands impacts are voiced in.
static var light_power_max: float = 0.9
## A projectile's penetration power from this up is "heavy" (rifle); between the two it is "medium"
## (pistol).
static var heavy_power_min: float = 1.6
## Seed of the private RNG that picks variants and jitter. Sound never touches the gameplay RNG.
static var rng_seed: int = 1177
## True = render the library on a worker thread after launch (`Sound.warm`) so no sound hitches the
## first time it plays. Skipped when there is no display (tests render lazily).
static var prewarm: bool = true
