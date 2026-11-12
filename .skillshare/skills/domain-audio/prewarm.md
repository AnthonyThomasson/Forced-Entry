# The sound pre-warm (`Sound.warm`, `warming()`, `finish_warming()`)

Sounds render lazily (1–33 ms each); with a display they are pre-rendered after launch, every variant of every profile (the count per
profile follows `_variant_count(_category_of(profile))`: a vehicle's ignition, door and crash count as `vehicle`), because a variant
first synthesised in a fight is a 9–35 ms hitch.

- **The pre-warm renders on a worker thread** (`Sound.warm`: one `WorkerThreadPool` task calling `SoundBank.render`, which touches
  nothing shared); the main thread files each finished sound into the cache at the next `_process` (`SoundBank.file`, main thread
  only, keeps a variant rendered on demand meanwhile). It takes about 9 s from launch.
- `warming()` is true while the worker renders or its sounds are not all filed; `finish_warming()` and `_exit_tree` wait for the worker.
- **Main waits on `warming()`** (interface 18): `_on_setup_chosen` keeps the setup window up with a status line, and `start_match`
  (a start that skips the window, a test) waits a frame at a time, before the match builds. So no match plays before the library is
  cached and `SoundBank.main_thread_renders` stays put through the first gunfire (`tests/general/match_sounds_prewarmed_test.gd`).
- Headless tests render on first use (`Perf.warm_sounds()` in `tests/_perf/perf_probe.gd` does what the pre-warm would have).
- Tests: `prewarm_off_main_thread_test.gd`, `prewarm_covers_every_variant_test.gd`; the library's time is `perf/audio_bank_render`.
