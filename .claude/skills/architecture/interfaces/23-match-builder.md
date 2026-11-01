23. **Main / Testing → MatchBuilder: building a match** (`scenes/match_builder.gd`, `class_name MatchBuilder`, a `RefCounted` of statics; part of
    the composition root with its placement helper `match_spawner.gd`, which only it uses; the flow and placement rules are `domain-main`'s).
    Main's played, Watch and Endless matches and the Testing domain's worlds (13) build through it: one way to stage, populate and bind a
    match. Nothing in the domains it wires knows it.
    - **The match spec**, a plain dict: `MatchBuilder.spec(overrides := {}) -> Dictionary` lays `overrides` over the defaults. `seed` (the
      house's; also pins placement, guns and styles; 0), `plan` (floorplan key, "" = by the seed), `entrance` (where the front entrance
      lands), `house` (a house, layout or arena already built, staged instead of a generated one; null), `defenders` / `invaders` (`{ count,
      loadout, at }`: 1 each, the side's loadout, optional explicit start points, one NPC each; a side given keeps the defaults of what it
      does not name), `human` (`{ node, side, lead, at }`: the human's character, `&"defender"` / `&"invader"`, whether it leads its side's
      squad, an optional start; `{}` none), `wait_nav` (true), `spawn_clearance` (20 px), `invader_margin` (80 px), `overlays` (`{ show_<x>:
      bool }` by `OverlayRegistry` flag; a flag not named starts off). Side loadouts: `INVADER_LOADOUT` (a stun, a frag, helmet, shirt, plate
      carrier with steel III plates, tactical pants, boots; the gun is the `LoadoutConfig` default) and `DEFENDER_LOADOUT` (`{}`), so a
      test's match carries what Main's does. `DEFENDER_FACTION` (`household`) / `INVADER_FACTION` (`invader`) are the factions.
    - **Building:** `build(match_spec, world: Node2D) -> Dictionary` is a coroutine: `stage`, then `populate`; `{}` when the match was torn
      down during the wait.
      - `stage(match_spec, world) -> Dictionary` (coroutine) is the world stage: the spec's `house` moved under `world`, or
        `WorldGen.generate` (1); `NavBuilder.build`, the `nav_debug.gd` overlay and the `nav_updater.gd` re-baker (9);
        `WorldLighting.light(world, seed, rooms)` (20). With `wait_nav`: two physics frames, then until `NavBuilder.ready` holds on the
        planning map and its steering map (at most `NAV_SYNC_MS`, 5000 ms real time, then a `push_error`), so no NPC is placed before the
        maps answer with this house. Returns the handle `{ world, house, rooms, openings, nav_debug }`.
      - `populate(handle, match_spec) -> Dictionary` over a staged handle: defenders and the invader team placed through `match_spawner.gd`
        from one RNG seeded with `seed` (or at the sides' `at`), each NPC bound before it joins the tree (the spawner's `bind` Callable:
        `bind_npc` with `entry_point_for` the NPC's faction); the human joined to its side (faction, start, reparented just above the
        house); everyone armed, styled and ranked (`arm`); `squads_over`; every overlay but the holes (the stage's) started through
        `set_overlay` by the spec's `overlays`. Adds to the handle `combatants` (spawn order, the human last), `squads` (faction ->
        `Squad`), `player_stack` (or null), `leader_overlay` and `view` (the human's `PlayerView`, built last by `PlayerView.watch`, 25: null
        with no human and while `VisionConfig.enabled` is off).
    - **The bind rule, once:** `bind_npc(npc, rooms, openings, entry_point := Vector2.ZERO)` hands the NPC's controller its `rooms`,
      `openings` and, when given, `entry_point`, **before the NPC joins the tree**; the controller is found by the group `npc_controllers`
      (7: authored on the scene, so it holds before the tree). `entry_point_for(faction, openings) -> Vector2` is the front entrance for an
      invader, ZERO for a defender (`front_entrance(openings)`, ZERO in a house with none). `bind_squad(npc, squad, stack := null,
      own_claims := false)` (21), `bind_player(player, rooms, openings) -> Node` (17) and `callout_ttl_of(members) -> float` (21) are
      the squad's and the human's.
    - **Arming and squads:**
      - `arm(characters, match_spec)`: each by its faction's side loadout through `LoadoutConfig.apply` (6), the guns drawn from `seed` XOR
        `LOADOUT_SEED_SALT`.
      - `style(characters, match_spec) -> Array`: one `apply` style per character, from `seed` XOR `STYLE_SEED_SALT` (`docs/outfits.md`). The
        police unit's lead is rank 2, sergeant 1, troopers 0 (a leading human invader takes the lead); each defender gets a crew style. Read
        off `CharacterStyleConfig.styles`, `styles_of(faction)`.
      - `build_squads(world, squads_spec: SquadsSpec, stack := null) -> Dictionary`. `SquadsSpec` (`scenes/squads_spec.gd`): `members` (the
        combatants), `openings`, `rooms`, `human` := {}, `claim_ttl` := `CLAIM_TTL_OF_NPCS` (any negative value = `callout_ttl_of` the
        side). One `Squad` per faction (21); the roster's `ambush_attacks` is set for the defenders' side only (LD29).
        `build_leader_overlay(world, squads) -> Node2D`.
      - `squads_over(world, squads_spec, leaders := false) -> Dictionary` is the squad tail `populate` and the Testing world's declared
        squads share: the human (`human.node`) gets its stack radio (`bind_player`), then `build_squads`, then `build_leader_overlay`,
        shown when `leaders`; returns `{ squads, player_stack, leader_overlay }`.
    - **Overlay routing, once:** `set_overlay(handle, flag, on)` takes a handle, or any dict with `nav_debug`, `leader_overlay` and
      `combatants`: `NAV_HOLES` to the `nav_debug`'s `show_holes`, `LEADERS` to the `leader_overlay`'s `show_leaders`, any other non-global
      flag to each combatant by one shared gate: through `OverlayRegistry.apply` as given for an NPC `OverlayRegistry.in_scope` of the handle's `overlay_scope` (`all` with none), all-off for the rest, nothing for a
      character with no AI controller. `PERF` is the caller's own (22). `set_overlay_scope(handle, flags, scope)` records `scope` (`all`, `defenders` or `invaders`) on the handle as `overlay_scope` and applies `flags` at once
      by the same gate and loop (the human has no controller, so no overlays); the Testing world calls it with a handle of the one actor it spawns, so an actor spawned after a scope follows it.
    - **The setup's specs** (Main's): `spec_from_setup(config, base := {}) -> Dictionary` reads the setup window's config (22) into a spec
      over `base` (its `seed`, each side's `count` and loadout keys, the human on its `side` with `lead` in a played match, none in Watch or
      Endless); `random_spec(rng, base, most) -> Dictionary` draws an endless run's next one (seed 0, each count in 1..its most, a random
      gun and outfit per side keeping the grenade counts).
    - **Main's one way in:** `Main.start_match(spec) -> Dictionary` builds `spec` under a fresh `World` node (`MatchBuilder.build`, the
      spec's `overlays` replaced by Main's flags) and wires the HUDs on the handle (17, 18, 21, 22); `{}` when the match was torn down.
    - **Testing (13):** `TestWorld` stages through `stage` (`wait_nav` on), binds each NPC actor through `bind_npc` with `entry_point_for`,
      populates a declared match through `populate` (`TestSetup.declared_match`, read as `t.world.match_handle`), builds declared squads
      through `squads_over` (`TestSetup.squads`) and routes overlay toggles through `set_overlay`. It has no bake, light, nav-wait or bind
      code of its own.
