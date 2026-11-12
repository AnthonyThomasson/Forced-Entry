# The player's view cone is rebuilt in slices, and the cone shown is 2 to 4 frames old

The view's cone (`docs/player-vision.md` V1) costs 6 to 11 ms a physics frame in a district match while the viewer walks or turns:
it is rebuilt almost every frame (the eye changes every frame), whole, in one tick. In a 10v10 with the view on an NPC that tick is
what the match's frame budget cannot spare (issue #195). The rebuild is now a **job stepped by work units** (`ViewCone.begin` / `step`, a unit being a ray cast, a
region shape query or a far-face probe), run `VisionSliceConfig.slice_units` (about 3.5 ms) a physics tick by `ViewPipeline`, and the
cone is published when the job is done. The cone the player sees is therefore the exact cone of the pose the job started from, 2 to 4
frames old (a job of 3 slices). This record says why that latency is accepted and what was not done.

## What the pipeline does, and what it never does

- A stale view starts a job from the live eye, facing and sight; each tick steps it; on completion the cone, bubble and eye are
  swapped in together (double-buffered, `ViewConeBuffer`), `SeenArea` is written and the memory paints from them.
- It **never shows a mix of two worlds**: a change of the world between slices (a blocker moved, changed shape, joined or left, a
  blocking character, a changed sight number) drops the job and starts it again from the live pose. After `restart_cap` (2) restarts in
  a row the next is built whole in one frame, so a world that changes every frame still gets a cone, every fourth frame (a whole build a frame was the cost before).
- It **never extrapolates**: the cone published is a fresh cone of an eye the viewer stood at, so the memory (V4, never cleared)
  never holds area no eye saw. A change of the viewer's pose alone lets the job finish on its start pose (restarting for it would
  mean a moving viewer never publishes).
- An eye that jumps (a teleport, a vehicle: past `jump_px`, 48) is built whole at once, so the cone is never more than a jump behind;
  so is a view's first cone.

## The latency accepted

A walking viewer's cone is up to 4 frames (about 17 px at a run, 10 px walking) behind its eye, the facing 2 to 4 frames behind its
turn. The user accepted that (issue #195, Agent Brief rule 7) because the alternative is a frame budget the 10v10 cannot meet. It
replaces the earlier pose lag (`rebuild_gap`: an eye 5 px or a facing 1 degree off waited one frame), which was the same trade at
one frame, and only for a slow walker: a quick turn (6 degrees a frame) was past its bounds and rebuilt every frame.
Now the job's length is the lag and a moving viewer's cost is a slice a frame, whatever the pose does. A mover entering or leaving the
seen area (V11) shows when the next cone publishes.

## Not done

- **Porting the cone to native code** (GDExtension / C++). It would cut the GDScript half of the rebuild (about 4 of 10 ms), not the
  engine's ray casts and shape query, and it adds a native build step to a project that is pure GDScript. The slice is a bound on a tick whatever the code is made of; a native port would shorten the job,
  not remove the need to cut it.
- **Two slices instead of a work-unit budget.** Half the cone in each of two frames halves the age but leaves a 5 ms tick, and the
  cost of a world with more shapes grows with no bound. Units bound the tick, and what a job costs (1,100 to 1,400 units in a match's
  view, a house's far fewer) decides its length, not the other way about.
- **Freezing the world for the job** (a snapshot of the blockers). The rays read the live physics space, so a snapshot would have
  to copy every shape in reach each job; checking `ViewWatch` each slice (0.005 ms) and restarting costs less and keeps the cone
  the plain one's, vertex for vertex.
- **Extrapolating the cone** to the live pose (turning or shifting the old polygon). A polygon from a pose the eye never stood at is
  a made-up cone, and the memory would paint it.

## Where it lives

`scenes/vision/view_pipeline.gd` (`ViewPipeline`: the start, restart, whole and publish rules), `view_cone.gd` (the job; the vision
skill's `cone-job.md`), `view_watch.gd` (`world_changed`: what the job asks each tick), `vision_slice_config.gd`; the reads
`PlayerView.starts()`, `building()` and `published_pose()` (interface 25). Tests: `vision/pose_lag_bounds`,
`vision/cone_restarts_on_world_change`, `vision/cone_skip_exact_sliced`.
