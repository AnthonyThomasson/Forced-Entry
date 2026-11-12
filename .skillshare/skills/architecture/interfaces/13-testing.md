13. **Testing → every domain** (a second composition root, like `main.gd`; the domain is `domain-testing`)
    `scenes/testing/` builds a test's world and drives it through the other interfaces only. Nothing depends on Testing.
    - **World:** WorldGen (1), or an arena / hand-laid layout from the three factories (2, with `WallFactory.openings_for`), staged by the
      match builder (23): `MatchBuilder.stage` runs the bake (9), the dusk lighting (20: `WorldLighting.light` after the bake) and the
      wait until both nav maps are `ready` before any actor enters. Each NPC actor is bound before it joins the tree by
      `MatchBuilder.bind_npc` (`MatchBuilder.entry_point_for` gives an invader the front entrance). `TestSetup.declared_match` runs
      `MatchBuilder.populate` over the staged world (read `t.world.match_handle`); `TestSetup.squads` runs `MatchBuilder.squads_over`, the
      human leader getting its stack radio from `MatchBuilder.bind_player` (read `t.world.squad(faction)`, `t.world.player_stack`).
    - **A district world:** `TestSetup.district(seed, plan := "", entrance := Vector2.ZERO)` declares `{ kind: "district", seed, plan,
      entrance }` (the runner's `--seed=N` pins its seed as it does a house's). `TestWorld` builds no district itself: it hands the spec
      to `MatchBuilder.stage` (23), which generates it (1) and bakes it over every tower and street. `t.world.district` is the district
      root (null in any other world); `t.world.house`, `rooms` and `openings` are the centre tower's, so every injected NPC is bound as in a
      house. A district world takes no placed objects (a `push_error`); the tower reads are `DistrictReads` (1).
    - **Actors:** character scenes plus the controller contract (7): a puppet `ScriptedController` or `player_controller.gd` on
      `character/character_base.tscn` (controller-less). `TestSetup.vehicle(id, kind, pos, rotation := 0.0, props := {})` instances
      `res://scenes/vehicle/<kind>.tscn` under the world root after the bake (not carved) and waits one physics frame; `t.vehicle(id)` reads
      it back (19); the puppet presses E with `use()` (the nearer of a door in reach and a vehicle), turns a door with `turn_door(steps)` (the wheel
      with E held) and drives with `drive(throttle, steer, handbrake)`, writing `movement.move_input` / `movement.run_input` as the
      player's keys do.
    - **Doors:** a hand-laid layout's doorway may declare `door: { material, style, hinge, swing_into, angle?, name? }`; the layout builder
      builds it with `WorldGen.door_definition` and `DoorFactory.spawn` (1, 2, 24) and `t.object(name)` finds it. A generated house is
      built with its doors unless the switch `worldgen.doors` (`WorldGenDoorConfig.enabled`, on by default) is off.
    - **Events:** `EventBus` and character signals (7, 10) feed its event log.
    - **Behaviour switches** set existing exported props and config-holder `static var`s by name, and an NPC's tunables by the indexed
      path `tuning:<topic>:<name>` (7). A name the holder lacks fails the test. Statics are restored after each test. Examples:
      `BloodConfig.enabled`, `PhysicsConfig.debris_enabled`, the Audio `audio.sound` switch.
    - **Perf replays:** the switch `testing.allocation_padding` (`AllocationPadding.enabled`) has `TestWorld.build` allocate loose nodes
      and physics RIDs first, shifting every instance id and RID; a catalog entry's `extra_switches` (name -> on, set by `TestSession`
      after the test's `configure`) lets a test replay another's world under its own terms (`tests/_perf/guard_replay.gd`).
    - **Von without a server:** script the answers through the AI decision sub-domain's `DecisionStub` statics and read what was asked off
      `DecisionStub.requests`, or (`requires_von`) replay the test's recording (`VonRecording`, `<name>_test.von.json`) through the stub's
      REPLAY mode, which `TestVonGate.mode_for` picks from the run flags (`--record-von`: RECORD, `--include-von` / `--require-von`: LIVE;
      a `live_only` test: no stub); the session's `von` part drives `DecisionServerLauncher` where a run needs the real server;
      `DecisionBudget.per_frame` (snapshots a frame may start) is set the same way.
    - **Runner:** `TestSetup.lock_interaction` (`camera` / `pause` / `overlays`) shuts out user input a test would trip over; the test
      sends its own through `TestContext.inject`, which the lock lets through. The runner builds the UI's `PerformanceOverlay` for the
      bar's `PERF` toggle and hands every other toggle to the world's `set_overlay`, which routes by the match's one rule
      (`MatchBuilder.set_overlay`; the bar is 22): any NPC flag reaches the NPCs in the bar's scope, and its "Show on" row (`OverlayRegistry.scopes_of(MODE_PLAY)`: `defenders`,
      `invaders`, `all`, default `all`) reaches the world's `set_overlay_scope(scope)`, which re-applies every toggle at once by `MatchBuilder.set_overlay_scope`. Its scene carries General's camera (`general/camera_controller.gd`; `GameTestSuite`
      makes one of its own): `frame(targets)` points it at the setup's camera targets (every actor by default); clear `pan_enabled` where a
      human-driven player walks on WASD or the test locks the camera.
    - **Pointer:** `Pointer.inject(screen)` (26) stands a screen point in for the mouse wherever its position is polled (the player's aim,
      the camera's look-ahead, the command menu's non-mouse fallback) until `Pointer.release()`, and never warps the real mouse; the test
      re-injects each frame to hold a world point under the pointer while the camera eases. `TestWorld.restore` releases it after each test.
    - **Sandboxes** (`sandboxes/`) may draw through Art (12: their own painter on `PixelCanvas`, rendered by `PixelArt.render` /
      `render_turned`) and render a sound with `SoundBank.recipe_for(profile)` / `SoundSynth.render(recipe, seed_value) ->
      AudioStreamWAV`, played on their own `AudioStreamPlayer2D`; the `Sound` service hears nothing of it (16).
    - **Main ↔ Testing:** Main reaches Testing only by changing scene to `testing/test_browser.tscn`; the browser's Back changes scene
      back to `main.tscn`. Beyond that Testing knows only the match builder (23). The UI widgets it shows (`test_browser_window.gd`,
      `test_browser_list.gd`, `test_result_hud.gd`, and the `TestBrowserState` value object) take plain dicts and emit signals.
    - **gdUnit4** (`addons/gdUnit4/`, v5.1.1) is Testing's one outward dependency: `GameTestSuite` and `UnitSuite` extend
      `GdUnitTestSuite`, and the session hook `test_report_hook.gd` (named in `project.godot`'s `[gdunit4]`) writes a run's report; no
      game domain names the addon (`domain-testing`).
