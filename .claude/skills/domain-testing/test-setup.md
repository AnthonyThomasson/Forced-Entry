# `TestSetup`: what `configure` declares

The reference `SKILL.md`'s "Writing a test" points to.

- **`configure(s: TestSetup)`** is data only, and the browser also calls it to list the switches.
  - World: `layout(rooms, doors, { thickness })` (a hand-laid building: `rooms` = `[{ key, type, rect,
    floor? }]`, `doors` = `[{ pos, width }]` on the walls the rooms share or on an outer edge; walls in the
    house style, doorways open, so the nav bake and `WorldGen.get_rooms` / `get_openings` work as for a
    house), `arena(rect, { floor, walls, thickness })` (a walled room in the house style, with the same
    `rooms` meta a house has) or `house(seed, plan := "", entrance := Vector2.ZERO)`. Default is an
    800×500 arena.
  - Objects: `object(id, catalogue_key_or_definition, pos, opts)`. Objects are placed under the
    house/arena root before the nav bake, so they are carved.
  - Vehicles: `vehicle(id, kind, pos, rotation := 0.0, props := {})` (`kind` `car` / `van`: `res://scenes/vehicle/<kind>.tscn`;
    rotation 0 = its front toward +x). Placed under the world root after the nav bake (not carved: the AI ignores vehicles), in
    place before they join the tree; a kind with no scene places nothing and `t.vehicle(id)` is then null. The world then waits
    one physics frame before the actors, because a new body joins the physics space only at the next step.
  - Actors: `actor(id, kind, pos, props)`. Kind is `puppet` (scripted), `player` (human-driven),
    `defender`, `invader`, or a scene path. `props` are set on the character before `_ready` (a `component:prop` key on that component of it, through
    `set_indexed`: `"anatomy:pose:gait:_stride"`, `tests/general/test_world_component_prop`; for example `max_health`, `start_slot`: 1 unarmed / 2 fists / 3 pistol / 4 key / 5 SMG / 6 assault rifle, `faction`, `movement:speed` and `movement:aim_point`, and the ammo props
    `inventory:start_rounds` (what the starting gun is loaded with; -1 = full) and `ammo:spare_magazine_types` (e.g. `[]` for none,
    `[&"extended"]`; the default is two standard magazines for each gun, so a test counting spares sets it)). Actors built here
    keep `default_inventory()` (every item) and the weapon they ask for: only a match (Main's, or a setup's `declared_match`) arms a spawn
    with its side's loadout (`MatchBuilder.arm`, `Character.inventory.set_loadout`). To retune a gun for one test, `set_static(GunConfig, "guns", modified_copy)` (e.g. spread 0 for a
    straight shot). Use
    `set_props(id, "GoalController", {...})` for a child's exports, a key an indexed path for an NPC's tunables
    (`{ "tuning:entry:enabled": true }`, interface 7) (the look is the `Wardrobe` child's: `set_props(id, "Wardrobe", { "rank": 2 })`,
    `look_seed`, `style`). An NPC actor is bound by the match's own rule before it joins
    the tree (`MatchBuilder.bind_npc`): the house's `rooms` and `openings`, and for an invader the front entrance as its
    `entry_point` (`MatchBuilder.entry_point_for`; none in a world with no front entrance, none for a defender).
  - Squads: `squads(opts := {})` builds one squad per faction over the setup's actors of that faction, in declaration order, as a
    match builds its own (`MatchBuilder.squads_over`, the squad tail `populate` ends with, after the actors spawn: the leader by rank, then
    declaration order, each member handed its squad), and the squad-leaders overlay over them, shown as the setup's overlays say. `opts.human` names an actor that
    leads its faction's squad as the human does: it is handed its stack radio (`MatchBuilder.bind_player`) and its squad through it,
    `own_claims` on the invaders' side only. `opts.claim_ttl` is how long (s) each squad keeps its members' entry claims (the `SquadsSpec`'s
    `claim_ttl` it hands `squads_over`): by default its NPCs' `tuning.radio.callout_ttl` (`MatchBuilder.callout_ttl_of`), which is 0 over puppets alone, so a squad of
    puppets keeps no claim unless `claim_ttl` names one: the two that radio claims name the NPCs' 6 s
    (`general/squad_go_latched_off_claims`, `ai/stack/stack_player_go_after_funnel_brush`). A world
    that declares no squads has none: its NPCs pick their own goals.
  - A whole match: `declared_match(overrides := {})` populates one over the staged world as Main does (`MatchBuilder.populate`, after the
    actors): `overrides` are `MatchBuilder.spec`'s (each side's `count`, `loadout` and `at`, `human`, `spawn_clearance`,
    `invader_margin`, ...), the world's seed its `seed` unless they name one, the setup's overlays its `overlays`. Its `human` may
    name an actor (`{ actor, side, lead, at }`, `actor` in place of `node`): that actor is joined to its side, armed and handed its
    stack radio. The match's NPCs are not test actors: read them off `t.world.match_handle`. Declare `squads` or `declared_match`, not both (an error).
  - Behaviour: `switch(name, on)` (the table in `SKILL.md`, "Behaviour switches") and `set_static(ConfigClass, prop, value)`. A `prop` the holder has no
    static var by (a switch row's too) is an error that fails the test (`TestWorld._set_static`), never a silent no-op.
  - Scripted Von: `von_script([{ pick: id, question: substring? }, …])` replaces the server with those
    picks (first rule whose id is offered; else the first offered option), so an AI test needs no server
    and is deterministic (`von_script(rules, latency_frames)` holds each answer back that many physics frames, `DecisionStub.latency_frames`, to test what an NPC does while a decision is in flight); `von_down()` makes every decision fail (the hold-steady fallback). Read what was
    asked off `DecisionStub.requests` (`{ state, question, options, pick }`, the AI decision sub-domain's stub). Ids are the decision tree's node
    ids (`combat`, `flank`, `engage`, …) and option ids. Keep `requires_von` tests for judging Von itself.
  - Presentation: `show_overlays(["show_vision", …])` and `camera_follow([ids])` (default frames all
    actors; the camera's hand-pan is off when a `player` actor is present, since WASD walks it).
    `lock_interaction([&"camera", …])` switches off user interactions in a headed run (`in-game-runner.md`, "Locking interactions").
