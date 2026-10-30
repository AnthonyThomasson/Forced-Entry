13. **Testing → every domain** (a second composition root, like `main.gd`)
    `scenes/testing/` builds a test's world and drives it through the other interfaces only:
    WorldGen (1, incl. the catalogue lookups) or an arena / hand-laid room layout from the three
    factories (2, incl. `WallFactory.openings_for`), staged as Main stages a match, through the match builder (23: `MatchBuilder.stage`
    over the house, layout or arena it built with its objects in place, so `NavBuilder` and `nav_updater.gd` (9) and the dusk lighting
    (20: `WorldLighting.light` after the nav bake) are Main's own path, then the wait until both navigation maps are `ready` before any
    actor enters), the character scenes plus the controller contract (7: each NPC actor bound by the match's one rule, `MatchBuilder.bind_npc`,
    before it joins the tree: the house's `rooms` / `openings` and, for an invader, the front entrance as its `entry_point`,
    `MatchBuilder.entry_point_for`), a declared match (`TestSetup.declared_match`: `MatchBuilder.populate` over the staged world, read with
    `t.world.match_handle`) or declared squads over the actors (`TestSetup.squads`: `MatchBuilder.squads_over`, the human leader handed its
    stack radio through `MatchBuilder.bind_player`, read with `t.world.squad(faction)` / `t.world.player_stack`) — a puppet
    `ScriptedController` or `player_controller.gd` on `character/character_base.tscn` (the
    controller-less character), the vehicle scenes (19: `TestSetup.vehicle(id, kind, pos, rotation := 0.0, props := {})` instances
    `res://scenes/vehicle/<kind>.tscn` under the world root after the nav bake (not carved) and waits one physics frame so the new bodies
    are in the space; `t.vehicle(id)` reads it back; the puppet presses E with `use_vehicle()` and drives with
    `drive(throttle, steer, handbrake)`, writing `movement.move_input` / `movement.run_input` as the player's keys do) — and `EventBus` / character
    signals (7, 10) for its event log.
    Behaviour switches set existing exported props and config-holder `static var`s by name, an NPC's tunables by indexed path on
    its controller (`tuning:<topic>:<name>`, interface 7) (duck-typed, like the overlay flags; a name the holder does not have is an error, which fails the test); a test can also script the Von answers through the AI
    decision sub-domain's `DecisionStub` statics, and read what was asked off `DecisionStub.requests` (`decision_stub.gd`, read by
    `decision_client.gd`; the test session's `von` part also drives the
    `DecisionServerLauncher` for the tests that need the real server; `DecisionBudget.per_frame`, the
    snapshots a frame may start, is set the same way) so AI
    wiring runs without a server. In the in-game runner a test can switch off user interactions that
    would change its result with `TestSetup.lock_interaction` (`camera` / `pause` / `overlays`), sending
    its own input through `TestContext.inject` so the lock lets it through; the runner also builds the
    UI's `PerformanceOverlay` for the overlay bar's `PERF` toggle and hands every other toggle to the world's `set_overlay`, which routes it
    by the match's one rule (`MatchBuilder.set_overlay`: the navigation holes to the world's `nav_debug.gd`, kept current by `nav_updater.gd`,
    the squad leaders to the `LeaderOverlay` of its declared squads or match, any other to its NPCs; the bar and `OverlayRegistry` are
    interface 22). Its scene carries General's camera (`general/camera_controller.gd`;
    the gdUnit4 base suite `GameTestSuite` makes one of its own), which it points at the setup's camera targets (every actor by default) with `frame(targets)` and whose `pan_enabled` it clears where a
    human-driven player walks on WASD or the test locks the camera. Examples of the knobs: the Physics domain's `BloodConfig.enabled` /
    `PhysicsConfig.debris_enabled` master switches and the Audio domain's `audio.sound` switch; statics are restored after each test.
    A sandbox (`sandboxes/`, e.g. a `ticket-assets` showroom) may also draw through Art (12: its own painter on
    `PixelCanvas`, rendered by `PixelArt.render` / `render_turned`) and render a sound with
    `SoundBank.recipe_for(profile)` / `SoundSynth.render(recipe, seed_value) -> AudioStreamWAV`, played on its own
    `AudioStreamPlayer2D`; the `Sound` service hears nothing of it (16). Main
    reaches it only by changing scene to `testing/test_browser.tscn`, and the browser's Back changes scene back to
    `main.tscn`; beyond that scene change Testing knows only the root's match builder (23); the UI widgets it shows
    (`test_browser_window.gd` with its list, `test_browser_list.gd`, and `test_result_hud.gd`) take plain dicts (the window's `TestBrowserState` too, a UI value object) and emit signals. Nothing
    depends on Testing. Its one outward dependency beyond the game is the gdUnit4 addon (`addons/gdUnit4/`, v5.1.1): its
    base suites `GameTestSuite` and `UnitSuite` extend `GdUnitTestSuite`, and its session hook (`test_report_hook.gd`, named in
    `project.godot`'s `[gdunit4]` section) writes a run's report, steps the editor's GdUnit panel's run as `--fixed-fps` steps
    the command line's and keeps its reports out of the checkout (`domain-testing`, "The GdUnit panel"); no game domain names it.
