# Typed components: the part lists

The rest of `SKILL.md`'s "Typed components" convention, from the AI's parts on.

And its parts are reached by preload const with
  **no `class_name`**, as its modules always were: the controller's `_cadence`, `_comms` and `_reflexes`; behaviour's
  `task`, `fight`, `errand`, `entries`, `grenades`, `orders` and `gait`; entry's leaves `state` and `world` and its ten
  parts (`claim`, `approach`, `readiness`, `orders`, `grenade`, `listen`, `pie`, `sweep`, `hold`, `radio`); combat's
  `throw`; locomotion's `crowd`, `give_way`, `stall` and `doors`; the planner's `_walk`; perception's
  `sight`, `house`, `contacts`, `hearing`, `orders`, `grenades`, `entry`, `views` and `confinement` (where the NPC may act: its
  territory, the room a defend order keeps it to and its squad leash, refreshed each tick by the controller's reflexes, frozen into
  the decision snapshot for the planner and read live by behaviour and Combat); the launcher's `_probe`; the doorway
  geometry's `posts`, `slots` and `layouts`; the snapshot author's `_throws` and `_orders`; the squad's `stacks` and the
  human's stack's `reservation` and `step_up`. A part member read from outside its part is public on it, its underscore and
  any prefix the part's name says dropped (`entry_ready_timeout` is `tuning.entry.ready_timeout`, `_bang_stage`
  `grenade.stage`); one used only inside its part keeps its name. Behaviour's, locomotion's, the controller's, perception's
  (but its `confinement`) and the team's working parts hold their Node owner (`behavior`, `loco`, `controller`, `perception`, the squad's `stacks`
  its `squad`, the human's stack's `step_up` its `stack`). Entry is a `RefCounted`, so its parts hold only its `state` and
  `world` leaves: a part method that needs the entry or a sibling takes the `Entry` facade as its first parameter, `entry`,
  at the call, and never stores it. The doorway geometry (`AgentEntry`) is a `RefCounted` too: its parts take it as `entry`
  at the call and hold nothing of it. Where gdstyle's `max-parameters` (5) leaves no room for it, a public method folds two
  arguments into one (`EntryPosts.defend_spot` / `ambush_spot` take the member's `place: Vector2i`, x which post, y of how
  many) and a private chain reads it from the per-call context dict it already takes (`c["entry"]` / `f["entry"]`), never
  stored. Combat's `throw`, entry's leaves and the data leaves (the cadence, the running leaf, the planner's walk,
  perception's confinement, the probe) hold no owner (`tests/ai/ai_parts_free_suite.gd`, which holds the doorway geometry's parts too), nor
  does the human's stack's `reservation` leaf. The shell splits the same way
  (`docs/adr/0008-the-shell-split-into-parts.md`), each file by its kind: tuning that no scene authors becomes an ADR 0003
  holder (the camera's `CameraConfig` and `CameraShakeConfig`); a scene script's authoring surface that one instance owns
  becomes an exported `Resource` (`main.run`, `MainRun`, local to its scene, so Main's runtime writes to it never outlive a
  `reload_current_scene`); a static library splits per family into `class_name` static libraries (the sound bank's
  `SoundGuns`, `SoundImpacts`, `SoundFootsteps`, `SoundGrenades` and `SoundVehicles`), and a drawing API hands its shape
  type out as `class_name`s other domains name (`PixelShape`, `PixelConvexShape`); a widget's sub-tree becomes a Node child
  (the command menu's `Panel`, `command_panel.gd`, and the test browser window's list, `test_browser_list.gd`, a `Tree`),
  reached by preload const. The other parts are reached by preload const with no `class_name` too: Main's `_endless` (a
  data leaf) and `_overlays` (holding Main), `Keybinds.bindings` (the rebinding store and the saved format, handed the
  action tables and holding no owner), a world piece's `look` (a data leaf) and
  `physics` (holding the piece), `WorldLighting`'s `_pool` (holding the node), `TestContext`'s `verdict` and `bundle`
  (holding no owner: the context is an `Object` freed by hand, so a part method that needs it takes it at the call) and
  `TestSession`'s `von` (holding the session). The coverage tool's probe, the one template file the tool copies into a
  project, holds its parts as inner classes (`Run`, `Matches`, `MatchCost`, `Tests`).
