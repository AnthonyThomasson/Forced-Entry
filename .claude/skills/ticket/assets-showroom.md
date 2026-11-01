# Setting up the staging room

A showroom is deleted before its audit, so this is the shape to build each time (file names are suggestions).

- **The sandbox stays thin.** `configure` lays the floor, the `player` actor, a camera on it and a few real props for scale.
  `run` adds the world nodes and returns. The `GameTest` object, and every lambda or signal bound to it, is freed once
  `run()` returns: anything live (buttons, pads, timers, puppets) is a node under `t.world`, never a method of the test.
- **A stage node owns the sets** (`set_stage.gd`). The sets are a `const` table in picker order. A set resolves to a *cast*:
  `{ row: [{ look, outfit, caption }], walker: {…} }`, so a new kind of set is a new cast function, not a new layout. The
  stage adds everything it spawns beside itself (`get_parent().add_child`) and keeps a list of it. On a pick it
  `remove_child`s then `queue_free`s each node, so the next set's bodies never share the physics space with the last set's.
- **The picker** (`set_picker.gd`) is a `CanvasLayer` panel at the bottom with Previous / Next (`focus_mode` none, so Space
  and Enter never press them) and a label `n / N   title` plus one line. It emits `picked(index)`; the stage stages that set.
- **Bodies are real characters** (`character_base.tscn` + a `ScriptedController`), props and the variant set before they join
  the tree and the position set before `add_child`. The variant goes in through a per-body switch on the domain node (a
  temporary `showroom_*` property) when a `static` would restyle every body at once. Rows are 110 px apart: a character's
  legs sweep for anything within 86 px every physics step.
- **Motion is a driver node** (`pose_driver.gd`) that steers the puppets: a turntable in 8 held steps (turning all the time
  repaints a body every frame), and a walker on a loop. Captions are `floor_label.gd` nodes under each body.
- **The player tries variants on** by stepping onto floor pads (`look_pads.gd`), which set the same per-body switch.
- **Headless cycle:** the stage reads a user arg `--showroom-cycle=<s>` and presses Next every `s` sim seconds through every
  set and back to the first, then quits. `--play` is the runner's own flag, so launch the runner through Godot
  (`tools/run_tests.sh` runs batches only, and those never see sandboxes), then scan the log:
  `"$GODOT" --headless --path . --fixed-fps 60 --log-file "$out/godot.log" res://scenes/testing/test_runner.tscn -- --play <words> --showroom-cycle=1`,
  then `python3 tools/scan_godot_log.py "$out/godot.log" --from=0`.
- **After a round of picks, add team sets** after the variant sets, each showing the picks as a match would field them: that
  side's match kit (the invaders' `MatchBuilder.INVADER_LOADOUT` outfit, a defender's `LoadoutConfig.outfit_of({})`), a few
  bodies plus a walker, and team-wide rules as the user stated them (a side that wears one picked look per match gets one set
  per look; a side that mixes picks per body gets a crew seeded per body, with fixed seeds so every visit looks the same).
  The user judges the picks together before the plan.
- **Environment showrooms** stage one house at a time through `WorldGen.generate(seed, plan, ...)` with fixed seeds (never
  World-Gen's internals), Previous / Next through floorplans and a second row of style buttons re-staging the same house.
