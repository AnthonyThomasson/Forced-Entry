---
name: domain-general
description: Use when editing scenes/general/ or working on keybinds, settings, the game clock, camera, command server, shared ids (PhysicsLayers, DrawLayers, LightMasks), FillBatch, WeightedPick, MatchVerdict.
---

# General domain (`scenes/general/`)

Infrastructure every domain may use. Cross-domain API: `architecture` interfaces 7, 10, 11, 13, 14, 15, 19. HUDs and menus are `domain-ui`. Tests: `tests/general/` (camera, keybinds, settings, FillBatch, WeightedPick, verdict; it also holds match-building and squad tests that belong to `domain-main` and `domain-ai` (`team.md`)).

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
| `physics_layers.gd`, `draw_layers.gd`, `light_masks.gd` | shared ids |
| `fill_batch.gd`, `weighted_pick.gd`, `match_verdict.gd` | shared helpers |

## Shared ids

- `PhysicsLayers.SOLID` is the layer walls, solid furniture and bodies sit on; every ray and sweep that must hit a wall reads it (add a layer here, never a magic number).
- `DrawLayers` is the one z ladder (`FLOOR` -5 … `EFFECTS` 4). Every domain's z knob starts from a rung; a new layer is a rung here.
- `LightMasks` (`docs/lighting.md` L6): occluder bits, the shadow masks by light height (a 2D shadow has no length, so height picks who shadows whom), item light layers `HOUSE` / `STREET`. `LightMasks.occluder(polygon, bit)` is the one place an occluder is shaped: wound clockwise on screen and culled counter-clockwise, so the shape stays lit and only what lies behind it falls dark. It returns null while `LightMasks.shadows` is off (the Testing domain's `lighting.enabled` switch).

## Game clock

`GameClock` counts physics frames in `_physics_process` and is `PROCESS_MODE_PAUSABLE`, so it stands still while the tree is paused (the spectator inspector's pause, the test runner's) and a headless `--fixed-fps` run reads the same times every run. Every AI ttl, timer and age runs on it (`docs/leadership.md` LD1); what measures real time (the Von launcher's boot timeout, Von's reply latency) stays on `Time`. It is an autoload node (an autoload and a class cannot share a name), read off the singleton.

## Input

All input goes through `Keybinds`; gameplay never hard-codes action strings or `KEY_*`. To add an input: an action constant, its default in `DEFAULTS` (or `MOUSE_DEFAULTS`), a typed reader, an entry in `LABELS` and `GROUPS` (a test enforces they cover every action). `Keybinds._ready` registers every action in the InputMap, so `project.godot` has no `[input]` section.

- Each action holds exactly one binding: a key (stored by physical keycode) or a mouse button. `FIRE`, `COMMAND`, `ZOOM_IN` and `ZOOM_OUT` are mouse defaults.
- `SHARED` pairs may sit on one input (`INTERACT`/`PAUSE`; each camera key with its move key) because the spectator match has no player; `conflicts_of` skips them.
- `FIRE` is read two ways (`is_fire_just_pressed` one round, `is_fire_pressed` held for an automatic gun); rebinding it moves both.
- While the player drives, its movement keys and `RUN` are the vehicle's throttle, steer and handbrake (read off `movement.move_input` / `run_input`): driving adds no action.
- `bindings` (`input_bindings.gd`, preloaded, no `class_name`) is built with the action tables handed in and holds no owner. `text_of` skips the layout lookup on the headless display server (it logs an error there).
- Tests that rebind end with `Keybinds.bindings.reset_all()`: the harness does not restore it.

## Saved settings

`Settings` keeps `debug` (the master switch for the AI overlays), the setup window's last choices, the overlay toggles and the key-binding overrides in `user://settings.json` (`Settings.path`). Only differences from the defaults are stored, so a changed default still reaches an action the player never touched.

- Main calls `Settings.load_file()` once in `_ready`, after seeding `Settings.debug` from its export. Nothing else does, so the headless runner (never loads `main.tscn`) never reads a developer's file.
- A missing file keeps the defaults; an unreadable one `push_warning`s and does the same; a file without `debug` leaves it as it was.
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

`camera_controller.gd` follows its exported `target_path`, or **frames** a list (`frame(targets)`: the midpoint of the live targets, zoomed to fit plus `frame_margin`, dropping any `is_dead`; the spectator view). `pan_enabled` (per instance) removes hand pan; the test runner turns it off for a human-driven player, where WASD walks.

- **Zoom** (both modes): the wheel, or a trackpad's `InputEventPanGesture` (macOS sends no wheel events; not rebindable), scales a lasting `_zoom_bias` that multiplies the automatic zoom `_base_zoom`, so it works the same in both modes and may pass the fit's `min_zoom`/`max_zoom` (limited by `wheel_min_zoom`/`wheel_max_zoom`). Read in `_unhandled_input`, so scrolling UI gets the wheel first.
- **Hand pan** (framing only): camera keys, or the mouse within `edge_pan_margin` of an edge (only once the pointer was seen moving over the window, cleared on mouse-exit / focus-out), set `_manual`, which suspends the framing position; `manual_hold` seconds without panning eases back in. Test: `tests/general/camera_manual_pan_test.gd`.
- **Driving zoom-out**: `_drive_zoom_out` reads `who.use.vehicle().view_zoom_out()` duck-typed (interface 19) and never `VehicleDriveConfig`. Test: `camera_zooms_out_driving_test.gd`.
- **Explosion shake** (`&"explosion"`): trauma from the kind's strength and nearness, applied through `Camera2D.offset` only, never `global_position`, so following and framing are unchanged. Test: `camera_shakes_on_explosion_test.gd`.

## Despawner

Global cap (`max_scene_objects`) for transient bodies: domains hand their spawns to `Despawner.track`. Physics' `DebrisLayer` and `ScorchDecals` read the same cap for landed chips and scorch marks.

## FillBatch

`FillBatch.new(canvas, base)` draws plain-coloured polygons and circles as ONE triangle array (`fill`, `fill_convex`, `circle`, then `flush`) in place of one draw command each, because the windowed renderer builds a vertex buffer per polygon command. It cuts the same triangles the engine would and each disc into `draw_circle`'s 64-gon, so the pixels match. A polygon that cannot be triangulated goes to the engine alone after what was added, which reports it as `draw_colored_polygon` does.

Under the headless display (`FillBatch.batching` false) nothing renders and gathering costs more than it saves, so each shape goes to the canvas as it comes; code that draws plain commands itself there (the chip chunk, the blood splat) is deliberate. `FillBatch.unit_circle()` and `fan(base, n)` feed the Character's `BodyMeshes.Solid`. Test: `tests/general/fill_batch_matches_draw_calls_test.gd` (headless: the triangles; `--windowed`: identical pixels).

## WeightedPick

One `rng.randf()` over the total weight; each entry takes the next stretch. `strict` keeps each caller's edge behaviour: false, a roll on the end of a stretch takes that entry and one past them all takes the last; true, it takes the next entry and one past them all takes the first. The room dresser, room wear and street marks, the Lighting rhythms (not strict) and the Character's style (strict) draw through it. Test: `tests/general/weighted_pick_suite.gd`.

## MatchVerdict

`MatchVerdict.decide(combatants)` is the one rule the MatchHUD banner and the command server's `match` decide by: `{}` while every faction has someone alive; once one is wiped out, `{ winner, survivors, sides }` (`winner` null for a draw). It reads `faction` and `is_dead` only and leaves a freed combatant out. Tests: `tests/ui/match_hud_verdict_test.gd`, `command_server_verdict_suite.gd`.

## Spectator mode

Main's `run.spectator_mode` (default on) runs an AI-only contest: it frees the human `Player` and `DebugUI`, frames every combatant with the camera and shows `MatchHUD`. Wiring lives in `domain-main`; General only publishes the contracts.
