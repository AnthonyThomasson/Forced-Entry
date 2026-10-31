# `TestSetup`: what `configure` declares

`scenes/testing/test_setup.gd` documents each call; this holds what its doc comments do not say. `configure` is data
only (the browser also calls it to list the switches).

- **World, one of:** `layout(rooms, doors, opts)` (a hand-laid building in the house style: the nav bake and
  `WorldGen.get_rooms` / `get_openings` work as for a house), `arena(rect, opts)` (a walled room with the same `rooms` meta)
  or `house(seed, plan, entrance)`. The default is an 800×500 arena.
- **Objects** are placed under the house or arena root before the nav bake, so they are carved.
- **Vehicles** are placed after the nav bake and are not carved (the AI ignores vehicles); the world then waits one
  physics frame before the actors, because a new body joins the physics space at the next step. A kind with no scene
  places nothing and `t.vehicle(id)` is null.
- **Actors:** kind `puppet` (scripted), `player` (human-driven), `defender`, `invader` or a scene path. `props` are set
  before `_ready`; a `component:prop` key reaches a component through `set_indexed` (`"anatomy:pose:gait:_stride"`,
  `"inventory:start_rounds"`, `"ammo:spare_magazine_types"`, `"movement:speed"`; the default is two standard magazines per
  gun, so a test counting spares sets it). `start_slot` is an `ItemRegistry` slot.
  - Actors built here keep `default_inventory()` (every item): only a match (Main's, or `declared_match`) arms a spawn
    with its side's loadout (`MatchBuilder.arm`). Retune a gun for one test with `set_static(GunConfig, "guns", copy)`.
  - `set_props(id, child, props)` sets a child's exports; a key as an indexed path reaches an NPC's tunables
    (`{ "tuning:entry:enabled": true }`, interface 7); the look is the `Wardrobe` child's (`rank`, `look_seed`, `style`).
  - An NPC actor is bound by the match's own rule before it joins the tree (`MatchBuilder.bind_npc`: the house's `rooms` and
    `openings`; an invader's front entrance as its `entry_point`, none in a world without one).
- **Squads:** `squads(opts)` builds one squad per faction over the setup's actors, in declaration order, as a match
  builds its own (`MatchBuilder.squads_over`), with the squad-leaders overlay. `opts.human` names an actor that leads its
  faction's squad as the human does (handed its stack radio through `MatchBuilder.bind_player`). `opts.claim_ttl` is how
  long a squad keeps its members' entry claims; by default the NPCs' `tuning.radio.callout_ttl`, which is 0 over puppets
  alone, so a squad of puppets keeps no claim unless `claim_ttl` names one. A world that declares no squads has none.
- **A whole match:** `declared_match(overrides)` populates one over the staged world as Main does
  (`MatchBuilder.populate`); `overrides` are `MatchBuilder.spec`'s. Its `human` may name an actor (`{ actor, side, lead,
  at }`): joined to its side, armed and handed its stack radio. The match's NPCs are not test actors: read them off
  `t.world.match_handle`. Declare `squads` or `declared_match`, not both (an error).
- **Behaviour:** `switch(name, on)` (`test_switches.gd`) and `set_static(Class, prop, value)`. A prop the holder has no
  static var for is an error that fails the test, never a no-op.
- **Scripted Von:** `von_script(rules, latency_frames)` replaces the server with picks (first rule whose id is offered,
  else the first offered option), so an AI test needs no server and is deterministic; `latency_frames` holds each answer
  back to test what an NPC does while a decision is in flight. `von_down()` makes every decision fail (the hold-steady
  fallback). What was asked is `DecisionStub.requests`. Ids are the decision tree's node and option ids. Keep
  `requires_von` for judging Von itself.
- **Presentation:** `show_overlays([...])`, `camera_follow([ids])` (default frames all actors; the hand-pan is off when a
  `player` actor is present, since WASD walks it) and `lock_interaction([&"camera", …])`
  (`in-game-runner.md`, "Locking interactions").
