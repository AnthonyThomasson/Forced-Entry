---
name: domain-main
description: Use when editing scenes/main.gd, match_builder.gd or match_spawner.gd, or working on match start-up, spawn placement, loadout arming, the endless run or how overlays are toggled.
---

# Main: the composition root

Files (all in `scenes/`): `main.gd` + `main.tscn` (UI flow), `match_builder.gd` (`MatchBuilder`, interface 23: spec in, handle out;
its API is in `architecture`), `match_spawner.gd` (NPC placement, used only by `MatchBuilder`), `squads_spec.gd` (`SquadsSpec`),
`main_run.gd` (`MainRun`), `main_endless.gd` (`_endless`), `main_overlays.gd` (`_overlays`). Main and the Testing runner
(interface 13) are the only code that knows every domain; nothing depends on Main. Main builds no match itself: the Testing
domain's worlds build through `MatchBuilder` too, so a test measures the match Main plays.

- `main.tscn` authors none of the run's values. Main's `run` (`MainRun`, an exported `Resource`) holds them (`house_seed`,
  `force_plan`, `entrance_distance`, `defender_count`, `invader_count`, `invader_margin`, `spawn_clearance`, `spectator_mode`,
  `player_side`, `debug_overlays`); a scene that authors one gives each Main its own copy. `endless_delay` and `endless_time_limit`
  stay exports on the node (`tools/coverage` reads `endless_time_limit` by name).
- `_endless` and `_overlays` are parts built once with Main and reached by preload const (no `class_name`).
- The side loadouts are not exports: they are the spec defaults (`MatchBuilder.INVADER_LOADOUT` / `DEFENDER_LOADOUT`).
- Tests drive Main only through its public members (`start_match`, `set_overlay`, `return_to_setup`, `run`'s exports, the
  `match_world` group, `Player`, `SetupMenu.current_config()`), run whole in a world of its own by `tests/_main/main_probe.gd`
  (`domain-testing`).

## Setup flow

A fresh launch loads settings, opens the setup window (`domain-ui` (`menus.md`)) and builds nothing until a start button.

- `Settings.debug` is seeded from `run.debug_overlays` before `Settings.load_file()`, so the headless runner never reads a
  developer's file and a file that does not name Debug leaves the export standing.
- Engine meta `skip_setup` (set by the dev command server's `restart`) builds at once from `_base_spec()`. Engine meta
  `match_seed` pins the seed (`_play`); a seed of 0 becomes `randi()`, so every run reproduces from its displayed seed.
  `return_to_setup()` (Escape, and the `menu` verb) removes both metas and reloads the scene.
- **Start**: a human joins `side` on top of that side's NPC count; with `lead` ticked (a played match only) the human leads the
  squad (`docs/leadership.md` LD10). **Watch**: AIs alone. **Endless**: AIs alone; `endless_delay` s after each `match_ended` Main
  frees `World` (`_teardown_world`) and plays `MatchBuilder.random_spec(rng, _endless.spec, _endless.most)`; an undecided match is
  called a draw after `endless_time_limit`. **Tests**: scene change to `testing/test_browser.tscn`. **Settings**: the settings
  page (interface 14); Main applies each `SettingsMenu` signal to `Settings` and answers with `set_rows`.
- The window's choices are saved (`Settings.set_setup`) on Start, Tests and Escape and fed back as defaults
  (`_with_saved_setup`): a key an older save lacks (the outfit, say) keeps its default.
- `_on_setup_chosen` reads the config with `MatchBuilder.spec_from_setup(config, _base_spec())`, then **awaits the AI's
  `DecisionServerLauncher.resolved`** so no NPC makes its first decision against a booting Von server. The launcher is a root
  node of `main.tscn` and always resolves; a run with no server starts with NPCs that hold steady.

## A match: `Main.start_match(spec)`

Main's one way into a match (a coroutine; the tests call it). It lays `spec` over `MatchBuilder.spec`, replaces the spec's
`overlays` with Main's own flags, adds a fresh `World` node (group `match_world`: how the dev command server finds the match)
and awaits `MatchBuilder.build`. A match torn down during the build returns `{}` and wires nothing. Then the UI over the handle
(`_match`):

- **Human present**: `_build_markers` (`StackMarkers` watching `player_stack`, `docs/tactical-entry.md` E16) and
  `_build_stun_screen` (`Sound.focus` = the human, interface 18, so a bang's muffle and tinnitus are the human's alone;
  `docs/grenades.md` G14). The scene's `Player` is freed when the human is another node.
- `_watch_side_stacks`: in a played match the markers watch the human's side's squad, lead or not (LD18).
- **Human leads**: `_build_command_menu` builds `OrderMarkers` and `CommandMenu` only when `squad.leader()` is the human, wires
  `order_requested` to the squad's `issue` and `selection_changed` to the markers (interface 21, LD11, LD12). Otherwise nothing
  reads the right button. `right_clear` is `OverlayToggles.RESERVED_WIDTH` with Debug on, else 0.
- `MatchHUD.begin(combatants, time_limit)`, then `_overlays.begin(spectator, handle)`: the match's mode and overlay scope (`overlays.md`). With no human,
  `_setup_spectator`: the camera frames the combatants, the `SpectatorInspector` goes under `World` (`setup(combatants, _overlays.npc_flags(),
  OverlayToggles.RESERVED_WIDTH)`, then `set_scope(_overlays.scope)`), and the player is freed. A played match has no per-character readout.
- `_overlays.build`: the performance overlay and toggle bar when Debug is on (built once, kept across an endless run).

`_teardown_world` frees `World` and everything the match left, and clears `Sound.focus`, `_match`, `_human`, `_overlays.inspector`.

## Overlays

`_overlays.flags` has one entry per `OverlayRegistry` row; the bar's toggles and its "Show on" scope reach Main's public `set_overlay(flag, on)` and `set_overlay_scope(scope)`,
which save the choice and route it live. Seeding, the scope per mode and the routing: `overlays.md`.

## The match module: gotchas

The API is interface 23; these are the reasons behind it.

- **Wait for the nav maps.** `stage` (a generated district: the nav bake covers its streets, the lights its towers) steps two physics frames (walls' colliders go live on a step), then waits until
  `NavBuilder.ready` holds on the planning map and the steering map (at most `NAV_SYNC_MS`, then `push_error`), so no NPC is
  placed while a map still shows another navmesh. A world freed during the wait returns `{}`. Main's match and every test world
  keep `wait_nav` on.
- **Light before characters.** `WorldLighting.light` (interface 20, `docs/lighting.md`) runs in `stage`, under `World` so a
  teardown frees it; characters placed afterwards cast their own shadows (group `characters`).
- **Bind before the tree.** `bind_npc` hands the controller `rooms`, `openings` and its `entry_point` before the NPC joins the
  tree, so its first tick knows them; `npc.tscn` authors the controller in group `npc_controllers` (interface 7) so that holds.
  An invader's entry point is the front entrance, a defender's none. `match_spawner.gd` never calls `MatchBuilder`: `populate`
  hands it `bind` as a `Callable`, so the dependency runs one way.
- **Placement RNG.** One RNG seeded with `seed` places defenders, then the invader team. Guns draw from `seed ^ LOADOUT_SEED_SALT`
  and styles from `seed ^ STYLE_SEED_SALT`, so a pinned seed pins loadouts and styles without shifting placement or each other.
- **The human's start**: the spec's `human.at`; else a defender gets a clear spot in a random room, an invader starts where it
  stands, or `front_step` px (Main: `run.entrance_distance`) out of the front door along the way out of its room, whichever street
  the district's house faces (Main's `Player` anchor is the front entrance itself). It is reparented just above the
  district (the lone house: draw order house < human < NPCs) and joins its side's faction, so NPCs treat it as an ally.
- **The human's view**: `populate` ends by watching the human, `PlayerView.watch(world, human)` (the Vision domain, interface 25,
  `docs/player-vision.md` V8), after the squads and overlays, and records it as the handle's `view`. No human (Watch, Endless) means
  no view and everything drawn; so does `VisionConfig.enabled` off. Main's `Player` is the viewer in a played match; its death lifts
  the view (V9) and the rest of the match is drawn whole. The overlays, markers and the HUD are drawn over it in their own colours
  (`ViewLayers.overlay`, interface 11).
- **Arming** (`arm`, `style`; `docs/outfits.md` O11, O15): invaders default to 1 stun + 1 frag and a helmet, shirt, plate
  carrier with steel III plates, tactical pants and boots; defenders to nothing and `LoadoutConfig.default_outfit`. The match's
  police unit is the first draw of `CharacterStyleConfig.styles` for the invaders' side (`styles_of`), worn by every invader the
  human included; the first is lead (rank 2), the second sergeant (1), the rest troopers (0). With `human.lead`, a human invader
  is the lead and the NPCs rank from the sergeant down, the draws unchanged (LD10). Each defender draws a crew style, a look
  seed and one of its style's weapons. A test actor is armed here only when its setup declares a match.
- **Squads** (`build_squads`, `squads_over`; `docs/leadership.md`): one `Squad_<faction>` per faction, built after `arm` (which
  ranks the unit). The leader is the squad's own rule (rank, then spawn order) or the human when it leads.
  `ambush_attacks` is set for the defenders' side only (LD29). `own_claims` is true on the invaders' side only, so a human
  defender leader's step-ups rally nobody (D29). `LeaderOverlay` stays hidden until `set_overlay` shows `LEADERS` (LD12, LD28).
  `claim_ttl` defaults to `callout_ttl_of(members)`, the first NPC's `tuning.radio.callout_ttl`; a test's squad of puppets
  passes its own.

## NPC placement (`match_spawner.gd`)

`populate` builds one per match and records every NPC it places in `combatants` (spawn order); `match_spawn_clear_test` builds
one with no `bind`.

- **Clear** (`is_clear`): at least `spawn_clearance` from every solid furniture footprint (`NavBuilder.furniture_holes`, read
  off shapes, right on the frame the house is built) and twice that from every placed combatant. `clear_spot` tries the room's
  centre, then `SPAWN_TRIES` random points; nothing clear logs and falls back to the centre. A body spawned inside a piece is
  ejected with the piece's momentum and flung.
- **Invader team** (`spawn_invader_team`, `docs/leadership.md` LD27), one group packed round a point:
  - beside the front door (`_beside_front_door`): `DOOR_SIDE_OFFSET` along the outside wall from the doorway's centre, on a
    side drawn from `rng`, and `DOOR_OUT_OFFSET` out from the wall, clamped into the rooms' bounds grown by twice
    `invader_margin` less two `spawn_clearance`, so the first ring stays on the walkable ring round the house;
  - round a human invader (`around`, whose start every member keeps clear of);
  - no front door: `perimeter_point` of the bounds grown by `invader_margin`.

  `_group_spot` walks rings twice `spawn_clearance` apart (`GROUP_RINGS`) for the first spot that is clear, `_outdoors` and,
  beside the front door, outside the doorway's straight strip (`_in_strip`); none logs and falls back to the point.
- **`add_npc` binds, then adds.** A body added at the world origin and moved afterwards overlaps whatever stands there for a
  frame, and physics launches that piece across the map (`match_spawn_origin_test`).

## Tests

Under `tests/general/` (`match_builder_*`, `match_nav_ready_*`, `match_spawn_*`, `match_setup`, `match_styles`,
`saved_setup_*`, `main_setup_*`, `test_world_invader_bound_as_match`), plus
`tests/ai/stack/human_defender_leader_no_rally_test.gd` and `tests/ui/leader_overlay_draw_test.gd`. The leader, squad and stack-radio tests that sit
there too (`lead_rank`, `squad_*`, `stack_player_wiring`) are `domain-ai` (`team.md`). List them with
`ls tests/general | grep -E 'match_|saved_setup|main_setup|test_world_invader'`. The overlay scope's tests are in `overlays.md`.

**Interfaces:** 1, 6 (`LoadoutConfig`: arming), 7 (the controller group, overlays' `show_<x>`), 9, 13, 14 (`Settings.overlay_scopes`), 17, 18, 20, 21,
22 (setup window, Von-server wait, match HUD, spectator inspector, overlay bar), 23, 25 (the human's `PlayerView`). Signatures: `architecture`.
