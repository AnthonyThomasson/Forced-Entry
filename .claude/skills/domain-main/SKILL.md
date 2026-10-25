---
name: domain-main
description: Deep implementation detail for the composition root (scenes/main.gd, scenes/main.tscn, scenes/match_builder.gd, scenes/match_spawner.gd) — the one place that wires every domain: the pre-game setup flow (Start / Watch / Endless / Tests / Settings) read into a match spec, awaiting the Von decision server, Main.start_match(spec) and the match-assembly module MatchBuilder (the world stage: house, nav map and re-baker, the dusk lighting, the wait for the nav maps; the population: NPC placement, the one bind rule, loadout arming and styling, the squads and the leader overlay; overlay routing), the HUDs Main wires on the match handle (stack markers, stun screen, the human leader's command menu, match HUD, spectator inspector, overlay bar), endless-run teardown and randomisation, the settings page wiring, and the Main exports. Use when editing main.gd, match_builder.gd or match_spawner.gd, or working on match start-up, spawn placement rules, loadout arming, the endless run or how the overlays are toggled. Complements the `architecture` skill (interfaces 1, 6, 7, 9, 13, 14, 17, 18, 20, 21, 22, 23).
---

# Main — the composition root (`scenes/main.gd`, `main.tscn`, `match_builder.gd`, `match_spawner.gd`)

`main.gd` (with the Testing domain's runner, interface 13) is the only code that knows every domain; nothing depends on it. It owns no
gameplay and builds no match itself: it keeps the UI flow (the setup window, the settings page, the endless run, the HUDs and the overlay
bar) and hands every match to the root's match-assembly module, `MatchBuilder` (`match_builder.gd`, interface 23), which the Testing
domain's world builds through too. The exports on the `Main` node are the authoring surface for a run (`house_seed`, `force_plan`,
`entrance_distance`, `defender_count`, `invader_count`, `invader_margin`, `spawn_clearance`, `spectator_mode`, `player_side`,
`endless_delay`, `endless_time_limit`, `debug_overlays`, and `show_agent_labels` / `show_agent_paths` / `show_vision` / `show_tactics` /
`show_room_zones` / `show_search` / `show_nav_holes`: seven of the overlays, the rest start at the registry's default). The side loadouts
are not exports: they are the match spec's defaults (`MatchBuilder.INVADER_LOADOUT` / `DEFENDER_LOADOUT`), so a test's match carries what
Main's does.

## Setup flow

On a fresh launch Main loads the saved settings (`Settings.load_file()` after seeding `Settings.debug` from its export, so the headless test
runner never reads a developer's file), opens the UI setup window (`domain-ui-menus`) and builds nothing until a start button is pressed.
A scripted `restart` (the dev command server) sets the Engine `skip_setup` meta so the reloaded scene builds at once, from `_base_spec()`.
The window offers:

- **Start** — a human joins the chosen side, on top of its NPC count, with the side's loadout and faction; with **Lead the team** ticked (the
  window's `lead`, a played match only) the human leads its side's squad (`docs/leadership.md` LD10);
- **Watch** — AIs alone (spectator mode);
- **Endless** — AIs alone; 5 s after each match ends (the MatchHUD's `match_ended`) Main frees its `World` node (`_teardown_world`) and plays
  `MatchBuilder.random_spec(rng, _spec, _endless_max)`: a new seed, each side's count drawn from 1 to the one chosen in setup, a random gun
  and outfit per side (`LoadoutConfig.random`) with the grenade counts it was set up with; an undecided match is called a draw after
  `endless_time_limit`; an endless run chosen with no NPC at all is one a side;
- **Tests** — changes scene to `testing/test_browser.tscn`; **Settings** — opens the settings page over the window.

The window gets `weapons`, `grenades` and `outfits` (`LoadoutConfig.options()` / `grenade_options()` / `outfit_options()`) and each side's
defaults from `_side_defaults` (`LoadoutConfig.normalize` of the side's loadout in `_base_spec()`, so `outfit` included, with its `count`).
Main saves the window's choices (`Settings.set_setup`, the outfit and `lead` with them) on Start, Tests and Escape and feeds them back into the
window's defaults (`_with_saved_setup`: a choice an older save does not name, such as the outfit, keeps its default).

Start, Watch and Endless reach `_on_setup_chosen(config)`, which reads the config into a match spec over the exports' with
`MatchBuilder.spec_from_setup(config, _base_spec())`: the config's `seed`, each side's `count` and its loadout keys (`weapon`, `magazine`,
`spares`, `stuns`, `frags`, `outfit`) over the side's default loadout, and the human (`_base_spec()` names the scene's `Player` on
`player_side` in a played match) on the config's `side`, leading with `lead`; in Watch and Endless no human. Before it plays the spec it
**awaits the AI domain's `DecisionServerLauncher.resolved(live)`**, so no NPC makes its first decision against a still-booting Von server;
the launcher is a root node of `main.tscn`, probes at scene load and always resolves (a run with no server still starts, with NPCs that hold
steady). `_play(spec)` resolves the seed (the Engine `match_seed` meta a harness pins wins; 0 becomes `randi()`, so the run reproduces from
it and can be re-entered), keeps the spec in `_spec` for the endless run and calls `start_match`. The settings page is wired here (interface
14): Main applies each `SettingsMenu` signal to `Settings` and answers with `set_rows`.

## A match: `Main.start_match(spec)`

Main's one way into a match (public, so the tests drive Main through it). It lays `spec` over `MatchBuilder.spec`'s defaults, replaces its
`overlays` with Main's own flags (`_overlay_flags`), adds a fresh `World` node (group `match_world`, how the dev command server finds the
match) and awaits `MatchBuilder.build(spec, world)`; a match torn down while it was built (Escape, or a new match) returns `{}` and wires
nothing. Then the UI over the handle (kept in `_match`):

- for the spec's human: `_build_markers` (the `StackMarkers` under `World`, `watch`ing the handle's `player_stack`, `docs/tactical-entry.md`
  E16) and `_build_stun_screen` (`Sound.focus` = the human, the Audio autoload's one input from Main: a bang's muffle and tinnitus are the
  human's alone; the `StunScreen` under `World`, `watch`ing it, `docs/grenades.md` G14); the scene's `Player` is freed when the human is
  another node;
- `_watch_side_stacks()`: in a played match the stack markers `watch_squad(squad.view)` the human's side's squad, lead or not, so every stack
  that side forms shows its rings (LD18);
- when the human leads, `_build_command_menu(rooms)`: if the squad's `leader()` is the human, the `OrderMarkers` (UI hud, `watch(squad.view)`)
  and the `CommandMenu` (UI hud, `setup({ rooms, teammates, view, resolve, leader, right_clear })`, the squad's `view` and `resolve`,
  `right_clear` the overlay bar's `OverlayToggles.RESERVED_WIDTH` with Debug on (`debug_overlays`), else 0, as the inspector's) under `World`,
  the menu's `order_requested` connected to the squad's `issue` and its `selection_changed` to the markers' `set_selection` (interface 21,
  LD11, LD12); nothing is built otherwise, so nothing reads the right button;
- `MatchHUD.begin(combatants, time_limit)` (the endless run's `endless_time_limit`);
- with no human, `_setup_spectator`: the camera frames the combatants, the `SpectatorInspector` under `World` (`setup(combatants, flags,
  OverlayToggles.RESERVED_WIDTH)`, the flags without the global ones), and the player and its debug panel are freed;
- `_build_overlays`: the performance overlay and the overlay toggle bar when Debug is on (built once, kept across an endless run).

`_teardown_world` removes and frees `World` (house, nav map, NPCs, inspector, and the blood / debris / casings they left), clears
`Sound.focus`, `_match`, `_human` and `_inspector`.

## The match module (`match_builder.gd`, `MatchBuilder`)

A `RefCounted` of statics, beside `main.gd`; its signatures are interface 23. A **match spec** goes in (`spec(overrides)`: `seed`, `plan`,
`entrance`, `house`, each side's `{ count, loadout, at }`, `human` `{ node, side, lead, at }`, `wait_nav`, `spawn_clearance`,
`invader_margin`, `overlays`), a **match handle** comes out (`{ world, house, rooms, openings, nav_region, nav_debug, combatants, squads,
player_stack, leader_overlay }`). `build` is its two stages:

1. **`stage`, the world stage.** The spec's `house` (a layout or arena already built, moved under the world) or `WorldGen.generate(seed,
   plan, entrance, world)` (it logs `House: <plan>  seed: N`); `WorldGen.get_rooms`; `NavBuilder.build`, the `nav_debug.gd` overlay
   (`NavDebug`, its holes started from the spec's `overlays`) and the `nav_updater.gd` re-baker (`NavUpdater`) (interface 9); then the dusk
   lighting, `WorldLighting.light(world, seed, rooms)` (interface 20, `docs/lighting.md`), under `World` so a teardown frees it; the characters
   placed after it cast their own shadows and are followed by it through the group `characters`. With `wait_nav` (on; Main's match and every
   test world wait) the world is stepped two physics frames (the walls' colliders go live on a step), then until `NavBuilder.ready` holds on
   the planning map and on its steering map, so no NPC is placed while a map still shows another navmesh (at most `NAV_SYNC_MS`, 5000 ms of
   real time, then a `push_error`; a world freed during the wait returns `{}`).
2. **`populate(handle, spec)`.** One RNG seeded with the spec's `seed` places the defenders, then the invader team, through a
   `match_spawner.gd` instance (below), or puts a side's NPCs at its `at` points (`_place_side`, one branch for both sides); each NPC is bound
   before it joins the tree, through the spawner's `bind` (a `Callable` `populate` sets: `bind_npc` with `entry_point_for` its faction). The human, when the spec names one, joins
   its side (`_join`: the side's faction, so its NPCs treat it as an ally; its start the spec's `human.at`, else for a defender a clear spot
   in a random room, while an invader starts where it stands, which for Main's `Player` is its anchor, `entrance_distance` below the front
   entrance), is reparented under the world just above the house (draw order house < human < NPCs). Then `arm` (every combatant, the human
   last), `squads_over` (below: the human's stack radio, the squads, the leaders overlay shown by the spec's `LEADERS`), and every other
   overlay but the holes started through `set_overlay` by the spec's `overlays`.

- **Arming** (`arm(characters, spec)`): every character gets its side's loadout (by its faction) through `LoadoutConfig.apply` →
  `Character.inventory.set_loadout` and `Character.set_outfit` — a chosen gun with its magazine and spares, its stun / frag grenade counts and its outfit
  (`docs/outfits.md` O11). By default invaders carry 1 + 1 grenades and wear a helmet, a shirt, a plate carrier with a steel III plate front
  and back, tactical pants and boots (`INVADER_LOADOUT`); defenders 0 + 0 in plain clothes (`DEFENDER_LOADOUT` `{}`, so
  `LoadoutConfig.default_outfit`: a t-shirt, jeans and shoes). The gun is the chosen one or by default one random gun drawn from an RNG seeded
  with the spec's seed XOR `LOADOUT_SEED_SALT`, so a pinned seed pins the loadouts without shifting placement. Each is styled as it is armed
  (`style(characters, spec)`, `docs/outfits.md` O15), from a second RNG seeded with the seed XOR `STYLE_SEED_SALT` (so the styles never shift
  the guns): its first draw is the match's police unit, one of the `CharacterStyleConfig.styles` whose `side` is the invaders' (`styles_of`:
  `zenitex`, `trauma`), worn by every invader, the human invader too, the first of them its lead (`rank` 2) and the second its sergeant (1),
  the rest troopers (0) (with the spec's `human.lead`, a human invader is the lead and the NPC invaders are ranked from the sergeant down, the
  draws unchanged: LD10); each defender, the human defender too, draws one of the defenders' styles (`merc`, `borg`), a look seed of its own
  and one of its style's `weapons` (`scrap`, `pipe`; an invader's is `police`), all handed to `LoadoutConfig.apply` as its `style` (`{ look,
  seed, rank, weapon }`). A test actor never comes through here unless its setup declares a match, and keeps the weapon it asks for.
- **Squads** (`build_squads`, interface 23, over a `SquadsSpec`: `scenes/squads_spec.gd`, its `members`, `openings`, `rooms`, `human`
  and `claim_ttl`): one `Squad` (`ai/team/squad.gd`, interface 21,
  `docs/leadership.md`) per faction under `world`, named `Squad_<faction>`, over that side's combatants in spawn order (after `arm`, which
  ranks the unit), with the house's openings and rooms, the human as its leader when the spec's `human.lead` says it leads, and the claim
  ttl `callout_ttl_of(members)` (the `callout_ttl` of the first NPC's controller, 0 with none) unless the spec's `claim_ttl` names one (a
  test's squad of puppets, `TestSetup.squads`); each member is handed its squad
  (`bind_squad`: an NPC's controller's `squad`, and the human's `PlayerStack`, through `stack`, its `squad` and `own_claims`, true on the
  invaders' side only, so a human defender leader's step-ups rally nobody, D29). The leader is the squad's own rule (rank, then spawn order),
  or the human when it leads. Then `build_leader_overlay(world, squads)`: the `LeaderOverlay` (UI overlays, `watch` over every squad's
  `view`), hidden until `set_overlay` shows it (LD12, LD28). **`squads_over`** (interface 23) is the squad tail both `populate` and the
  test world's declared squads (`TestSetup.squads`) end with: the human (`human.node`) handed its stack radio (`bind_player`) first, then
  `build_squads`, then `build_leader_overlay`, shown when `leaders`; it returns them for the match handle (`squads`, `player_stack`,
  `leader_overlay`).
- **The bind rule, once** (`bind_npc(npc, rooms, openings, entry_point)`): an NPC's controller is handed the house `rooms`, its `openings`
  (for tactical entry) and, when given, its `entry_point` **before the NPC joins the tree**, so its first tick already knows them; the
  controller is found by its contract (the child with `control` and `rooms`, interface 7), since the `npc_controllers` group is joined only in
  `_ready`. An invader's entry point is the front entrance (`front_entrance(openings)`, `entry_point_for(faction, openings)`), a defender's
  none (`_front_opening` is the one lookup of the front entrance among the openings: `front_entrance` returns its `pos`, and `populate`
  hands the opening itself to the spawner). The test world binds its NPC actors by the same call.
- **Overlay routing, once** (`set_overlay(handle, flag, on)`): `NAV_HOLES` to the handle's `nav_debug` (`show_holes`, redrawn), `LEADERS`
  to its `leader_overlay` (`show_leaders`; a world with no squads has none), any other non-global flag to every combatant with an AI
  controller through `OverlayRegistry.apply` (`domain-ui-overlays`); `PERF` is not the match's.
- **The setup's specs:** `spec_from_setup(config, base)` and `random_spec(rng, base, most)` (the setup flow, above).

## Main's own overlays

Overlay flags live in `_overlay_flags` (one entry per row of `OverlayRegistry`), seeded by `_initial_overlays`: the registry's defaults, then
the `show_*` exports, then the player's saved toggles (`Settings.overlays`), which win over the exports; with Debug off every flag starts
off. `start_match` hands them to the match as its spec's `overlays`. The bar's `overlay_toggled` reaches Main's public
`set_overlay(flag, on)`, which saves each flip with `Settings.set_overlay` and applies it live: `PERF` to Main's own performance overlay; in
a spectator match an NPC's own flag to `SpectatorInspector.set_flag` (it shows overlays on the selected NPC only); everything else to the
match by the module's one rule, `MatchBuilder.set_overlay(_match, flag, on)` (the navigation holes, the squad leaders, and in a played match
every NPC's own overlay).

## NPC placement (`match_spawner.gd`, a `RefCounted`)

`MatchBuilder.populate` builds one per match and sets `world`, `spawn_clearance`, `invader_margin` and `bind` on it (`match_spawn_clear_test`
builds one of its own, with no `bind`); it records every NPC it places in `combatants`, in spawn order. It never calls `MatchBuilder`: the
builder hands it the bind rule as `bind`, so the dependency runs one way.

- `spawn_defender(rooms, rng, index)` — a random room; `clear_spot(rect, rng)` returns its centre when clear, else the first clear point of
  `SPAWN_TRIES` (32) drawn from the rng (inset from the walls). **Clear** (`is_clear`) = at least `spawn_clearance` from every solid
  furniture footprint (`NavBuilder.furniture_holes`, read off the shapes, so it is right on the frame the house is built) and twice that from
  every combatant already placed; the centre again, logged, when nothing is clear. (A body spawned inside a piece is ejected with it and the
  piece's momentum flings it.)
- `spawn_invader_team(rooms, rng, count, front, around := Vector2.INF)` — the invader team in one group (`docs/leadership.md`
  LD27), packed round one point:
  - **beside the front door** (`front`, the front entrance's opening `populate` found, `{}` with none; `_front_door` reads its centre, the way
    out of its room and its width):
    `_beside_front_door` puts the point against the house's outside wall, `DOOR_SIDE_OFFSET` (120 px) along it from the doorway's centre,
    past the jamb and out of the doorway's straight line, on the side drawn from `rng` (so a pinned house seed pins it), and
    `spawn_clearance` out from the wall; the wall hides the team from inside;
  - **round a human invader** (`around`: the human's start, which a member keeps clear of as of any combatant);
  - **in a house with no front door**, round `perimeter_point` of the rooms' bounding box grown by `invader_margin`, at `rng.randf()`.
  Each member takes `_group_spot`: the point, then rings twice `spawn_clearance` apart (about one slot per twice `spawn_clearance` of ring,
  `GROUP_RINGS` 6), the first spot `is_clear` of the furniture holes and every combatant placed (and `around`), `_outdoors` (out of every room
  grown by `spawn_clearance`, within twice `invader_margin` of the bounds) and, beside the front door, out of the doorway's straight strip
  (`_in_strip`: within half its width of its centre along the wall); the point, logged, when none is. Each invader is bound with the front
  entrance as its entry point (`bind`), so its controller heads straight for it.
- `add_npc(scene, name, pos)` instances the scene, sets its position, binds it (`bind.call(npc)`, when `bind` is valid) and only THEN
  adds it under `world` (a body added at the world origin and moved afterwards overlaps whatever
  stands there for a frame, and the physics launches that piece across the map), and appends it to `combatants`; `npc_name` names the first
  of a kind plainly (`Defender`, `Invader`), the rest `<base> 2`, …

## Tests

- The module: `tests/general/match_builder_builds_match_test.gd` (`s.declared_match` on a generated house: the handle's world, rooms and openings, the
  counts, the invaders' kit, unit and ranks, one squad per faction led by the rank rule, every controller bound with rooms, openings, the
  front entrance and its squad), `match_nav_ready_before_spawn_test.gd` (both maps `NavBuilder.ready` as the first NPC enters, its first walk
  target on the navmesh, for the module and for Main run whole; a match torn down during the wait places nobody),
  `test_world_invader_bound_as_match_test.gd` (a test-world invader bound as a match's, its declared squad's partner following).
- Placement: `match_spawn_team_beside_front_door_test.gd` (LD27, a sweep of every plan: the team beside the front door, out of its strip, on
  both sides across the seeds, no defender knowing a hostile on the first frame), `match_spawn_team_grouped_test.gd` (Main run whole: the team
  in one group; played as an invader, round the human), `match_spawn_team_no_front_door_test.gd` (a house with no front door: round a point
  of the ring), `match_spawn_clear_test.gd` (two defenders in a room with a bed over its centre start clear and apart),
  `match_spawn_origin_test.gd` (a counter against the world origin is not launched by a spawn).
- Arming and the setup: `match_setup_test.gd` (`arm` by faction, `random_spec`, `spec_from_setup`, the window's defaults off Main run whole),
  `match_styles_test.gd` (one unit per match from the seed, defenders mixed, every item in its wielder's weapon style),
  `saved_setup_grenade_counts_test.gd` (the saved grenade counts and an older save's defaults), `main_setup_start_builds_match_test.gd` (the
  window's Start builds the match it was set to: counts, sides, guns, grenades, outfits, the human's stack radio and squad).
- The leadership wiring: `lead_rank_test.gd` (LD10: the ranks with and without "Lead the team", the same style draws, `lead` saved),
  `command_menu_wiring_test.gd` (LD11: a match through `Main.start_match`, the menu orders a stun stack and both NPCs claim in bang mode; LD13
  / LD16: with "Hold for my go" ticked it holds until the menu's "Go into the kitchen", then bangs and goes in), `stack_player_wiring_test.gd`
  (`bind_player` attaches the stack with the house's doorways), `squad_leader_rule_test.gd` and `squad_succession_test.gd` (LD3, LD4),
  `tests/ai/stack/human_defender_leader_no_rally_test.gd` (D29: Main's match, a human defender leading: its step-up rallies nobody, its
  teammate keeps following), `tests/ui/leader_overlay_draw_test.gd` (the `LEADERS` toggle through `MatchBuilder.set_overlay`, in a test world
  and in Main's match).
- The tests drive Main only through its public members (`start_match`, `set_overlay`, its exports, the `match_world` group, `Player`,
  `SetupMenu.current_config()`), run whole in a world of its own by `tests/_main/main_probe.gd` (`domain-testing`).

**Interfaces:** 1 (World Generation), 6 (`LoadoutConfig`: arming a side), 7 (the characters and the AI controller, the overlays'
`show_<x>`), 9 (Navigation), 13 (the Tests button's scene change; the Testing world builds through the module), 14 (`Settings`, the settings
page, the dev command server), 17 (the human's `PlayerStack` and the stack markers), 18 (`Sound.focus`, the stun screen), 20
(`WorldLighting.light`), 21 (the squads, the command menu and order markers, the leader overlay), 22 (the setup window, the Von-server wait,
the match HUD, the spectator inspector, the overlay bar), 23 (`MatchBuilder`) — signatures in `architecture`.
