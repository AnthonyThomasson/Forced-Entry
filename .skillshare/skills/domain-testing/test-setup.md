# `TestSetup`: what `configure` declares

`scenes/testing/test_setup.gd` documents each call; this holds what its doc comments do not say. `configure` is data
only (the browser also calls it to list the switches).

- **World, one of:** `layout(rooms, doors, opts)` (a hand-laid building in the house style: the nav bake and
  `WorldGen.get_rooms` / `get_openings` work as for a house), `arena(rect, opts)` (a walled room with the same `rooms` meta),
  `house(seed, plan, entrance)` or `district(seed, plan, entrance)` (a downtown district: `MatchBuilder.stage` generates it and bakes the
  nav over its streets as Main's match does; `TestWorld.district` is its root, `house` / `rooms` / `openings` the centre tower's, so a
  district world takes no placed objects, `push_error`). The default is an 800×500 arena.
- **Objects** are placed under the house or arena root before the nav bake, so they are carved.
- **Doors:** a `layout` doorway may declare one: `{ pos, width, door: { material, style, hinge, swing_into, angle?, name? } }`. `LayoutBuilder`
  builds it through `DoorFactory.spawn` from `WorldGen.door_definition(material, style)` (the hinge a point on the jamb where the walls'
  ends stand: 6 px in from the `width` gap's edge in a layout's 12 px walls) and `TestWorld` registers it in `objects` under its node
  `name`, so `t.object(name)` finds it. The test works it through the door contract (`toggle`, `turn_by`, `open_fully`) or the Use key:
  the puppet's `use()` / `turn_door(steps)`, or a `player` actor driven by injected events (`Input.action_press(Keybinds.USE)` for a tap
  or a hold, a wheel notch or a pan gesture through `TestContext.inject`; `tests/character/door_use_key_test.gd`,
  `door_scroll_open_test.gd`). A player's aim is the mouse: `tests/_character/player_pointer_probe.gd` (`Pointer.aim(t, you, point)`
  puts a world point under it, again each frame while the test camera still eases; `Pointer.at(event, pointer)` gives an injected wheel
  or pan event the pointer's place). A puppet's punch needs `start_slot: 2`. A generated house is built with its doors unless the switch
  `worldgen.doors` (`WorldGenDoorConfig.enabled`) is off; the AI scenario families that predate doors turn it off (`# Doors off until
  #159 makes this family door-aware.`).
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
- **The player's view:** `view(actor_id)` names the actor the world's `PlayerView` follows when the `vision.enabled` switch is on (else
  the first `player` actor); `TestWorld` watches it as `MatchBuilder.populate` watches the human, and a declared match with a human
  has its view from `populate`, not from here (`tests-vision.md`).
- **Behaviour:** `switch(name, on)` (`test_switches.gd`) and `set_static(Class, prop, value)`. A prop the holder has no
  static var for is an error that fails the test, never a no-op.
- **Scripted Von:** `von_script(rules, latency_frames)` replaces the server with picks (first rule whose id is offered,
  else the first offered option), so an AI test needs no server and is deterministic; `latency_frames` holds each answer
  back to test what an NPC does while a decision is in flight. `von_down()` makes every decision fail (the hold-steady
  fallback). What was asked is `DecisionStub.requests`. Ids are the decision tree's node and option ids.
- **Recorded Von:** `"requires_von": true` in `describe()` runs the real decision pipeline with Von's recorded answers
  (`<name>_test.von.json` beside the test; `tools/run_tests.sh --record-von --id=<id>` writes it, `gotchas.md`). Assert world
  outcomes and `require` the premise as for any test, never that a pick was made. `"live_only": true` (the transport itself,
  `runner-flags.md`) keeps the real server.
- **Presentation:** `show_overlays([...])`, `camera_follow([ids])` (default frames all actors; the hand-pan is off when a
  `player` actor is present, since WASD walks it) and `lock_interaction([&"camera", …])`
  (`in-game-runner.md`, "Locking interactions").
