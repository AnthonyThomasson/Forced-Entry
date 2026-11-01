---
name: domain-audio
description: Use when editing scenes/audio/, adding or retuning a sound (guns, impacts, footsteps, reloads, grenades, vehicles, doors, crashes), changing how events map to sounds, or asserting on sound in a test.
---

# Audio domain (`scenes/audio/`)

A leaf: it imports only General's `EventBus`. Other domains **post EventBus events**; the `Sound` autoload listens and plays.
There are no audio files: `SoundSynth` renders every sound from a recipe into an `AudioStreamWAV`, so a new material or gun is a
row in a table. Interfaces: 10 (the topics below, and the `&"sound"` it posts), 13 (`audio.sound`, a sandbox's own voice), 16 (`SoundSurface`), 18 (`Sound.focus`), 19 (the
vehicle a loop follows). Tests: `tests/audio/` (`tools/run_tests.sh audio`); NPC hearing of footsteps is `docs/hearing.md`.

A sandbox renders a sound itself: `SoundBank.recipe_for` / `SoundSynth.render` → `AudioStreamWAV` on its own `AudioStreamPlayer2D`; `Sound` hears nothing of it.

| File | Role |
|---|---|
| `sound.gd` (autoload `Sound`) | The service: EventBus listener, variant / pitch / volume, range cull, voice pool, deafness, vehicle loops, the pre-warm. |
| `sound_bank.gd` (`SoundBank`) | The cache and dispatch: `sound(profile, variant)`, `recipe_for(profile)` (the family is the profile's first part), `profiles()`, `band(power)`. |
| `sound_synth.gd` (`SoundSynth`) | `render(recipe, seed)`: layers (`noise`, `tone`, `modes`, `pulses`), optional `vary` (each seed its own take) and `drive`, normalised to `peak`. Same recipe + seed gives the same bytes. |
| `sound_guns.gd`, `sound_impacts.gd`, `sound_footsteps.gd`, `sound_grenades.gd`, `sound_vehicles.gd`, `sound_doors.gd` | The six families: the tables, the profile-name functions and the recipes. A house door's: `doors.md`. |
| `sound_surface.gd` (`SoundSurface`) | Static floor registry (the `BloodSurface` pattern): `register`, `unregister`, `at(pos)` (newest floor wins; none, the street included, is `outdoor`), `surface_for(material, pattern)`. |
| `sound_config.gd`, `sound_library_config.gd`, `sound_deafness_config.gd`, `sound_vehicle_config.gd` | Tuning. `SoundConfig`: the master switch and the per-category mix (`category_db`, `category_voices`, `category_range`, `category_jitter_scale`, `range_follows_zoom`, jitters). `SoundLibraryConfig`: sample rate, `category_variants`, the weight bands, `rng_seed`, `prewarm`. `SoundDeafnessConfig`: the muffle and the tinnitus. `SoundVehicleConfig`: engine pitch and load, skid, the crash speed bands. |

## Profiles

A profile is a `StringName` that fully determines a sound, so tests assert on it without rendering:
`shot/<gun>`, `impact/<material>/<outcome>/<band>` (outcome `blocked` / `penetrate` / `ricochet`; a fist is
`impact/<material>/punch`, no band), `footstep/<surface>/<walk|run>`, `reload/<gun>/<out|in>`, `throw/<kind>`,
`grenade/<kind>/<surface>` (a bounce), `explosion/<kind>`, `tinnitus/whine`, `engine/<kind>`, `ignition/<kind>`,
`door/<kind>/<open|close|slide_open|slide_close>`, `skid/tyre`, `crash/<material>/<light|medium|heavy>` (`crash/flesh/<band>` is a
character struck), `leaf/...` (a house door: `doors.md`). Rules that hold across them:

- An unknown gun borrows its band's recipe; an unknown material is `default`, a wall's empty material `wall`; an unknown vehicle kind
  is voiced as a car; an unknown landing floor is open ground. A profile may not run past 1 s (`tests/audio/bank_test.gd`).
- **Bands** come from penetration power (`SoundBank.band`: `light`, `medium`, `heavy`); heavier is lower, louder and adds a sub boom.
- A `hard` material rings long on a ricochet; a soft one whips. A round stopped by armour posts the armour's material
  (`docs/outfits.md` O6), so it sounds as that, not as flesh.
- The synth normalises every sound, so a quiet one says so with a `db` trim in its table row, which `SoundBank` folds into `level_db`.
- Loop recipes (`engine`, `skid`, `tinnitus`) skip the fade and fold what a layer still sounds past the clip's end back onto its
  start, so they join without a seam; a steady tone must be a whole number of cycles of the length.

## Events the service listens to

| Topic | Posted by | Becomes |
|---|---|---|
| `&"shot"` | `GunItem.secondary` | `shot/<gun>` at the muzzle |
| `&"hit"` | `Projectile._deal`, `Character._post_melee_hit`, `Explosion` | an impact by `outcome`. A hit with none of `blocked` / `penetrate` / `ricochet` / `punch` (a blast's, none) is silent; a fly-over posts nothing. |
| `&"footfall"` | `CharacterFootsteps._report` | `footstep/<floor under the sole>/<gait>` |
| `&"reload"` | `CharacterAmmo` | stage `start` → `out`, `done` → `in`; other stages silent (a cancelled reload never posts `done`) |
| `&"throw"` | `GrenadeItem._release` | `throw/<kind>` |
| `&"grenade"` | `ThrownGrenade._post` | stage `bounce` → `grenade/<kind>/<floor>`; `rest` silent |
| `&"explosion"` | `Explosion.frag` / `.stun` | `explosion/<kind>` (the same event shakes the camera) |
| `&"stun"` | `CharacterStun.take` (via `Character.take_stun`) | only for the `focus` character with `deaf` > 0: the tinnitus |
| `&"vehicle"` | `vehicle.gd` | stage `ignition`, `door_*` / `slide_*`, `crash`, `bump_character` (louder by `speed / crash_speed_ref` within the band); category `vehicle` |
| `&"engine"`, `&"skid"` | `vehicle_drive.gd` | stage `start` / `stop` the vehicle's loop |
| `&"door"` | `door.gd` | a house door's stage → `leaf/...` (`doors.md`); category `door` |

It posts `&"sound"` `{ kind, profile, variant, position, volume_db, pitch }` for every sound it accepts; that is what tests assert on.

## How a sound is played

1. `Sound._on_posted` returns at once when `SoundConfig.enabled` is off or the topic is not its own; the event becomes a profile.
2. Range: `reach_from` is 0 beyond `category_range` (scaled by `1/zoom` when `range_follows_zoom`, `range_at_zoom`); no camera
   means in range. The same number becomes the player's `max_distance`.
3. A variant is drawn from the service's **own RNG** (`rng_seed`, never the gameplay RNG), never the one played last for that
   profile; pitch and volume are jittered, widened per category by `category_jitter_scale`. Loudness adds `level_db`,
   `category_db`, `master_db` and the event's own (a step by speed, a bullet by `speed_factor`, a punch by damage).
4. A voice: the category's oldest is cut off when it is at `category_voices`; else a free one; else a new `AudioStreamPlayer2D`
   child (the pool grows lazily, never past the caps' sum). A voice is free when its clip has played, counted in **simulated
   time** (`_now += delta`), not read from the player: a fixed-FPS test run outpaces the audio thread.

## Why the sounds are voiced as they are

Keep these when adding a sound; each reads wrong otherwise. Tests carry the measured bounds.

- **A step is a heel then a softer toe tap 45–62 ms later**, with a faint rustle, from 6 takes with wider jitter than other
  sounds; the cadence is the walk cycle's. **Every surface is a dull thud on purpose:** high-passed bursts and 1.5–2.7 kHz rings
  read as tinny, so the heel thump leads, scuffs are low-passed, no floor keeps a ring. Give a new surface a `thump` first and
  keep scuff cut-offs low. Tests: `footstep_variety_test.gd`, `footstep_tone_test.gd`.
- **An impact has weight:** every impact carries a low body thump however hard the thing struck, so metal and glass thud as well as
  ring; the weight band scales body, pitch and level (`SoundImpacts.BANDS`), the faster round or harder punch is louder.
  Test: `impact_weight_test.gd`. To measure, `tools/dump_sounds.gd`, then analyse with `tests/_audio/sound_probe.gd` (`brightness`,
  `low_share`, `low_weight`).
- **A vehicle's door is a thunk, not a creak (a house door's too):** its clicks are short noise bursts and the body is low tones; creaks and panel rings above
  ~300 Hz read high-pitched. Keep a new door sound's clicks short and its weight under ~150 Hz. Test: `vehicle_door_tone_test.gd`.

## Deafness: `Sound.focus`, `muffled()`, the tinnitus (`docs/grenades.md` G14)

`Sound.focus` is a character node (Main sets the human and clears it at teardown; null is nobody's ears, so an AI's stun is
silent). Audio reads only its `stun.view()` (`deaf`), duck-typed.

- `muffled()` is true while the focus's `deaf` > 0 (false for null, freed or non-stunnable); it lifts exactly when deafness ends.
- The muffle: every game voice plays on the `GameSound` bus (an `AudioEffectLowPassFilter`, made in `Sound._ready`); while muffled
  the filter closes toward `muffle_cutoff_hz` and lifts slowly, so the bang that deafens is heard, then goes dull. Headless,
  nothing is heard, so tests assert `muffled()`.
- The tinnitus: a `&"stun"` for the focus with `deaf` > 0 starts one `tinnitus/whine` voice on the Master bus (so the muffle does
  not dull it), once per stun. It loops and **follows the deafness**: each frame its `until` and volume come from `deaf`, fading
  over `tinnitus_tail`; range `1e6` (it is in the listener's head).

## Vehicle loops (`engine`, `skid`)

One looping voice per vehicle and kind, keyed by instance id (`_loops`); a second `start` is ignored. `_start_loop` plays variant 0
with `until` = INF and is not range-culled (the listener may come closer); `_follow_loops` moves it to the vehicle each frame and
glides pitch and level (`loop_ease`) toward `_loop_aim`, read duck-typed (`engine_state()`, slip, speed), so Audio imports nothing
from Vehicles. An engine that no longer runs ends its loop. A loop ends on its `stop` event, its vehicle freed, its engine
stopped, or its voice taken by a newer one of the category. `loop_of(vehicle, kind)` is the test read.

## Gotchas

- `play()` outside the tree logs an engine error (which fails a test); voices are only children of the autoload.
- On quit `Sound._exit_tree` frees the voices and pauses 80 ms so the mixer can drop its playbacks; without it a process that quits
  mid-sound reports leaked `AudioStreamPlaybackWAV` objects.
- With a camera present (the test runner has one) range culling is live: audio tests not about distance set
  `SoundConfig.category_range` to `Probe.EVERYWHERE` (`tests/_audio/sound_probe.gd`).
- Sounds render lazily (1–33 ms each); with a display they are pre-rendered after launch, every variant of every profile (the
  count per profile follows `_variant_count(_category_of(profile))`: a vehicle's ignition, door and crash count as `vehicle`),
  because a variant first synthesised in a fight is a 9–35 ms hitch. **The pre-warm renders on a worker thread** (`Sound.warm`:
  one `WorkerThreadPool` task calling `SoundBank.render`, which touches nothing shared); the main thread files each finished sound
  into the cache at the next `_process` (`SoundBank.file`, main thread only, keeps a variant rendered on demand meanwhile).
  `warming()` / `finish_warming()` and `_exit_tree` wait for the worker. Headless tests render on first use
  (`Perf.warm_sounds()` in `tests/_perf/perf_probe.gd` does what the pre-warm would have). Tests: `prewarm_off_main_thread_test.gd`,
  `prewarm_covers_every_variant_test.gd`; the library's time is `perf/audio_bank_render`.
- Headless uses the Dummy audio driver: playback is accepted and silent; assert on `&"sound"` events, `active()`, `muffled()`, `loop_of`.

## Adding to it

- **A gun:** a row in `GunConfig`, and a recipe row in `SoundGuns.SHOTS` (until then it borrows its band's).
- **A material:** a row in `SoundImpacts.MATERIALS`. **A floor surface:** a row in `SoundFootsteps.SURFACES` and a case in
  `SoundSurface.surface_for`. **A vehicle kind:** a row in `SoundVehicles.KINDS`.
- **A new category:** a topic posted by the owning domain, a `*_profile` and recipe in its family's file (a new family: a
  `Sound<Family>` file with `profiles()` and `recipe(parts)`, a row in `SoundBank.recipe_for` and a line in `SoundBank.profiles`),
  a case in `Sound._on_posted`, entries in `SoundConfig`'s category tables and `SoundLibraryConfig.category_variants`, and a test.
- **Audition:** `godot --headless --path . -s tools/dump_sounds.gd -- --out=DIR [--variants=2] [--filter=impact/metal]` writes
  every profile as a `.wav` (smoke test: `tools/tests/test_dump_sounds.py`).
