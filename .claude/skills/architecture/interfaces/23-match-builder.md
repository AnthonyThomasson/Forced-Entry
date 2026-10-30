23. **Main / Testing → MatchBuilder: building a match** (`scenes/match_builder.gd`, `class_name MatchBuilder`, a `RefCounted` of statics;
    part of the composition root, beside `main.gd`, with its placement helper `match_spawner.gd`, which only it uses; the flow and the
    placement rules are `domain-main`'s). Main's played, Watch and Endless matches and the Testing domain's worlds (13) build through it, so
    there is one way a match is staged, populated and bound. Nothing in the domains it wires knows it.
    - **The match spec**, a plain dict: `MatchBuilder.spec(overrides := {}) -> Dictionary` lays `overrides` over the defaults: `seed` (the
      house's, which also pins the placement, the guns and the styles; 0), `plan` (a floorplan key, "" = by the seed), `entrance` (where the
      front entrance lands), `house` (a house already built, a layout or an arena with its objects placed, staged in place of a generated
      one; null), `defenders` / `invaders` (`{ count, loadout, at }`: 1 each, the side's loadout, optional explicit start points, one NPC each,
      in place of placement; a side given keeps the defaults of what it does not name), `human` (`{ node, side, lead, at }`: the human's
      character, `&"defender"` / `&"invader"`, whether it leads its side's squad, an optional start; `{}` none), `wait_nav` (true),
      `spawn_clearance` (20 px), `invader_margin` (80 px) and `overlays` (`{ show_<x>: bool }` by `OverlayRegistry` flag, the debug overlays
      the match starts with; a flag it does not name starts off; `{}`). The side loadouts' defaults are `MatchBuilder.INVADER_LOADOUT`
      (1 stun, 1 frag, a helmet, a shirt, a plate carrier with a steel III plate front and back, tactical pants, boots; the gun the
      `LoadoutConfig` default) and `DEFENDER_LOADOUT` (`{}`), so a test's match carries what Main's does. `DEFENDER_FACTION` (`household`)
      / `INVADER_FACTION` (`invader`) are the scenes' faction tags.
    - **Building:** `build(match_spec, world: Node2D) -> Dictionary` (a coroutine: `stage`, then `populate`; `{}` when the match was torn
      down during the wait). `stage(match_spec, world) -> Dictionary` (a coroutine), the world stage: the spec's `house`, moved under
      `world`, or `WorldGen.generate` (1); `NavBuilder.build`, the `nav_debug.gd` overlay (`NavDebug`) and the `nav_updater.gd` re-baker
      (`NavUpdater`) (9); `WorldLighting.light(world, seed, rooms)` (20); then with `wait_nav` two physics frames and a wait until
      `NavBuilder.ready` holds on the planning map and on its steering map (at most `NAV_SYNC_MS`, 5000 ms of real time, then a
      `push_error`), so no NPC is placed before the maps answer with this house. `populate(handle, match_spec) -> Dictionary` over a staged
      handle: the defenders and the invader team placed through `match_spawner.gd` from one RNG seeded with `seed` (or at the sides' `at`
      points), each NPC bound before it joins the tree (the spawner's `bind`, a `Callable` `populate` hands it: `bind_npc` with
      `entry_point_for` the NPC's faction); the human joined to its side (its faction, its start, reparented just above the house);
      everyone armed, styled and ranked (`arm`); `squads_over`; every other overlay but the holes (the stage's) started through
      `set_overlay` by the spec's `overlays`.
    - **The match handle**, a plain dict: `{ world, house, rooms, openings, nav_debug }` from `stage`, plus `combatants` (every
      character in spawn order, the human last), `squads` (faction -> `Squad`), `player_stack` (the human's `PlayerStack`, or null) and
      `leader_overlay` from `populate`.
    - **The bind rule, once:** `bind_npc(npc, rooms, openings, entry_point := Vector2.ZERO)` hands an NPC's controller its `rooms`,
      `openings` and, when given, `entry_point`, **before the NPC joins the tree**; the controller is found by the group `npc_controllers` (interface 7:
      authored on the scene, so it holds before the tree). `entry_point_for(faction, openings)
      -> Vector2` is the front entrance for an invader, ZERO for a defender (`front_entrance(openings) -> Vector2`, ZERO in a house with
      none). `bind_squad(npc, squad, stack := null, own_claims := false)` (21), `bind_player(player, rooms, openings) -> Node` (17) and
      `callout_ttl_of(members) -> float` (21) are the squad's and the human's.
    - **Arming and squads:** `arm(characters, match_spec)` (each by its faction's side loadout through `LoadoutConfig.apply`, interface 6,
      the guns from `seed` XOR `LOADOUT_SEED_SALT`), `style(characters, match_spec) -> Array` (one `apply` style per character, from `seed`
      XOR `STYLE_SEED_SALT`: the match's police unit and its ranks, lead 2, sergeant 1, troopers 0, a leading human invader the lead; each
      defender a crew style; read off `CharacterStyleConfig.styles`, `styles_of(faction)`), `build_squads(world, squads_spec: SquadsSpec,
      stack := null) -> Dictionary` (`SquadsSpec`, `scenes/squads_spec.gd`: `members` (the combatants), `openings`, `rooms`, `human` := {},
      `claim_ttl` := `CLAIM_TTL_OF_NPCS`; one `Squad` per faction, interface 21, keeping claims `claim_ttl` s, or, at `CLAIM_TTL_OF_NPCS`
      (any negative value), `callout_ttl_of` the side) and `build_leader_overlay(world, squads) -> Node2D`;
      `squads_over(world, squads_spec: SquadsSpec, leaders := false) -> Dictionary` (its Arrays in `build_squads`' order, as `Squad.setup` takes them) is the squad tail `populate` and the Testing
      world's declared squads share: the human (`human.node`) handed its stack radio (`bind_player`), then `build_squads`, then
      `build_leader_overlay`, shown when `leaders`; it returns `{ squads, player_stack, leader_overlay }`.
    - **Overlay routing, once:** `set_overlay(handle, flag, on)` on a handle, or any dict with its `nav_debug`, `leader_overlay` and
      `combatants`: `NAV_HOLES` to the `nav_debug`'s `show_holes`, `LEADERS` to the `leader_overlay`'s `show_leaders` (none, nothing), any
      other non-global flag to each combatant with an AI controller through `OverlayRegistry.apply`; `PERF` is the caller's own (22).
    - **The setup's specs** (Main's): `spec_from_setup(config, base := {}) -> Dictionary` reads the setup window's config (22) into a spec
      over `base` (its `seed`, each side's `count` and loadout keys, the human on its `side` with `lead` in a played match, none in Watch or
      Endless); `random_spec(rng, base, most) -> Dictionary` draws an endless run's next one (seed 0, each count in 1..its most, a random gun
      and outfit per side keeping the grenade counts).
    - **Main's one way in:** `Main.start_match(spec) -> Dictionary` builds `spec` under a fresh `World` node (`MatchBuilder.build`, the spec's
      `overlays` replaced by Main's flags) and wires the HUDs on the handle (17, 18, 21, 22); `{}` when the match was torn down while built.
    - The Testing domain (13): `TestWorld` stages through `stage` (`wait_nav` on), binds each NPC actor through `bind_npc` with
      `entry_point_for`, populates a declared match through `populate` (`TestSetup.declared_match`, read as `t.world.match_handle`), builds declared squads
      through `squads_over` (`TestSetup.squads`) and routes its overlay toggles through
      `set_overlay`; it has no bake, light, nav-wait or bind code of its own.
