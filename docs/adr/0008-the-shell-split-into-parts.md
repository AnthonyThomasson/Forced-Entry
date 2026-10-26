# The shell split into parts: root, input, camera, canvas, sound bank, lighting, objects, menus and the Testing API

Thirteen files outside the actors and the AI were over gdstyle's `quality/max-file-length` (1000),
`max-class-variables` (15) or `max-public-methods` (20), which issue #76 turns on with no exclusion (lines as `wc -l`
counts them, here and below):
- `main.gd` (36 vars), `camera_controller.gd` (33 vars), the `Keybinds` autoload (22 public);
- `PixelCanvas` (27 public), `SoundBank` (1660 lines, 24 public), `WorldLighting` (17 vars), `EnvironmentObject`
  (22 vars);
- the command menu (20 vars), `TestContext` (24 vars, 32 public), `TestSession` (17 vars), `TestBatch` (23 public), the
  test browser window (20 vars);
- the coverage tool's probe (30 vars).

They are of different kinds, and each is split the way its kind already reads:
- **Tuning that no scene authors becomes a static holder** (ADR 0003): the camera's twenty exports go to
  `CameraConfig` (follow, framing, zoom, hand pan) and `CameraShakeConfig` (the explosion shake, its `shake_` prefix
  dropped). `target_path` and `pan_enabled`, which a scene or the test runner sets per instance, stay exports.
- **The root's authoring surface becomes one exported `Resource`, `main.run` (`MainRun`).** A Node child would be
  missing where tests build Main from its script. A static would carry the mode across `return_to_setup()`'s reload.
  ADR 0006's objection to a `Resource`, an override shared by every instance, does not apply to the one Main, and
  `MainRun` is `resource_local_to_scene` so it never does: a scene that authors a `run` hands each Main it instantiates
  its own copy, and Main's runtime writes (`run.spectator_mode`, `run.debug_overlays`) never outlive a
  `reload_current_scene`. Main's endless state becomes a data leaf, `_endless`, and its overlay wiring a part holding
  Main, `_overlays`. Its seven `show_*` exports go: each repeated the `OverlayRegistry` default, and nothing set them.
  `endless_delay` and `endless_time_limit` stay exports on Main (the coverage tool reads the second by name).
- **An autoload keeps what gameplay reads and hands a separable topic to a part.** `Keybinds` keeps the action table
  and the twelve typed input readers. Its rebinding store and the saved format it owns become `Keybinds.bindings`, and
  a binding's current event (`event_of`) goes private on it.
- **A drawing API keeps its drawing methods.** The shape type leaves `PixelCanvas` as `PixelShape` /
  `PixelConvexShape` (`extends PixelShape`), with its static factories (`rounded`, `ellipse`, `disc`, `bowed`) and
  `line_points`. The tone ramp goes to `ArtSurfaceConfig.tones`, the holder it reads. `clear` was
  `fill(s, CLEAR, 0)` and goes. A painter's call stays one name, and nothing is allocated per draw.
- **A static library splits per family.** `SoundBank` keeps the cache, the profile list, the dispatch and the
  round-weight band. Each sound family (`SoundGuns`, `SoundImpacts`, `SoundFootsteps`, `SoundGrenades`,
  `SoundVehicles`) holds its tables, its name rule and its recipes, moved verbatim, so every sound is the same bytes.
- **An entity's state goes to the parts it owns** (ADR 0004):
  - a world piece's look fields to `piece.look`, and its Physics wiring to `piece.physics`;
  - the lighting's flash pool to a part, `_pool`;
  - the command menu's widget tree to a `Panel` child (`command_panel.gd`), and the test window's list to a `Tree`
    subclass (`test_browser_list.gd`, the window's `_tree`).
  The contracts stay on the body: hittable, interactable, `get_lights`, `hit_marks`, and the menu's and window's
  interface APIs.
- **The Testing API keeps the test verbs.** `TestContext` keeps the twenty verbs a test's `run(t)` calls: lookup,
  waiting, the event log, the assertions and `finish`. The run's verdict and failure bundle move to `verdict` and
  `bundle`, parts the session reads. The declared match is read off the world (`t.world.match_handle`,
  `t.world.squad(f)`, `t.world.player_stack`), and the Von forwarder gives way to `DecisionStub.requests`. `bind` and
  `record` go: the session sets the context's `world` and `rooms` and appends its `events`. `TestSession`'s Von gate
  becomes `von`. `TestBatch` privatises the six methods only it calls.
- **The probe keeps one template file.** The coverage tool drops its probe into any project as one file, so its parts
  (`Run`, `Matches`, `MatchCost`, `Tests`) are inner classes.

Family 4's rules apply:
- a part member read from outside is public, without its underscore or its part's prefix;
- the parts of a RefCounted or freed-by-hand owner never store it (`TestContext`'s parts hold none: a part method that
  needs the context takes it at the call);
- a Node owner's parts may hold it (Main, `WorldLighting`, the piece, the session, the probe).

A part nobody outside its owner names is a preload const, or an inner class in the probe. A new global name is added
only where an export must name one (`MainRun`), where a holder is tuning (the camera's), or where other files call it
(the shapes, the sound families).

Decisions taken while the parts were built:
- **The root.** `MainOverlays.route(flag, on, handle)` names its match `handle`, since `match` is a GDScript keyword;
  `MainOverlays.initial(debug)` seeds `flags` (each registry default, the saved toggles over it, all off without Debug)
  and returns nothing.
- **The sound families.** The bank dispatches on the profile's first part, one match row per family. Inside a family
  the consts drop the family word (`SoundGrenades.KINDS`, `SoundVehicles.KINDS`), a footstep's and an impact's chooser
  is `profile(...)`, `grenade_profile` is `bounce_profile`, and `SoundVehicles.recipe(parts, profile)` takes the whole
  profile, which an unknown crash material needs.
- **The canvas.** The base↔subclass reference between `PixelShape`'s factories and `PixelConvexShape` loads, so the
  convex factories stay on the base. The four `clear` sites call `fill(<shape>, PixelCanvas.CLEAR, 0)`.
- **The UI.** The test list's play signal is `play_requested(path)` (gdstyle's past-tense signal rule). Locals that
  would shadow `Control.size` are `extent`, `font_size` and `side`, and the panel's local in its `dock()` is `vertical`.
- **The probe.** Its run config's seed is `Run.seed_value` (`seed` is a built-in), and `MatchCost.record(out, frames,
  bus_seen, deaths)` takes the deaths too, so a unit's JSON keys keep their order.
- **The Testing API.** `VonGate.skip_reason(announce: Callable)` is handed the session's `status.emit`: the `status`
  signal stays on the session, named there, since the engine analyzer fails an unused signal. Two test helpers that took
  `t` only for the Von forwarder lost it (`Entry.asked(prefix)` in `tests/_ai/entry_probe.gd`, `_offered(id)`).
  `TestWorld` gains `squad(faction)`.

## Consequences

**The counts** (lines / vars / public, before → after): `main.gd` 598 / 36 / 3 → 482 / 14 / 3; `camera_controller.gd`
291 / 33 / 1 → 258 / 13 / 1; `keybinds.gd` 412 / 0 / 22 → 253 / 1 / 12; `pixel_canvas.gd` 778 / 10 / 27 → 416 / 10 /
20; `sound_bank.gd` 1660 / 2 / 24 → 142 / 2 / 9; `world_lighting.gd` 456 / 17 / 5 → 367 / 8 / 5;
`environment_object.gd` 269 / 22 / 5 → 166 / 14 / 5; `command_menu.gd` 676 / 20 / 5 → 514 / 12 / 5;
`test_context.gd` 498 / 24 / 32 → 228 / 8 / 20; `test_session.gd` 351 / 17 / 8 → 294 / 11 / 7; `test_batch.gd` 385 / 7
/ 23 → 385 / 7 / 17; `test_browser_window.gd` 530 / 20 / 3 → 286 / 12 / 3; `probe.gd` 550 / 30 / 0 → 627 / 11 / 5 (its
inner classes 8 / 1, 9 / 3, 9 / 2 and 4 / 2). Every new part is within all three limits, the largest `sound_vehicles.gd`
at 686 lines. The tuning holders go from 77 (76 and family 5's
`SquadFollowConfig`, ADR 0007) to 79.

**Callers:**
- Painters write `PixelShape.rounded(…)` and `ArtSurfaceConfig.tones(base)`.
- `Sound` and the tests call `SoundImpacts.profile(…)` and the like.
- `Settings` calls `Keybinds.bindings.overrides()`.
- Tests read `t.world.squad(f)`, `DecisionStub.requests`, `t.bundle.screenshot(…)` and `t.verdict.expect_log(…)`: 210
  lines in 112 files of `tests/` and `sandboxes/` gave way to 228, most of them a scripted rewrite of one receiver.

**What stays the same:**
- The saved settings file, every sound's samples and every painter's pixels.
- The menu's and the window's node names and signals. The interface APIs of the command menu (21), the test browser
  (13) and `WorldLighting` (20).
- `SoundBank.recipe_for` (13).
- The coverage tool's counts.

**Proof**, each run once and not checked in (a golden file would pin the art and sound design):
- The sound output: a dump of every profile at six variants, 1308 samples of 218 profiles, plus the 40 malformed
  profiles refused and every chooser over its arguments, identical to the base at every commit.
- The pixels: a hash of every `PixelArt` cache and emissive image over every house plan at two seeds, every catalogue
  piece at four facings and three neons, about a hundred characters and both vehicles, identical to the base at every
  step (the characters compared on the keys both runs drew, since a ragdoll's timing varies the set).
- The settings file: one saved by the base code, read and saved again by the new, is byte-identical to the base code's
  own re-save.
- The probe: a coverage run of one test gives the same map hash, units and every count before and after.

**Further rules:**
- `TestContext` sits at exactly twenty public methods. The next test verb starts a part of its topic (the event log
  first); it never grows the facade.
- A new sound family is a file, one dispatch row and one list line.
- A camera tunable goes in its holder.

**Allocations:** each world piece allocates two more objects at spawn, each world one, each test three, Main three and
the `Keybinds` autoload one. A plain perf A/B therefore plays a different fight (the sight cadence is keyed on instance
ids), and is compared on the same fight: family 5's close compared the game slices (audio, world, root) with it,
base `cfc8467` against `41101bf`, within the bar. The UI, probe and testing slices touch no game per-frame path.

**Docs:** the architecture skill's interfaces 12, 13, 14, 21, 22 and 23 name the new reads, its holder list names the
camera's two, its "Typed components" convention names these parts, and each domain skill says what each part holds.

## Considered options

- **`PixelCanvas` parts reached by property** (`c.shade.bevel(…)`): rejected. The canvas is a `RefCounted`, so a part
  could not hold it; it would take the canvas at every call or split the shared coverage snapshot. About 500 painter
  calls would get longer for no gain.
- **Static helpers that take the object** (`PixelFinish.grain(c, …)`, `CharacterStun.level(c)`): rejected, as in #76's
  grilling.
- **A fully topical `TestContext`** (`t.wait.until`, `t.find.actor`, `t.expect.check`): rejected. It changes about
  7668 lines in about 600 files, the API every test reads most.
- **Typing `TestContext.world` as the `TestWorld` script:** rejected. Every test's parse would hang on the world's
  preload chain. The 79 lines that read a squad, a stack or a match handle take an explicit type instead.
- **`Keybinds`' input readers as the part** (`Keybinds.input.is_fire_pressed()`): rejected. It is fewer lines, but it
  splits the one pattern gameplay follows (an action const, a default, a typed reader).
- **Main's run exports as a Node child or a static holder:** rejected, for the reasons above.
- **A zero-allocation `EnvironmentObject`:** rejected. No cut set reaches 15 vars without folding a catalogue field.
- **Strided packed arrays in `WorldLighting`:** rejected. They cost readability, and the pieces already fork the fight.
- **The probe's parts as files beside it:** rejected. The instrumenter copies only `probe.gd`, so a project without
  `tools/coverage/`, such as the coverage tool's fixture, would fail to load them.
- **The Von gate emitting the session's signal itself:** rejected. The signal would be named nowhere in the session,
  which the analyzer flags; the gate is handed the emit instead.
- **Sound families as preload consts on the bank** (`SoundBank.Impacts.profile(…)`): rejected. `Sound` and the tests
  call the choosers, and the audio domain names its statics `Sound*`.
- **Exclusions or a higher threshold:** rejected by #76 and ADR 0004.
