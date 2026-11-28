# Player vision

In a played match the screen shows only what the human's character sees. What it saw before is drawn in a dark cool greyscale
(black where it never looked): the world as it stands now, with what has been seen of what moves or lies loose (V12); and nothing
that moves is drawn out of view. Behaviours V1 to V12
are the spec; each has its tests named under it, following the convention of `docs/lighting.md`. The tests are in `tests/vision/`
(`tools/run_tests.sh --domain=vision`) through `tests/_vision/vision_probe.gd`, which keeps the spec's numbers as its own consts
and reads the game only through the names interface 25 publishes, so a test checks this file and not the code. The code is the
Vision domain (`scenes/vision/`, skill `domain-vision`, `docs/adr/0011-the-vision-domain.md`); the shared rules it stands on are
General's (`SightRay`, `ViewLayers`, `SeenArea`: `architecture` interface 11).

All distances are px and angles degrees unless said. The numbers are `VisionConfig`'s and `VisionGroundConfig`'s (`scenes/vision/`) and, for what a character
sees by, `CharacterVisionConfig`'s (`scenes/character/`).

## What is built

`PlayerView.watch(root, character)` (the match builder's `populate` for Main's human, the Testing world for its viewer) adds one
`PlayerView` node under the world, in the group `player_view`, with the reads `cone()`, `bubble()`, `sees(point)`, `viewer()`,
`rebuilds()` and the part it draws with, `ground` (`ViewGround`): two textures the 3D scene's toon shaders read by a surface's own
ground position. The **live mask** is a square window of the world about the camera holding the cone, its edge feathered; the
**seen mask** (the memory) covers the floors' bounds, never cleared, and only gains where a cone was published. Nothing is
photographed or laid over the picture: the world is lit and drawn as it stands and the shaders dim it by the masks (V12).
The world's own things carry the rest: each moving thing's domain sets its `visibility_layer` (`ViewLayers.set_moving`), which Art's
`MeshCarrier` and `MeshFollower` read to hide a mover the cone does not reach, and each overlay owner makes its node an overlay (`ViewLayers.overlay`),
which `GroundLayer` lays flat on the ground over the picture.

The words the spec uses: the **view** is the whole of this; the **cone** is the polygon of what the viewer sees now (the cone
round its facing and the bubble round it); the **memory** is where the viewer has seen (the seen mask); a thing is **moving** or
**at rest** by the bit it sits on; the **seen area** is what General's `SeenArea` says the cone shows live (`GLOSSARY.md`).

## Behaviours

**V1. The cone.** The human sees what the NPCs see, by their default numbers: a 110° cone round its `facing` out to 2520, a 48
bubble all round, and a line of sight over real heights: the cone stays a floor-plan polygon, but only a piece whose twin top
(`TwinSpace`, interface 29: a wall 96 px, a wardrobe 78, a counter 38, a table 31) is above the viewer's **eye** breaks it; a
lower piece is looked over. The eye is the height of the posture the viewer is in (`BodyHeights.eye`, 1.64 m at 42.3 px a metre:
standing 69 px, ducked 32 px), so ducking behind a counter closes the cone behind it and standing opens it again; a car (its body 40 px, its cabin's roof 60) is looked over by a standing player and blocks a ducked one, as a counter does, while a van's cabin (roof 78) stops a standing eye too (its bonnet, 46, does not); a piece that hangs above the eye (a mirror from 46 to 80 px: its base over a ducked eye's 32) is looked under, as a doorway's lintel is, so the cone passes beneath it; a character is
looked over at any height, as it always was (a body does not hide what lies behind it from the cone). The numbers are a Character holder's (`CharacterVisionConfig`, read through
`character.sight()`, which adds `eye_height`, the eye of the posture it is in; the native suite `character/character_vision_config_suite`
holds the three numbers to the spec and equal to the NPCs' default `NpcSensesTuning`), so any character carries the same view. The cone is exact at corners: nothing behind a wall corner
or a doorway's end is in it. A wall or tall piece that is seen shows its top: the cone reaches the far face of the shapes the
ray met. It is complete however many blockers are in reach (the shape query is asked again with more room while it comes back
full, so no cap drops one). Doors (`docs/doors.md`) follow the same rule: a shut solid door blocks, a glass-panel door
(`transparent`) is seen through, an ajar door's gap is seen through, a knocked-down door does not block. The cone is rebuilt
only when its output can change: the eye moved or turned, the viewer's sight numbers changed, or where a ray can pass (the sector the viewer looks along and the bubble round it,
within the view distance) a blocker moved,
changed shape (a dent, a wall re-cut, a door's swing, fall or shattered panes) or joined or left; plus a forced rebuild every
`VisionConfig.rebuild_every` (10) physics frames, a backstop. A frame that starts nothing shows the cone the last job published.
**A blocker that moved 0.05 px or less is where it was (#194, the creep rule).** Settling bodies (a shoved bookshelf coming to rest) creep 0.0005 to 0.003 px a frame for dozens of frames, and in the 10v10 each creep restarted the job: 212 of 240 restarts in a 300-frame window, and the third restart in a row built the whole cone in one frame (76 times, 8 to 10 ms). So a blocker is "where it was" while its origin's move plus its extent's turn, measured **from the snapshot the job began on** (not from the last frame), is within `ViewWatch.STILL_PX` (0.05 px; the engine's own hit noise is 0.02): no restart, no new job. Creeps add up, so a held pose lags the job's snapshot by at most 0.05 px (the job reads the live space each slice, so that is its yardstick, not "live"), and a move of 0.05 px or more restarts and starts as before. What it gives up: the published cone is exact for the blockers *as the job holds them*, and the live world's reference cone may differ from it by a sliver (a corner's side ray, 0.0002 rad, that grazes a creeping blocker flips between hit and miss: in the 10v10 one vertex 160 px along a ray, a strip 0.1 px wide). `tests/_vision/cone_checker.gd` therefore holds the cone to the reference vertex for vertex while no blocker in reach creeps and, while one does (`PlayerView.creeping_in_reach()`: a creeper behind the viewer loosens nothing), to a difference of at most 20 px^2 of area (`SLIVER`; the worst measured is one 12.6 px^2 sliver, on about 2 % of the compares). An exact check against the held snapshot cannot be built: the job reads the live space each slice. Tests: `vision/view_watch_creep_suite` (a creep under the bound never restarts, creeps add up and restart, a move of the bound or more restarts and starts, a turn counts by the extent it swings), `vision/cone_skip_exact` and `_sliced` (the checker).

**The cone is a job (#195).** A rebuild is not one frame's work: the view starts a job from the viewer's live eye, facing and sight
and steps it `VisionSliceConfig.slice_units` (450, about 3.5 ms) of engine work in each physics tick until it is done, and only then
publishes it (`SeenArea`, the two masks' paint read the cone, the bubble and the eye together). **The published cone is
the fresh cone of the pose the job started from, in the world as it was then: the exact cone of one eye in one world state, never a
mix and never extrapolated** (the memory, V4, never holds area no eye saw). It is as old as the job is long: a job of k ticks started
in tick f publishes in tick f+k-1 and the next starts in f+k, so the cone shown is at most 2 (k - 1) frames old. **Usually that is 2 ticks, up to 2
frames; a job of 3 ticks is up to 4 frames old, and the longest of a district's grid (5 ticks) up to 8** (`vision/pose_lag_bounds` still holds a job to 6 ticks, 10 frames). In the 10v10 district's grid of eyes (`perf/cone_corner_cost`, 2026-11-19, under load: 5.35, 2 busy Godot) a job was a median 2 ticks, 10 % took more
than 3 and the most took 5 (the rays of a district job were a median 495 units, so at a slice of 450 the median job is the start tick, the corners and a first part of the rays, and one more). The bound was longer than the 2 to 4 of the cone as first
sliced (a job of 6 ticks, 10 frames, from 2026-11-12) because its corners were priced at a slice; the user chose, on 2026-11-19, to price them at what they cost in the twin space. **The corners are priced at their cost** (`cost_shape` 95 and `cost_hits` 35 a chunk, 200 for a median read, the user's 225 held by `perf/cone_corner_cost`: the region shape query and its
polygons are about 200 to 225 units of ray work, 1.4 to 1.5 ms with the machine loaded, about 1 ms quiet), so the tick that starts a job does the corners and then the first rays up to the slice (a crowded region asked again is priced for each ask, and can fill the slice with them): a start tick is about a slice, not the 6 to 7 ms of corners priced as one unit, and a job is a start tick plus its remaining rays' ticks (a house's is one or two ticks, a 10v10 district's two for most eyes). What the viewer's pose does meanwhile is not asked: **a change of
the eye or the facing alone lets the job finish on the pose it started from**, and the next job starts from the live pose. **A change
of the world between slices restarts the job from the live pose** (a blocker within reach moved by more than `ViewWatch.STILL_PX`, 0.05 px, from where the job's snapshot has it, changed shape, joined or left, a
changed sight number, the eye's height included, or cone tuning, and the frame after a job began while a blocker within reach moved,
which a query that frame may have read where it was): the readers keep the last cone published until a job completes. After
`VisionSliceConfig.restart_cap` (2) restarts in a row, since the last publish, the next restart is **built whole in that frame, unless the
world's change is slow moves only (#194, the settling job)**: no signal, no new or left blocker, no change of the sight, and
every blocker in reach within `VisionSliceConfig.settle_px` (1 px) of where the job's snapshot has it (`ViewWatch.settles`). That restart
begins a settling job, a job like any other (a slice a tick) whose blockers are "where they were" while within `settle_px` of its
snapshot instead of 0.05 px; it publishes when it ends, with `PlayerView.settled_publish()` true, and the job after it starts at once
from the world as it is (a blocker 1 px off its snapshot is past 0.05 px). So the cone a settling job shows is the world's to what a
piece moved while it was built: by up to `2 * settle_px` (2 px) at the piece for one that reverses and `settle_px` (1 px) for one that moves one way
(`ViewWatch.lag()` at the publish; the job restarts past it), a strip along the shadow edge about that wide that grows with the distance from the
eye (a bound the checker holds in area: `SETTLE_AREA` of `tests/_vision/cone_checker.gd`). It lasts while the piece moves (every cone is then a settled one, and a cone
at least every 8 frames) and the cone is exact again about two jobs after it stops. The speed limit: a piece that moves more than `settle_px` between a settling job's start and its publish leaves the bound inside the job,
and that restart is built whole: about `settle_px` per frame of the job after its start, so 0.5 px a frame for a job of 3 ticks (still a settling job, the cone off by the most it can be) and about 0.25 px a frame for the longest district job (5 ticks); 0.75 px a frame is built whole in the test's house. No frame spends more than a slice on a settling job:
a whole build cost 6.7 to 12 ms where a slice is a start tick. A move of more than `settle_px`, a signal, a joined blocker or a change of the sight at the cap are built whole, as
before, and a settling job restarted again is built whole; `settle_px` 0 builds every cap whole. `tests/_vision/cone_checker.gd` holds
the cone of a settling job to the reference cone of the world by area (`SETTLE_AREA`, either way), the cone after it (the live pose's) exactly, and every other cone as before.
The first cone of a view is built whole too, and the cone for **an eye that jumped** past `jump_px` (48) from the pose of the cone published (a
teleport, a vehicle), checked every tick: the cone shown is never more than that far behind. A lift (V9) drops a half job with the view. The old pose lag
(`rebuild_gap`, an eye 5 px or a facing 1 degree off waiting a frame) is gone: the job's length is the lag. A mover entering or leaving
the seen area (V11) shows when the next cone publishes.
Tests: `vision/pose_lag_bounds` (the pipeline: a job of 3 slices is published a cone at most 4 frames old, a job of 6 ticks one at most 10 frames old, and of a pose the viewer stood at, a pose change alone restarts nothing, an eye jump of 60 px and a blocker that moves in every frame are built whole, the seen mask draws only published cones), `vision/cone_restarts_on_world_change` (a wardrobe moved or a solid joined between two slices restarts the job and the cone published is the reference cone of the world after, not of the one the job began on or a mix; a wardrobe moved every frame is built whole after two restarts, at least every fourth frame, of the live pose), `vision/cone_settles_past_the_cap` (a wardrobe moving 0.15 px a frame: the job past the cap settles, no whole build, a cone at least every 8 frames, of the live pose, and the cone after it stops is the reference; one moving 0.5 px a frame (the limit of the test's job of 3 ticks) still settles, one moving 0.75 px, past it, or 3 px, is built whole; a change of the view distance while it creeps is built whole; the wardrobe lags the job by at most `settle_px` at a settled publish, and its cone is off the world by more than none and at most `SETTLE_AREA`),  `vision/half_job_dropped` (the viewer killed, or the view disabled, with a job in flight: the job is dropped, the seen area cleared and not written by it again, and a view enabled again builds its first cone whole), `vision/cone_follows_sight` (two rooms joined by a doorway, a wardrobe and a table, the eye turned: points over
the table and inside the cone are in the polygon; points behind the wardrobe, beyond the wall, behind the eye past 48 are not;
points within 48 behind it are), `vision/cone_exact_at_corners` (eyes near the room corners and the doorway's ends, facing along
and across the walls: no sampled point behind a corner is inside the polygon and every sampled point the eye sees is; a seen
wall's far face is in the polygon, the room beyond is not), `vision/cone_exact_with_many_blockers` (more solid shapes in reach
than any query cap: every wardrobe keeps its corner rays), `vision/cone_same_after_savings` (the live cone against the reference
cone, the plainest form of the cone, vertex for vertex, over a grid of eyes and facings in generated houses and after a door, a
shove and a freed piece move through it), `vision/fan_hide_margin_keeps_grazing_corner` (a shelf's tip a hair off a fan ray whose hit the engine
reports 0.02 px off the shelf is cast: the fan calls a corner hidden only when the two rays either side of it met one convex shape nearer
than the corner and the corner is more than a quarter pixel, at its own distance, from either ray), `vision/cone_skip_exact` and `vision/cone_skip_exact_sliced` (the same run with the job cut into 90-unit slices) (a still then a turning viewer through a dent, a shove, a
door's swing, panes shattered, a door knocked down, a piece added and freed, and the viewer's posture changing what it looks over: every cone published equals a fresh rebuild's from the pose it is of (`PlayerView.published_pose()`), vertex for vertex, the cone held between two publishes is the one before, and a view settled on the viewer's pose shows the live pose's; a still viewer starts far fewer jobs than there are frames and never goes more than
`rebuild_every` frames without starting one). `vision/cone_follows_sight` also hangs three doors in the wall the rooms share, and
the eye stands before each in turn: the point beyond a shut solid door and one beyond a shut hollow door are not in the polygon,
the point beyond a shut glass-panel door is, the solid door swung open shows the point through its gap and hides it again shut,
and a hollow door knocked down does not hide it (`objects/door_blocks` holds the rule for an NPC's sight).
`vision/cone_skip_exact` also runs a world of its own: a solid moved every frame 3750 px from the viewer (the reach is 2520)
forces no rebuild, one moved every frame in the cone forces one a frame, and, with a checker holding every frame's polygon to a
fresh rebuild's, a solid built each way a body reaches further than its origin does (a shape offset 2000 px, turned a quarter, a
polygon, a scaled body, a shape scaled and one mirrored, a shape set after the body is placed, the shapes cut anew, a body that
says `changed`) moves from outside the reach into it the frame after a rebuild (so that the backstop cannot be what rebuilds): a
rebuild in that frame, and the fresh rebuild's cone in every frame after, also when it is freed. `ViewWatch` watches the
blockers within reach, by the view distance and each solid's own extent. The native suite `vision/view_watch_suite` holds its
cost (a blocker that moves is not measured again, only one whose shapes come or go), the largest absolute scale of a shape or a
body, and a body that moves out of the reach as well as into it. The view hands the watch the world's twin space, which says when it
twins a body: the colliders sorted with no twin (a district has hundreds of rugs and mats no builder twins, 311 of 1,360 in the 10v10)
are asked again then, not on each check (that was 0.15 ms a frame, 2026-11-24, #194); a watch built with no twin space asks
each check as before. Test: `vision/view_watch_twins_suite`.

**V2. One sight rule.** Sight is geometry, one rule in General (`SightRay`, interface 11), in two forms of the same height test, and a
body's posture sets its heights (#194 D9). **The NPCs' sight** (`AgentVision`) is a 3D eye ray in the twin space: from the viewer's eye
(its posture's, `BodyHeights.eye`) to a few points on the target (head, chest and hips at the target's posture, `BodyHeights.sight_points`),
seen if any one is clear, the head tried first (the first clear point ends the ask). Walls, doors, furniture and vehicles block it where
they stand, at the height they stand: a standing NPC (eye 69 px) looks over a table (31 px) and sees a standing body close behind a sofa
(back 38 px), a ducked body (head 32 px, chest 24, hips 18) right behind that sofa is hidden from it, and a ducked NPC (eye 32 px) cannot
look over a counter (38 px) at all; a car (body 40 px, roof 60) is looked over standing and blocks ducked, the same, and a van's roof (78) stands over a standing eye and blocks it; bodies never block, so a character in the way hides nothing; a `transparent` surface (a glass-panel
door) is looked through however tall (the glass front of a shop's fridge or snack machine is a collider, not `transparent`: it blocks sight as the solid fridge did, though the stock behind it is drawn; the shelf aisle's bays are open, so a ducked eye sees through between its boards, which the old solid aisle did not allow: `docs/stacked-items.md` SI16). A body in the open is seen from anywhere its lines are clear, so a ducked one far behind cover is
seen over it (the eye looks down). The query behind it is public (`SightRay.visible_parts(viewer, target)`: the heights of the target's
points the viewer's eye sees, and `visible_centre`: the middle of them, -1 when none: what an aim at the visible part reads). **The
view** casts the same rule on the plan (`SightRay.plan_hit`): a 3D ray level at the viewer's eye height in the twin space, so a piece lower
than the eye is under it and a doorway's lintel over it: V1. A world with no twin space, and a body with no twin (a body added this frame has none until the twin space's first update), block nothing in either. Tests: `general/sight_ray_suite` (native: the plan cast over a built twin space: a wall, a
table, a piece just under and just over the eye, a body with no twin (not in the twin space: it blocks nothing), a `transparent` piece, a character, the caller's exclude list left
alone) and `general/sight_ray_eye_suite` (native: the eye ray: a wall at any height, a table over and under, the floor behind it, the
points of a body, a pane, the twins left out), `ai/perception/sight_height_by_posture` (a standing NPC sees over a table and sees a
standing body behind a sofa but not a ducked one; a ducked NPC cannot see over a counter and sees again standing),
`general/sight_visible_parts` (a ducked body shows none, one, two, three of its points as it stands further behind a counter; a standing
one in the open all three), `ai/perception/sight_follows_a_moving_target` and every `ai` vision test (`tools/run_tests.sh --domain=ai`;
`objects/door_blocks`).

**V3. Inside the cone** the world is seen as it is, lit and drawn live, characters and all, with one rule for a living character: it is
drawn only if one of its body points (head, chest, hips at its posture) is clear from the viewer's eye (`SeenArea.hides`, asked by Art's
mirror of a character the cone reaches), so a ducked enemy behind a sofa stays hidden though the cone covers the ground it stands on, and is
drawn again as it stands; a corpse, an item and a car follow the cone alone. A thing that moves and is cut by the
cone's edge is cut per pixel (the shader reads the live mask, which is feathered at its edge: V12). Tests: `vision/memory_follows_cone`
(the live window and its blur), `vision/vision_mask_3d_windowed` (a mover on the edge: some of it drawn on the lit side and none beyond the cut),
`vision/ducked_enemy_behind_sofa_not_drawn` (a standing enemy behind a sofa in the cone is drawn, a ducked one not, a ducked one in the
open is, and it is drawn again as it stands) and `vision/cone_height_by_posture` (standing, the cone passes over a counter, a car and a coffee
table and stops at a wardrobe and a van's cabin; ducked, it stops at the counter and the car and passes over the coffee table; standing again reopens it).

**V4. Outside the cone** each place is drawn **as the human last saw it**, the memory, in the picked look: greyscale (`grey`
1.0), contrast 0.9 about 0.3, brightness 0.55, tint (0.88, 0.96, 1.12), "Darkwood cool". A place never seen is **black**. The edge
is feathered over **16** screen px, laid inside the edge (a disc of 32 shifted copies of the polygon, averaged). The memory starts
empty when the match starts, is never cleared after, and only gains: it holds where the viewer has been seen to look, as the world
stands now (V12), not a picture of it. It is `seen_scale` (0.5) texels a px over the floors' bounds, at most `seen_max_side`
(2048) texels a side (so within Godot's 16 384 px texture limit), and drops below that scale to fit. Tests:
`vision/memory_follows_cone` (the memory covers the floors' bounds at its scale and maps them edge to edge, starts empty, is
cleared once and never again; both masks draw the cone and the bubble; the live mask's blur stays within the feather and reaches
it; the shaders are told where each lies), `vision/memory_fits_texture_limit` (a 20 000 px arena),
`vision/vision_mask_3d_windowed` (the look in pixels: floor never seen black, remembered floor dimmer, not black and nearly grey).
A headless run has no pixels: those tests read what the parts are told, and the look is read in the window.

**V5. Never remembered while moving:** living characters (allied and hostile) and what they hold, bullets and tracers, grenades
in flight, hit particles, flying debris, blood spray, an explosion's look, a shot's or a burst's flash light, and a vehicle while
it moves. A body that moves sits on `ViewLayers.MOVING`, and Art's `MeshCarrier` and `MeshFollower` hides it while no part of a disc round it is in
the cone (V12); what is not a body (a bullet, a burst's bits, a blast's parts, a casing in the air) is marked moving in its mesh
(`MeshNodes.moving`) and cut by the shader outside the cone. Tests: `vision/moving_never_remembered` (the living puppets, a
bullet and a grenade in flight are on `MOVING`; furniture, a wall and the blood already settled (a splatter) are on `WORLD`:
the premise that the read tells them apart), `art/moving_mark` (the mark on a mirrored mover, the bullet batch, a burst's bits and
sparks, a blast's parts and a part added later), `art/mirror_hides_unseen_movers` (a mover outside the cone is hidden, shown in
it), `projectile/casing_hidden_out_of_view`.

**V6. Remembered once at rest:** a dead body once its ragdoll sleeps, a dropped item, a spent casing, a grenade lying still, a
parked vehicle, and the house and street (floors, walls, doors, furniture where last seen, settled blood, scorch, debris chips).
A door is always `WORLD`: it is remembered where it stands at whatever angle, mid-swing included. Once at rest a thing is shown
only after the cone has reached it, and then it stays shown where it lies, dimmed and grey (V12); moved again, it is moving again
(hidden outside the cone, and to be reached again where it comes to rest). A body, a vehicle and a grenade can be moved again: a
dropped item and a casing at rest stay at rest for good (nothing shoves them: each stops its physics for good), so the "moved
again" cases are the corpse a blast wakes, a parked car driven or shoved, and a grenade whose piece is pushed or blasted out from
under it (it falls, on `MOVING` until it rests again; `SmallFlight.unsupported`, `docs/grenades.md` G8).
Tests: `vision/at_rest_remembered` (a dead body on `MOVING` until its ragdoll sleeps, on `WORLD` after and on `MOVING` again from
the frame a blast wakes it; a dropped gun, a casing and a frag lying still on `WORLD`, in flight on `MOVING`; in a world of its
own a wooden door swung open and shut is on `WORLD` in every frame of its swing), `vision/vehicle_rest_remembered` (a car driven,
then parked), `art/mirror_hides_unseen_movers` (at rest and never seen: hidden; once reached: stays shown; moved out of view and
resting there: hidden until reached again), `projectile/casing_hidden_out_of_view`,
`projectile/frag_falls_when_its_support_is_pushed_away` (the fall).

**V7. Debug overlays and markers are drawn over the view, in colour:** the AI debug overlays (an NPC's own too, out of view),
the navigation and leader overlays, the contact, stack and order markers. Each is an overlay (`ViewLayers.overlay`), which
`GroundLayer` lies flat on the ground over the 3D picture and under the HUD, in its own colours and where its owner is, at any
camera turn, never dimmed or remembered by the masks (they are not part of the 3D scene the shaders read). Tests:
`vision/overlays_over_view` (an NPC with every overlay on, the navigation holes, the leaders' crowns and the stack, order and
contact markers: each under the match's ground layer, visible), `general/ground_overlays_3d` (Main whole: one
shared layer following the camera's ground-to-screen transform).

**V8. Whose view.** In Main the view is built in a played match (Start) for the human only; Watch and Endless (no human) draw
everything. In a test world any one character can be the viewer, an NPC included (`TestSetup.view(actor_id)`): the screen then
shows what that NPC sees, by the same rules, so a test (the perf guard among them) runs the view's real cost. Viewing an NPC
changes nothing in its AI. Tests: `vision/view_only_for_the_human` (a declared match with a human has one view, of the human),
`vision/no_view_without_a_human`, `vision/main_view_for_start_only` (Main run whole: Start builds one view, Watch none),
`vision/view_on_npc` (one view, its polygon from the NPC's eye and facing as it turns; the same scripted run with and without the
view gives the same decisions, places and arrival tick).

**V9. The viewer's death lifts the view** (the human's, or a viewed NPC's in a test): everything is drawn again at once, live, for
the rest of the match. So does the viewer leaving the tree without dying; a viewer already dead gets no view. Tests:
`vision/death_lifts_view` (the node, its viewports and the masks are gone within a frame and none comes back; and
nothing is hidden after: `SeenArea` holds no area, so a disc and a box far from where the viewer stood reach it again, which they
did not while the view stood, for the human's death, a viewed NPC's, and a viewer freed or removed).

**V10. The switch.** `VisionConfig.enabled` (default on) gates the view in Main's match; the test world's `vision.enabled`
switch is off unless a test asks, so existing tests and sandboxes look as they do; with it on, the world views its `player`
actor, or the actor `TestSetup.view` names. Tests: `vision/switch_off` (no `PlayerView` and no `SubViewport` under the world, no mask on, and `SeenArea` holds no area: a far disc and
box reach it, so no repaint is skipped).

**V11. The seen area, and the unseen runs on.** The seen area is General's `SeenArea`: Vision writes the cone's polygons each
time a cone is published (a job done), bumps its `version()` and clears them on a lift; a disc (`reaches`) asks it, and `active()` says whether any view stands. What reads it is what hides by the view: Art's `MeshCarrier` and `MeshFollower`
(a mover is hidden while no part of a disc round it reaches the area, V12) and the shot layer (a casing in the air or lying
unseen). The one test of a point inside a polygon is `SeenArea.contains`, an even-odd rule (the view's `sees` asks it too),
since the engine's `Geometry2D.is_point_in_polygon` said inside for points well outside a cone with many collinear corners.
With no view (Watch, Endless, the switch off, the view lifted) the area is empty and nothing is hidden. The view never touches
what the world does: a character wholly outside the cone and bubble keeps its pose, aim, hands, footsteps and ragdoll running
(gameplay reads those, never what is drawn), so a hit lands on it as it would unviewed. Tests: `vision/unseen_keeps_running` (the
same walker, out of the cone behind the viewer, shot three times in two worlds built from one declaration, one viewed and one
not: the same hits at the same places, for the same damage, on shoulders turned the same way), `general/seen_area_suite`
(native: the disc and box tests over polygons laid out by hand, an L-shaped polygon, no area set),
`vision/view_sees_suite` (native: `sees` at a cone the engine's point-in-polygon gets wrong, the bubble, no polygon),
`vision/death_lifts_view` (the area cleared on a lift), `art/mirror_hides_unseen_movers` (hidden outside, shown in the cone).

**V12. The two masks.** The view is not a picture laid over the 3D scene: it is
two textures the 3D scene's shaders read by a surface's own ground position (`xz`), and the world is lit and drawn as it stands. The
cone and the bubble, V1's polygon, are drawn into a **live mask**, a square window of the world about the camera
(`VisionGroundConfig.live_side` texels whatever the zoom, so a texel is a few world px, more of them zoomed out; the edge feathered
`feather` screen px as V4's is, laid inside the edge) and into a **seen mask** over the floors' bounds (`seen_scale`, at most
`seen_max_side` texels a side, never cleared) that only gains: where the player has seen. The toon shaders (`toon`, `toon_tex`, the
kit's decal) and the outline pass read them (`ToonMask`'s global uniforms, `toon_vision.gdshaderinc`), so every floor, wall, piece of
furniture and character is shaded by them with no per-mesh work: in the cone it is lit as it is; where it is only remembered it is
**the current static world** (its doors, its furniture where they stand now, the light now: not a picture from when it was seen)
greyed (`grey`), with `contrast` about `pivot`, tinted (`tint`) and keeping `brightness` of its light, as V4's look; where nothing was
seen it is black (`unseen_brightness` 0), its lines too (the outline's floor is as lit as the ground, so a wall's or a piece's line is
no clue to the unseen house).

A thing that **moves** is drawn only inside the cone, as V5: its mesh is hidden when no part of a disc round it
(`MirrorVisionConfig.moving_reach` 60, a vehicle's `vehicle_reach` 130) is in the cone (`MeshCarrier`, `MeshFollower`; the thing's sim node on
`ViewLayers.MOVING`: V5's list), and a thing the cone cuts is cut pixel by pixel by the shader, its shadow with it
(`MeshNodes.moving`, which marks every part under a node and any part added later; bullets, a burst's bits and a blast are marked so,
and a casing in the air is drawn no size outside the cone). What is **dynamic but at rest** (V6: a corpse once its ragdoll sleeps, a
character at rest, a dropped item, a casing lying, a parked car: `MirrorVisionConfig.seen_first`) shows only once the player has seen
it: it is hidden until the cone first reaches it, and from then on it stays drawn where it is, dimmed and grey (a seen flag, kept across a
rebuild of its mesh; a casing's is its own). A thing that then moves outside the cone loses the flag: a character seen alive who walks
out of view and dies there, a car that drives off and parks, a corpse or item blown out of view, must be reached again where it comes
to rest. The **static world** (floors, walls, furniture, doors) is remembered wherever the ground was seen,
without the first sight of each piece. Known limits: settled blood, decals and scorch are static in the 3D render, so they show in the
remembered ground from the first sight of that ground, not of the mark; a debris chip is one part of a batch and cannot be told moving
from lying, so one in the air is drawn outside the cone like one at rest.

Drawing is **on request**: each mask is drawn when a cone is published and the live one again when the window is laid again (the camera
drifts out of it, or the zoom steps); a still viewer in a still world draws nothing (the backstop republishes an unchanged cone, which
draws nothing), and the world is never photographed: the view's only viewports are the live window and the seen mask, which
draw once on request. The masks are switched on `settle_frames` (2) frames after the first cone is drawn and cleared when the view
lifts (V9). The debug overlays (V7) lie flat on the ground, over the picture.

Tests: `vision/ground_view_3d` (the masks switch on after the first cone and clear on a lift; a still view draws nothing across the
backstop's rebuilds, a walk draws both; the window follows a camera that leaves it; the view's only viewports are the live window and the memory and neither renders every
frame),
`general/view_follows_paused_camera_3d`, `art/mirror_hides_unseen_movers` (a mover outside the cone is
hidden, shown in it; a character, a corpse and a dropped rifle never seen are hidden at rest and stay shown once the cone has reached
them; one that moved out of view and rests there (a car parked, a character that walked off and died) is hidden until reached again; furniture never hidden), `art/moving_mark` (the mark on a mirrored mover, the bullet batch, a burst's bits and sparks, a blast's
parts and a part added later), `projectile/casing_hidden_out_of_view` (a casing in the air or lying unseen is no size; whole once
seen), and, windowed (shaders compile and pixels draw only there), `vision/vision_mask_3d_windowed` (at the four camera yaws and at 0.5x
and 3x: the floor in the cone lit and a character there drawn; floor behind never seen black with no line of the unseen house; after a
look about it remembered, dimmer, nearly grey, with the character standing on it not drawn; a mover on the cone's edge drawn on the lit
side and none beyond the cut; a moving box outside the cone casts no shadow on the lit floor, and the same box in the cone does),
`art/toon_vision_hook_windowed` (a mask dims the toon and the decal).

**Sound.** There is no on-screen hint for gunfire or footsteps heard out of view; sound stays as it is (`docs/hearing.md` is the
AI's side).

An emptied shelf (`docs/stacked-items.md` SI13) is hollow: a viewer in front looks into a compartment between its boards and sees the back, as a shelf's front is open; its back and its sides stop sight at every height. Test: `objects/hollow_shelf_compartments_are_open`.

## Out of scope

Any view in Main's Watch and Endless (no spectator view, no side views), a view for NPCs in Main's matches (a test world can view
one, V8), more than one viewer at once, an on-screen hint for sounds, the memory fading with time, capturing what is off screen,
a view of the dead human.

## Technique

The *live mask* is a viewport over a window of the world about the camera, the *seen mask* a world-space viewport over the floors'
bounds that is cleared once; each cone published is drawn into both as a triangle fan (the live one once per tap of the feather,
32 shifted copies added up), and the toon shaders read them by a surface's ground position (V12). The two viewports are siblings
(a viewport nested in another makes the engine log an error) and draw on request, never every frame.

The **cone polygon** is a fan from the eye over ray ends sorted by angle. The rays are an even fan (`cone_rays` 64 across the cone,
`bubble_rays` 48 round the eye) plus, exactly at corners, three for each corner of each blocking shape the eye can see (the
corner's own angle and `corner_offset` either side), so a chord of the fan never cuts across the shadow behind a corner. The shapes
come from a physics shape query on the solid layer (the hull of the cone's sector, its arc cut into 16 chords, and the bubble, grown 2 px: a shape that touches neither is in no ray, and has no corner within the half pixel at which two corners are one of a corner that is), never a walk of the scene tree. A corner whose line of sight needs no ray: the two rays of the even fan either side of it met the same convex shape, both nearer than the corner, so the line crosses the chord between those hits and meets the shape there (`vision/cone_hidden_corners_not_cast`: the rays cast to corners are `PlayerView.corner_rays()`); the fan's rays are cast once, for the corners and the polygon both. A corner beyond the view distance adds no ray (`vision/cone_beyond_reach_exact`), so a shape that only touches the query's hull past the reach, or the disc outside the sector, changes nothing. Every ray is
cast leaving out the low pieces in reach, so it meets its first blocker in one cast; where it ends on a blocker it runs on to where
it leaves the solid (the farthest exit over the blocking shapes holding a point 0.1 px along it, at most `far_depth` 120; `far_bleed`, 14, in
when it leaves through no edge). Two choices make a rebuild independent of which of several overlapping shapes the
engine names: the far-face pick reads the shapes that hold the point and not the shape the ray hit, and two corners less than half
a pixel apart are one, the lesser (x, then y) standing for them. Without both, a fresh rebuild was not deterministic.

**What triggers a rebuild** (`ViewWatch`): the eye, the facing, the sight numbers and the cone's `VisionConfig` numbers; the
transform or collision layer of any blocker where a ray can pass (within the view distance of the eye and in the cone's sector or the bubble, each grown by the blocker's own extent, kept from the time its
shapes came or went, and 2 px: `vision/cone_ignores_solids_outside_its_sector`), each frame, and once more the frame after a rebuild made while one moved (a query in the frame a body moved
can read it where it was); by signal a blocker's shapes coming or going, its leaving the tree, a door's `changed`; a collider that
entered the tree; the viewer's eye height (it ducks or stands: every collider is sorted again by it, the lows and the blockers); and
`rebuild_every` frames since the last. A low piece is looked over, so it is in no ray and is not watched; a character is looked over at any
height, so it is never watched and costs no rebuild however it moves. A piece's top (its twin's, `TwinShapes.top_of`, kept on the twin)
and a door's `transparent` are read once and kept (a piece with no twin yet blocks like a wall and is asked again, a body twins a frame
after it joins): a piece's top is set once from its mesh's real size (`PieceHeights`), a door's is always 84 and its
`transparent` is fixed at spawn (a shatter changes only the look's `broken`). **`ViewWatch` does not watch either**, though the rebuild
rule as first written lists a changed top or `transparent` among its triggers: Objects promises that neither changes in play
(interface 03). Should one ever change (a tipped piece, #194 D14), the cone is stale until the next rebuild, at most `rebuild_every` (10)
frames later, the backstop that bounds it; a feature that makes one change must tell `ViewShapes` and `ViewWatch`.

## Tunables

`VisionConfig`: `enabled` true; the look `grey` 1.0, `contrast` 0.9, `pivot` 0.3, `brightness` 0.55, `tint` (0.88, 0.96, 1.12);
`feather` 16; `cone_rays` 64, `bubble_rays` 48, `corner_offset` 0.0002 rad; `far_depth` 120, `far_bleed` 14;
`rebuild_every` 10. `VisionGroundConfig` (the masks, V12): `live_side` 768, `window_margin` 1.25, `window_slack` 1.8,
`seen_scale` 0.5, `seen_max_side` 2048, `unseen_brightness` 0, `settle_frames` 2. `VisionSliceConfig`: `slice_units` 450 (about 3.5 ms of engine work a physics tick; a unit is a ray cast, a region shape
query or a far-face probe, priced `cost_cast` 1, `cost_shape` 95 and `cost_probe` 1, and the corners' polygons and dedupe `cost_hits` 35 a chunk of `hit_chunk` 32 hits: the corners are priced at their cost in the twin space, **200 units as the code prices them** (`cost_shape` 95 for the query + 3 chunks of `cost_hits` 35, the median read of a district), **225 the price `perf/cone_corner_cost` pins them at** (the user's, 2026-11-19: it holds the measured cost within a 15 % band of it, and a read measures about 213). The split of the 200 between query and chunks is a choice that is not the honest cost (query 60, chunk 50): the chunk's 35 holds a crowded region's cone at the 4 frames of `vision/view_on_npc` (37 gives 5, 55 gives 6), so a crowded region (7 chunks) costs about 0.5 ms over its nominal slice), `restart_cap` 2, `jump_px` 48, `settle_px` 1. `CharacterVisionConfig`: `fov_degrees` 110, `view_distance` 2520, `awareness_radius` 48 (what the eye looks over is `BodyHeights.eye` of its
posture, 69 px standing and 32 px ducked, no number of its own). The reach of a mover hidden by the view is `MirrorVisionConfig`'s (`moving_reach` 60, `vehicle_reach` 130). The look and the 16 px edge were picked by eye,
against a flat 45 % grey (too dark and flat), a full-brightness grey (too close to the live world), a hard edge (a harsh line) and
a 40 px feather (it smears the cone).
Tests: `vision/pose_lag_bounds` (`slice_units`, `jump_px`), `vision/cone_restarts_on_world_change` (`restart_cap`), `vision/cone_settles_past_the_cap` (`settle_px`), `vision/cone_skip_exact` (`rebuild_every`).

## Measured cost

The corners are two stages (`ViewCone`: the region query, then its hits folded 32 at a time), so a slice can end between them (`cost_shape` 95 a query, `cost_hits` 35 a chunk: a median 3 chunks, 200 units, near the sum a read measures; the polygon is the same vertex for vertex, `vision/cone_sliced_matches_whole`, `vision/cone_same_after_savings`). A shape's dedupe cells (half-pixel cell to corner, the lesser of two in a cell) are made once with its polygon and kept with it, and the fold merges them into the job's one dictionary a shape in one step (only a shape that shares a cell with one met before is looked at corner by corner); the distinct corners are that dictionary's values, in the order first met. `ViewWatch.built` skips a blocker that stands where it did.
The prices are `VisionSliceConfig`'s (Tunables, above): the corners' 225 is held by `perf/cone_corner_cost` for the whole, the query and the
chunks each within 2x of what they measure.
Tests: `vision/cone_corners_priced` (the query and chunks priced, the rays after what is left of the slice), `vision/cone_slice_units`, `perf/cone_corner_cost`.

A collider's top is read once and kept (`ViewWatch`; it does not change in play), so a viewer that ducks or rises moves bodies between the
blockers and the looked-over by it and measures only those that start to block; no collider is sorted again from nothing.
Test: `vision/cone_height_by_posture` (the cone ducked and standing; the kept tops are pinned by the suite `tests/vision/view_watch_posture_suite.gd`).

The live cone is held vertex for vertex to `tests/_vision/reference_view_cone.gd`, the plainest form of V1's rule: it keeps nothing between
builds and casts every ray plainly. It is the yardstick: change it only with this spec.
Test: `vision/cone_same_after_savings`.

`perf/match_npc_vision_relative` holds the view's cost over the same match unviewed: at most **3.2 ms** a frame with the viewer parked (set
from eight quiet runs on a house, the highest plus 25 %, the user's choice; kept, not loosened, on the district), at most **3.5 ms** with a
viewer that walks and turns (`MOVING_BUDGET_MS`: 1.7x the median of six quiet runs of the sliced cone, not `perf.md`'s 4x rule, which a
per-frame cost would never trip), and the live cone at most **0.75** of the reference cone's cost from the same eye. `perf/match_npc_vision`
is the absolute guard on the same match. Headless runs see the CPU side only; the GPU side is measured by hand in a window.
Tests: `perf/match_npc_vision_relative`, `perf/match_npc_vision`.

The dated measurements, the choices they led to and the windowed play-through are `docs/adr/0017-district-perf-measurement-history.md`.
