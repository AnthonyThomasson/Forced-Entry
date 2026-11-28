---
name: domain-general
description: Use when editing scenes/general/: keybinds, settings, camera, command server, Pointer, PhysicsLayers, ViewLayers, SightRay, SeenArea, WeightedPick, MatchVerdict.
---

# General domain (`scenes/general/`)

Infrastructure all domains use. Cross-domain API: `architecture` interfaces 7, 10, 11, 13, 14, 15, 19, 24 (`scroll_notches`, `INTERACT`), 26 (`Pointer`), 29 (`TwinSpace`). HUDs and menus: `domain-ui`. Tests `tests/general/` (camera, keybinds, settings, WeightedPick, SightRay, SeenArea, BodyHeights, PlanSpace, TwinSpace (`twin_space_world`, `twin_space_in_match`), Pointer (pointer_converts, pointer_inject), verdict; it also holds match-building tests, in `domain-main` ("Tests"), and squad tests, in `domain-ai` (`team.md`)).

Autoloads (`project.godot`): `Keybinds`, `Despawner`, `EventBus`, `GameClock`, plus Audio's `Sound`. The rest are `class_name` static holders (no instance). Tuning holders: `CameraConfig`, `CameraShakeConfig` (ADR 0003), read live, so a test may `set_static` them.

## File map

| File | Holds |
|---|---|
| `keybinds.gd`, `input_bindings.gd` | action table, typed readers; rebinding store `Keybinds.bindings` |
| `settings.gd` | `Settings`: saved JSON |
| `game_clock.gd` | `GameClock` |
| `event_bus.gd`, `game_log.gd` | `EventBus` (topics and payloads: interface 10), `GameLog` (interface 15) |
| `despawner.gd` | cap on transient bodies |
| `camera_controller.gd` (+ the two config holders) | `Camera2D` |
| `command_server.gd` | dev command server |
| `pointer.gd`, `faded_twins.gd` | `Pointer` (26; `pointer.md`), `FadedTwins` (which twins the wall fade holds faded: Art writes, Pointer reads; 27) |
| `ground_layer.gd` | `GroundLayer`: flat 3D overlays (`camera3d.md`) |
| `physics_layers.gd`, `view_layers.gd` | shared ids |
| `world_rng.gd` | each world's random stream and its characters' spawn order (`helpers.md`) |
| `weighted_pick.gd`, `match_verdict.gd`, `sight_ray.gd`, `seen_area.gd` | shared helpers (`helpers.md`) |
| `body_heights.gd`, `plan_space.gd` | `BodyHeights` (real posture heights, 42.3 px a metre), `PlanSpace` (plan `Vector2` <-> 3D): `heights.md` |
| `twin_worlds.gd` | `TwinWorlds` (the twin space beside a `World2D`; `twins.md`) |
| `twin_space.gd`, `twin_shapes.gd` | `TwinSpace` (the twin 3D space: a 3D twin per solid 2D body, synced each physics frame, the hook each domain builds its twin through), `TwinShapes` (a 2D shape lifted to a 3D one): `twins.md` |

## Shared ids

- `PhysicsLayers` holds the twin 3D space's layer bits (`TWIN_WORLD`, `TWIN_VEHICLE`, `TWIN_CHARACTER`, `TWIN_WALKOVER`, the masks `TWIN_ALL` / `TWIN_BLOCKS` / `TWIN_SURFACES`, `twins.md`); every ray and sweep reads one (add a layer here, never a magic number). No 2D layer exists: every sim root is a plan handle (`Node2D`).
- `ViewLayers` holds the visibility bits that say what the player's view may remember (`helpers.md`).

## Game clock

`GameClock` counts physics frames in `_physics_process` and is `PROCESS_MODE_PAUSABLE`, so it stands still while the tree is paused (the spectator inspector's pause, the test runner's) and a headless `--fixed-fps` run reads the same times every run. Every AI ttl, timer and age runs on it (`docs/leadership.md` LD1); what measures real time (the Von launcher's boot timeout, Von's reply latency) stays on `Time`. It is an autoload node (an autoload and a class cannot share a name), read off the singleton. `seconds()` reads 1e-9 above exact (compare it with itself, never with `msec() / 1000.0` or `frame() / 60.0`) so `seconds() - start >= ttl` ends on the frame a ttl of whole frames says whatever frame it started on (as floats it missed at 45 of 100 start frames); `msec()` reads 16 or 17 ms a frame by the frame a span starts on, so a world calls `align()` when it begins (`WorldRng`) and every span from then reads the same ms (`domain-testing`'s perf notes; `tests/general/game_clock_suite.gd`).

## Input

All input goes through `Keybinds`; gameplay never hard-codes action strings or `KEY_*`. To add an input: an action constant, its default in `DEFAULTS` (or `MOUSE_DEFAULTS`), a typed reader, an entry in `LABELS` and `GROUPS` (a test enforces they cover every action). `Keybinds._ready` registers every action in the InputMap, so `project.godot` has no `[input]` section.

- Each action holds exactly one binding: a key (stored by physical keycode) or a mouse button. `FIRE`, `COMMAND`, `ZOOM_IN` and `ZOOM_OUT` are mouse defaults. `COMMAND` is the right button; the spectator inspector's right-click select reads the raw button, not the action (no match has both a command menu and an inspector).
- `SHARED` pairs may sit on one input (`INTERACT`/`PAUSE`; each camera key with its move key) because the spectator match has no player; `conflicts_of` skips them.
- `FIRE` is read two ways (`is_fire_just_pressed` one round, `is_fire_pressed` held for an automatic gun); rebinding it moves both.
- `INTERACT` (default Space, "Interact (sit, door, vehicle)", "Interaction" group) is the one key for a chair, a bed, a house door and a vehicle's door (the Use action it absorbed is gone; a saved binding for it is dropped): `is_interact_just_pressed()`, `is_interact_pressed()`, `is_interact_just_released()` (`domain-character`). `CAMERA_TURN_LEFT` / `CAMERA_TURN_RIGHT` (default Q / E, "Camera" group) a press turns the 3D camera a quarter (`Keybinds.camera_turns_pressed() -> int`: +1 / -1 a press).
- `Keybinds.scroll_notches(event) -> float` is how far an event scrolls in wheel notches (positive up): a `ZOOM_IN` / `ZOOM_OUT` press is one (its own `factor`), a trackpad's `InputEventPanGesture` counts `CameraConfig.trackpad_zoom_sensitivity` per unit of `delta.y` (up is negative); 0 for any other event. The camera zooms by it and the player's controller turns a door by it while Space is held on one, taking the event in `_input` so the camera never sees it (`docs/doors.md` DR7).
- While the player drives, its movement keys and `RUN` are the vehicle's throttle, steer and handbrake (read off `movement.move_input` / `run_input`): driving adds no action.
- `bindings` (`input_bindings.gd`, preloaded, no `class_name`) is built with the action tables handed in and holds no owner. `text_of` skips the layout lookup on the headless display server (it logs an error there).
- Tests that rebind end with `Keybinds.bindings.reset_all()`: the harness does not restore it.

## Saved settings

`Settings` keeps `debug` (the AI overlays' master switch), the setup window's last choices, the overlay toggles with their scope per mode and the key-binding overrides in `user://settings.json` (`Settings.path`). Only differences from the defaults are stored, so a changed default reaches an action the player never touched.

- Main calls `Settings.load_file()` once in `_ready`, after seeding `Settings.debug` from its export. Nothing else does, so the headless runner never reads a developer's file.
- A missing file keeps the defaults; an unreadable one `push_warning`s and does the same; a file without `debug` leaves it.
- `Settings.overlay_scopes` is the bar's "Show on" scope per mode (`{ play: scope, watch: scope }`): only the modes the player chose a scope for, set by `set_overlay_scope(mode, scope)`, loaded from the file only when a mode's entry is a string. A mode with none starts on the UI's `OverlayRegistry.DEFAULT_SCOPES`, which Main reads: `Settings` depends on no UI (`domain-main` (`overlays.md`)).
- Mutators save at once. `reset_all()` leaves `debug`. `set_setup` drops the start `mode` and keeps each side's dict whole.
- Tests point `Settings.path` at a scratch file with `set_static` (`tests/general/settings_file_test.gd`).

## Dev command server

`command_server.gd` (a node in `main.tscn`) drives a running game with line-delimited text commands on 127.0.0.1. Editor-only (`OS.has_feature("editor")`), and off unless the port is > 0: `GODOT_CMD_PORT` (per worktree, set by `tools/editor.sh`), else `application/debug/command_port`. `GODOT_CMD_PORT=off` keeps it off whatever port is set: `tools/load_check.sh`, `tools/run_tests.sh` and the coverage runner always set it, so two worktrees' checks never clash on 9080.

- Verbs: `help` lists them (a verb table in the script); anything else is evaluated as a GDScript `Expression` against the node. Drive it with `tools/gcmd.py` (one command) or `tools/match.py` (N scored matches); the `godot-run` skill covers it.
- Movement and actions inject `Input` presses through `Keybinds` names, the same path a human's input takes, so no game domain is coupled to it.
- It finds combatants under the scene root or a node in the `match_world` group (Main's container for everything a match builds).
- `match` prints one parseable line: each AI combatant's health, act and alive flag, then the verdict and elapsed time. It reads only the Character API and the AI controller's `current_act()`. `verdict_of` words `MatchVerdict.decide` (a 1v1 names the survivor; the HUD names a lone survivor in any match): `tests/general/command_server_verdict_suite.gd`.
- `ai` dumps every AI combatant's `debug_state()` as JSON; `tools/von_probe.py --capture` turns the dump into replayable Von scenarios.
- `restart [seed]` reloads the scene. The seed rides in `Engine` meta `match_seed` and `skip_setup` makes `main.gd` build at once instead of reopening the setup window.

## Camera

`camera_controller.gd` follows its exported `target_path`, or **frames** a list (`frame(targets, within := Rect2())`: the midpoint of the live targets, zoomed to fit plus `frame_margin`, dropping any `is_dead` and any outside `within`, the test host's world ground; the spectator view). `pan_enabled` (per instance) removes hand pan; the test runner turns it off for a human-driven player, where WASD walks.

- **Zoom** (both modes; 3D: whole steps, `camera3d.md`): the wheel, or a trackpad's `InputEventPanGesture` (macOS sends no wheel events; not rebindable), scales a lasting `_zoom_bias` that multiplies the automatic zoom `_base_zoom`, so it works the same in both modes and may pass the fit's `min_zoom`/`max_zoom` (limited by `wheel_min_zoom`/`wheel_max_zoom`). Both are read through `Keybinds.scroll_notches(event)`, in `_unhandled_input`, so scrolling UI gets the wheel first, and a door held by Space takes the event before it (`_input` of the player's controller).
- **Hand pan** (framing only): camera keys, or the mouse within `edge_pan_margin` of an edge (only once the pointer was seen moving over the window, cleared on mouse-exit / focus-out), set `_manual`, which suspends the framing position; `manual_hold` seconds without panning eases back in. Test: `tests/general/camera_manual_pan_test.gd`.
- **Driving zoom-out**: `_drive_zoom_out` reads `who.use.vehicle().view_zoom_out()` duck-typed (interface 19) and never `VehicleDriveConfig`. Test: `camera_zooms_out_driving_test.gd`.
- **Explosion shake** (`&"explosion"`): trauma from the kind's strength and nearness, applied through `Camera2D.offset` only, never `global_position`, so following and framing are unchanged. Test: `camera_shakes_on_explosion_test.gd`.

## The 3D camera rig

`camera_rig.gd`, `render_*config.gd` (27): `camera3d.md`.

## Pointer

`Pointer` (interface 26): the one screen ↔ world conversion and the injectable pointer; `pointer.md`.

## Despawner

Global cap (`max_scene_objects`) for transient bodies: domains hand their spawns to `Despawner.track`. Physics' `DebrisLayer` and `ScorchDecals` read the same cap for landed chips and scorch marks. Entries live in an insertion-ordered dictionary (ticket -> instance id) beside an id -> ticket index, so cap eviction and a `tree_exited` removal are O(1) with no cycles to leak. A node tracked twice is two entries (its exit drops the oldest); lowering the cap keeps the original deferred enforcement on the next `track`. T: `despawner_evicts_oldest_test.gd`.

## Shared helpers

`WorldRng`, `WeightedPick`, `MatchVerdict`, and the player's view's shared rules `ViewLayers`, `SightRay` and `SeenArea`: `helpers.md`.

## Spectator mode

Main's `run.spectator_mode` (default on) runs an AI-only contest: it frees the human `Player`, frames every combatant with the camera and shows `MatchHUD`. Wiring lives in `domain-main`; General only publishes the contracts.
