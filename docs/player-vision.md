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
(`TwinSpace`, interface 29: a wall 96 px, a wardrobe 90 or more, a counter 38, a table 31) is above the viewer's **eye** breaks it; a
lower piece is looked over. The eye is the height of the posture the viewer is in (`BodyHeights.eye`, 1.64 m at 42.3 px a metre:
standing 69 px, ducked 32 px), so ducking behind a counter closes the cone behind it and standing opens it again; a car (its belt, 47 px; a van's 56) is looked over by a standing player and blocks a ducked one, as a counter does; a piece that hangs above the eye (a mirror from 46 to 80 px: its base over a ducked eye's 32) is looked under, as a doorway's lintel is, so the cone passes beneath it; a character is
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
**The cone is a job (#195).** A rebuild is not one frame's work: the view starts a job from the viewer's live eye, facing and sight
and steps it `VisionSliceConfig.slice_units` (450, about 3.5 ms) of engine work in each physics tick until it is done, and only then
publishes it (`SeenArea`, the two masks' paint read the cone, the bubble and the eye together). **The published cone is
the fresh cone of the pose the job started from, in the world as it was then: the exact cone of one eye in one world state, never a
mix and never extrapolated** (the memory, V4, never holds area no eye saw). It is as old as the job is long: a job of k ticks started
in tick f publishes in tick f+k-1 and the next starts in f+k, so the cone shown is at most 2 (k - 1) frames old. **Usually that is 2 ticks, up to 2
frames; a job of 3 ticks is up to 4 frames old, and the longest of a district's grid (5 ticks) up to 8** (`vision/pose_lag_bounds` still holds a job to 6 ticks, 10 frames). In the 10v10 district's grid of eyes (`perf/cone_corner_cost`, 2026-11-19, under load: 5.35, 2 busy Godot) a job was a median 2 ticks, 10 % took more
than 3 and the most took 5 (the rays of a district job were a median 495 units, so at a slice of 450 the median job is the start tick, the corners and a first part of the rays, and one more). The bound was longer than the 2 to 4 of the cone as first
sliced (a job of 6 ticks, 10 frames, from 2026-11-12) because its corners were priced at a slice; the user chose, on 2026-11-19, to price them at what they cost in the twin space. **The corners are priced at their cost** (`cost_shape` 225: the region shape query and its
polygons are about 200 to 225 units of ray work, 1.4 to 1.5 ms with the machine loaded, about 1 ms quiet), so the tick that starts a job does the corners and then the first rays up to the slice (a crowded region asked again is priced for each ask, and can fill the slice with them): a start tick is about a slice, not the 6 to 7 ms of corners priced as one unit, and a job is a start tick plus its remaining rays' ticks (a house's is one or two ticks, a 10v10 district's two for most eyes). What the viewer's pose does meanwhile is not asked: **a change of
the eye or the facing alone lets the job finish on the pose it started from**, and the next job starts from the live pose. **A change
of the world between slices restarts the job from the live pose** (a blocker within reach moved, changed shape, joined or left, a
changed sight number, the eye's height included, or cone tuning, and the frame after a job began while a blocker within reach moved,
which a query that frame may have read where it was): the readers keep the last cone published until a job completes. After
`VisionSliceConfig.restart_cap` (2) restarts in a row, since the last publish, the next restart is built whole in that frame; so is the
first cone of a view, and the cone for **an eye that jumped** past `jump_px` (48) from the pose of the cone published (a
teleport, a vehicle), checked every tick: the cone shown is never more than that far behind. A lift (V9) drops a half job with the view. The old pose lag
(`rebuild_gap`, an eye 5 px or a facing 1 degree off waiting a frame) is gone: the job's length is the lag. A mover entering or leaving
the seen area (V11) shows when the next cone publishes.
Tests: `vision/pose_lag_bounds` (the pipeline: a job of 3 slices is published a cone at most 4 frames old, a job of 6 ticks one at most 10 frames old, and of a pose the viewer stood at, a pose change alone restarts nothing, an eye jump of 60 px and a blocker that moves in every frame are built whole, the seen mask draws only published cones), `vision/cone_restarts_on_world_change` (a wardrobe moved or a solid joined between two slices restarts the job and the cone published is the reference cone of the world after, not of the one the job began on or a mix; a wardrobe moved every frame is built whole after two restarts, at least every fourth frame, of the live pose),  `vision/half_job_dropped` (the viewer killed, or the view disabled, with a job in flight: the job is dropped, the seen area cleared and not written by it again, and a view enabled again builds its first cone whole), `vision/cone_follows_sight` (two rooms joined by a doorway, a wardrobe and a table, the eye turned: points over
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
body, and a body that moves out of the reach as well as into it.

**V2. One sight rule.** Sight is geometry, one rule in General (`SightRay`, interface 11), in two forms of the same height test, and a
body's posture sets its heights (#194 D9). **The NPCs' sight** (`AgentVision`) is a 3D eye ray in the twin space: from the viewer's eye
(its posture's, `BodyHeights.eye`) to a few points on the target (head, chest and hips at the target's posture, `BodyHeights.sight_points`),
seen if any one is clear, the head tried first (the first clear point ends the ask). Walls, doors, furniture and vehicles block it where
they stand, at the height they stand: a standing NPC (eye 69 px) looks over a table (31 px) and sees a standing body close behind a sofa
(back 38 px), a ducked body (head 32 px, chest 24, hips 18) right behind that sofa is hidden from it, and a ducked NPC (eye 32 px) cannot
look over a counter (38 px) at all; a car (47 px) is looked over standing and blocks ducked, the same; bodies never block, so a character in the way hides nothing; a `transparent` surface (a glass-panel
door) is looked through however tall. A body in the open is seen from anywhere its lines are clear, so a ducked one far behind cover is
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
table and stops at a wardrobe; ducked, it stops at the counter and the car and passes over the coffee table; standing again reopens it).

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
(hidden outside the cone, and to be reached again where it comes to rest). Only a body and a vehicle can be moved again: a dropped item, a
casing and a grenade at rest stay at rest for good (nothing shoves them: a dropped item stops its physics for good, a casing's
flight ends once, a resting grenade does nothing but wait for its fuse), so the "moved again" case is the corpse a blast wakes.
Tests: `vision/at_rest_remembered` (a dead body on `MOVING` until its ragdoll sleeps, on `WORLD` after and on `MOVING` again from
the frame a blast wakes it; a dropped gun, a casing and a frag lying still on `WORLD`, in flight on `MOVING`; in a world of its
own a wooden door swung open and shut is on `WORLD` in every frame of its swing), `vision/vehicle_rest_remembered` (a car driven,
then parked), `art/mirror_hides_unseen_movers` (at rest and never seen: hidden; once reached: stays shown; moved out of view and
resting there: hidden until reached again), `projectile/casing_hidden_out_of_view`.

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
not: the same hits at the same places, for the same damage, on shoulders turned the same way), `general/seen_area_suite` and
`general/seen_area_rect_suite` (native: the disc and box tests over polygons laid out by hand, an L-shaped polygon, no area set),
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
query or a far-face probe, priced `cost_cast` 1, `cost_shape` 225 and `cost_probe` 1: the corners are priced at their cost in the twin space, about 200 to 225 units), `restart_cap` 2, `jump_px` 48. `CharacterVisionConfig`: `fov_degrees` 110, `view_distance` 2520, `awareness_radius` 48 (what the eye looks over is `BodyHeights.eye` of its
posture, 69 px standing and 32 px ducked, no number of its own). The reach of a mover hidden by the view is `MirrorVisionConfig`'s (`moving_reach` 60, `vehicle_reach` 130). The look and the 16 px edge were picked by eye,
against a flat 45 % grey (too dark and flat), a full-brightness grey (too close to the live world), a hard edge (a harsh line) and
a 40 px feather (it smears the cone).
Tests: `vision/pose_lag_bounds` (`slice_units`, `jump_px`), `vision/cone_restarts_on_world_change` (`restart_cap`), `vision/cone_skip_exact` (`rebuild_every`).

## Measured cost

**2026-11-19, the corners re-priced for the twin space (#194 del2d; the user chose A, to price them at what they cost: `cost_shape` 225, not a slice).** `perf/cone_corner_cost` (the 10v10 district, 168 reads, load 5.35, 2 busy Godot, so the times are inflated and the ratio is what is read): the corners took **1,428 µs** against **7.02 µs** a unit of the rest of the job, so **198 units** (p25 104, p75 304; 203 on an earlier run at load 13; the 2D query had been 372 to 374), `cost_shape` 450 would have been 2.3 times that, outside the test's 2x, and 225 is within it. A job at the default slice is a median **2 ticks (max 5; 10 % over 3)** (3, 6 and 26 % before, below), so a cone shown is up to 2 times (ticks - 1) frames old: usually up to 2, at most 8 in the grid. The tick figures were measured loaded and not on a quiet machine: perf3d re-measures them (`--quiet`). `perf_ab.sh` of the twin-space cone, 29e423bc against 0fa52306 (before this re-pricing), 4 rounds: `perf/match_npc_vision` avg -0.5 %, the 10v10 guard -2.1 %, 5v5 -0.2 %, grenade -1.1 %; not re-run for the price (it moves when a rebuild's rays are cast, not how many).

**2026-11-12, the corners priced at a slice (#195, cone-start; superseded by the re-pricing above; `--quiet` runs, none marked loaded, load 4.7 to 7.5, 0 busy Godot).**
`perf/cone_corner_cost` (the 10v10 district, 168 reads: a grid of eyes and facings, each the median of 5): the corners (`begin` and the first
step: the region shape query, its polygons, the dedupe) took **1,982 and 1,937 µs** against **5.51 and 5.35 µs** a unit of the rest of the job
(rays, far-face probes, visibility casts), so **372 to 374 units** (p25 168, p75 627 by eye), where `cost_shape` had been 1. It is 450 now, a
slice, so the tick that starts a job holds the corners (about 2 ms) and no rays, not the corners plus 449 units (about 6 to 7 ms). The
cost is a tick more a job: at the default slice a district job was a median 2 ticks (max 5; 11 % over 3) and is a median **3 (max 6; 26 % over
3)**; the cone shown is 2 times (ticks - 1) frames old at most (V1 has the figures). `perf_ab.sh` same-fight, base `5343aa38`,
tip `dc3fa0dc`, 4 rounds, the fight unchanged (the cone steers no NPC): `perf/match_npc_vision` avg 16.94 to 16.29 ms (-0.65), p95 28.83 to
28.52, max 43.52 to 39.19 (-4.33); the three guards with no view moved by noise (avg +0.03, +0.06, +0.34). `perf/match_npc_vision_relative`, one run:
parked -0.13 ms, ratio 0.08; moving 1.34 ms (2.0 to 2.1 before), ratio 0.19 (0.25 to 0.26 before).
Tests: `perf/cone_corner_cost`, `vision/cone_corners_priced`, `perf/match_npc_vision`, `perf/match_npc_vision_relative`.

**2026-11-12, the cone as a sliced job (#195; `--quiet` runs, none marked loaded, load 3.9 to 5.9, 0 to 2 busy Godot).** The same fight
at the commit before the pipeline (`d3f40a8f`) and at it. `perf/match_npc_vision_relative`, three runs before and six after: the moving view's cost over
the unviewed match **4.49, 4.67 and 4.36 ms before, 2.05, 2.00, 2.00, 1.94, 2.04 and 2.14 after (six runs)** (the job is one slice, about 3.5 ms, a frame, where the
whole rebuild fell in every moving frame), its cone 0.44 to 0.45 of the reference cone's before and 0.25 to 0.26 after; the parked view
-0.14, -0.14 and -0.08 ms before, -0.17, -0.32, -0.23, -0.07, -0.32 and -0.09 after (no change: it rebuilds for its backstop only). `MOVING_BUDGET_MS` is
3.5 ms, 1.7 times the median of six runs of the sliced cone (2.05, 2.00, 2.00, 1.94, 2.04, 2.14 ms) and below the 4.36 to 4.67 of the cone before. `perf_ab.sh` in same-fight mode (`--ids=perf/match_npc_vision`, 3 rounds, the fight is unchanged since
the view steers no NPC): the absolute guard's median avg frame 19.12 ms before and 17.75 after (-1.37 ms, -7.2 %), p95 31.70 and 29.17,
max 47.44 and 42.37. (That guard's gain is smaller than the relative guard's: what share of its frame the view's cone is was not separated.) The age of the cone shown is V1's.
Tests: `perf/match_npc_vision_relative`, `perf/match_npc_vision`.

**2026-11-07, the pose lag and the fan table (not `--quiet`: load 10 to 12, 29 other Godot).** `perf/match_npc_vision_relative` with the parked
viewer moved to the district's outer corner facing away from the fight (a viewer in the centre house's largest room rebuilt on 28 to 100 %
of the frames, shoved and dented by the fight): the parked view read -0.82 and -0.64 ms against 3.2, rebuilding only for its backstop; the
moving rounds, whose turning aim (6 degrees a frame) is past the lag's bounds and so still rebuild every frame, read 6.74 and 5.02 ms
(11.9 and 10.9 on 2026-11-07 before). `MOVING_BUDGET_MS` is 8.5, about 1.4x of their mean.
Test: `perf/match_npc_vision_relative`.

The perf tests run headless and see only the CPU side, so the GPU side was measured by hand, windowed, as `docs/lighting.md`
"Measured cost" does. **Each figure below says where it comes from.** *Recorded* means a commit's test header or message holds it
(the commit is named). *Not reproduced* means it comes from the ticket's own measurements and its slices' notes, was first
written down in this document (commit 6ecb4659) and has been re-run by no one since: take it as the order of magnitude it
gave, not as a number to hold the code to.

**When the perf figures were measured.** Every perf figure below but the last two bullets (the district, 2026-11-02) was taken before commit 6bd7cc63 (a blood pool's repaint
decided on the frame's view, by its box), and **no perf test was run after it or after the later fixes of the review, until the district run of 2026-11-02 (the bullet below)**. 6bd7cc63
does not touch the cone, the change check or the ratio the second guard reads, so the cone figures and the ratio stand. It does
touch the frame the first guard reads: a pool then asked `SeenArea.reaches_rect` (a box, since removed, a little cheaper to refuse than the
circle) and draws in `_process`, not `_physics_process`; that moves the view's cost by about the pool skip's own size (0.13 to
0.5 ms, below) or less, which is inside the spread between runs, but it was not measured. Two later changes to the change check
are unmeasured too: `ViewWatch` no longer rebuilds for a blocker that is moving outside the eye's reach (the cone test
`vision/cone_skip_exact` counts it) and no longer measures a moving blocker's shapes anew each frame (it keeps each blocker's
extent, and compares the key field by field without building an Array), which can only cost less; and after a rebuild made while
a blocker within reach moved it rebuilds once more the next frame (a query in the frame a body moved can read it where it was),
which costs one rebuild a move that ends within reach.

- **Before the savings, the view on an NPC in a 10v10 (not reproduced).** The ticket measured about +7.4 ms a frame windowed,
  "4 to 5 ms of it the cone's CPU, about 3 ms the second world render (the capture) and about 2 ms GPU". Those three parts
  sum to 9 to 10 ms, not 7.4: they are separate estimates from separate measurements, so read them as the shape of the cost
  (the cone, then the capture, then the GPU) and not as a breakdown of the 7.4.
- **A measurement of the same match before slices 13 and 14 (not reproduced)** on a shared, loaded machine (load average 1.2 to 4.0;
  Vulkan, 1152×648, `--fixed-fps 60`, vsync off): the median frame was 18.78 ms headless and 29.95 ms windowed, the cone's rebuild
  4.86 ms headless and 3.81 ms windowed, the characters' visual update 3.78 and 7.00 ms, blood 1.69 and 1.51 ms (0.73 and 0.50 ms
  of it pools wholly outside the cone). The cone's cost depends on where the viewer stands (2.6 to 6.0 ms between runs).
- **Slice 11, the cone's own caches (not reproduced):** the ticket put the view's cost at 5.68 ms before and 3.65 ms after, and the
  cone's headless bench down 45 %. Both sit inside the 2.92 to 5.46 ms the ten quiet runs below spread over, so the pair is not
  evidence of a saving by itself; the saving the code makes is held by `vision/cone_same_after_savings` (the same polygon) and
  the ratio below.
- **Ten quiet runs before the savings (recorded, commit 46b929e4, and the header of
  `perf/match_npc_vision_relative`):** the view's cost over the unviewed match was 2.92 to 5.46 ms, median 4.36.
- **After slices 13 and 14** (unseen characters not repainted; the cone rebuilt only when its inputs changed), **eight quiet runs of
  `perf/match_npc_vision_relative` (recorded, commit a7f3b67c, and that test's header)** (the `--quiet` gate passed, none marked
  loaded) gave the view's cost over the unviewed match as 0.33, 0.36, 0.63, 1.18, 1.58, 1.70, 2.50 and 2.51 ms, median 1.38.
  **The budget is 3.2 ms**: the highest quiet run plus 25 %, rounded, by the user's choice. Median plus 25 % (1.73 ms) was not
  chosen, because the spread is between runs (each plays a different fight) and it would fail two of these eight correct runs;
  3.2 ms still fails the cost before the savings, every one of whose runs was over it. The second check is a ratio: the live cone's
  per-frame cost (the change check, and the rebuild when there was one) over the reference cone's, built from the same eye in
  blocks of its own, at most **0.75**. The same eight runs gave 0.27, 0.31, 0.39, 0.39, 0.40, 0.42, 0.49 and 0.59, median 0.40;
  with the savings off it reads 1.00 to 1.02 and with only the skip off about 0.65 (all recorded, a7f3b67c).
- **Windowed, after the savings (not reproduced):** Vulkan, `--fixed-fps 60`, vsync off, 1152×648, the same 10v10 with the view on
  an NPC, interleaved on and off, three runs: the view on minus off was −4.74, −1.54 and −2.18 ms a frame, with the cone ratio 0.47,
  0.22 and 0.35. The ticket read this as a net gain windowed because unseen characters are not repainted while the off blocks
  repaint everyone; the GPU was not separated from the CPU in these runs, and three runs are too few to say a sign, so the claim is
  only that the view was not seen to cost windowed.
- **The pool skip (not reproduced)** alone measured 0.13 to 0.5 ms a frame (12 to 25 % of the pools' draw time), the whole frame's
  change within noise. It is kept for what it saves in the pools' own draw, not for a frame it was seen to speed up.
- **Dropped, not measured to hold:** the single world draw (V3). An earlier probe that drew only what moves in the main viewport
  read +2.6 to +6.2 ms windowed and about 3 to 4 ms of GPU saved; it is unverified, since by the ancestor rule above it probably drew
  none of the characters' children.
- **On the district, 2026-11-02 (recorded, `perf/match_npc_vision_relative` and `perf/match_npc_vision`).** Both guards now play the
  10v10 in a downtown district whose centre house is the largest plan (`Perf.configure_match`), not in a house. A quiet run (load 3.6, no other
  Godot) of the relative guard read **0.88 ms** (median of 12 rounds, rounds from -9.0 to +7.1) and the cone at 0.11 of the reference
  cone's, against the 3.2 ms and 0.75 budgets. **The budget was set on a house** (the eight runs above) and has not been set again for the
  district; it is kept, not loosened. The view's cost rose with `5204e489`, the district-cost commit (the bisect read 3.9 ms before it,
  10.4 at it and 13.7 after the planning ring), and the Vision change that followed brought it back to 4.9 and 5.2 ms: the even fan is cast
  once, the shape query takes the cone's sector, `ViewWatch` rebuilds only for a blocker where a ray can pass, and a corner beyond the
  view distance adds no ray (`vision/cone_hidden_corners_not_cast`, `cone_reads_only_its_sector`, `cone_beyond_reach_exact`). **What in
  `5204e489` raised it was not isolated**: with `environment_object_visuals.gd` and `blood_smear.gd` put back to their older form it read
  4.25 ms, with only one of the two 9 to 16, and `reask_frames` 1 changed nothing. The district had 3208 corners a rebuild against 480 on
  main, which is what the Vision change removed.
- **The cone rewrite is beyond the district brief (#182).** The even fan cast once, the shape query on the cone's sector and the
  watcher's blocker check (`view_cone.gd`, `view_sector.gd`, `view_shapes.gd`, `view_watch.gd`, the reference cone and four
  equivalence tests) were made to cut the view's cost on a district. The ticket's brief had no vision line. The cone is vertex for
  vertex the reference cone's (V-tests above), and it changes the lone house's view cost too.
- **The moving viewer, #192 (recorded, `perf/match_npc_vision_relative`, `vision/cone_same_after_savings`).** The relative guard parks
  its viewer, so it never measured the cone that rebuilds about every frame while its viewer walks (6 to 9 ms a frame in
  `perf/match_npc_vision`). #192 made that rebuild cheaper without changing a vertex: static blockers' corner polygons are kept
  across rebuilds until the collider moves, is dented or is re-cut, and each is checked against its body once a rebuild (a memo
  in front of the lookup, dropped at each rebuild, when polygons are cleared and when a collider leaves the tree: a rebuild asks for
  a polygon about 1,300 times and uses few); the angles are built without lambda sort or map. A first form also reused the previous
  ray's blocker shapes for the far face; a profile found it fired on 0.2 % of the far-face reads (298 of 146,583) and cost more than
  it saved (its isolation query, point test and settled check ran on the other 99.8 %), so it was removed. `vision/cone_same_after_savings`
  holds a walking, turning eye past moved, dented and re-cut blockers, and past a body that moves every frame, to
  `tests/_vision/reference_view_cone.gd`, frame by frame, counts the cross-rebuild reuses and the memo's hits, and checks no polygon
  is checked twice in a rebuild. The guard also plays rounds where the viewer walks a scripted loop (eye and facing change every timed
  frame, a premise it checks) and holds the moving view's median cost to `MOVING_BUDGET_MS`, **20 ms**: about 1.4x the quiet moving
  median of about 13 ms (11.89 and 10.90 ms in the two runs of 2026-11-07, so about 1.7x). It departs from `perf.md`'s 4x rule because the
  cost is a cone rebuilt every frame, and 4x of a per-frame cost would never trip. (Before the memo the quiet median was 13.9 ms, against 12.2 at the base of the story; the profile put the
  difference on the polygon re-checks and the far-face reuse.)
- **The perf matches run with `worldgen.doors` off** until #178 and #159 make the entry door-aware, which the shared perf probe
  (`tests/_perf/perf_probe.gd`) says. `perf/match_npc_vision`, the absolute guard on the same match, is still red on the district after
  #192 (2026-11-07, two runs that were not `--quiet`: avg 22.53 and 20.13, p95 35.97 and 31.25, max 46.69 and 42.67 ms). Its excess over
  the 10v10 is the moving view's cone, rebuilt almost every frame (about 11 ms a frame in the moving rounds), and a follow-up; the 10v10's
  own tail is the grenades' escape search. The relative guard's parked view read 5.64 and 4.77 ms against its 3.2 ms (rounds 1.0 to 11.7),
  red as it was on 2026-11-02 (4.9 and 5.2). Numbers and loads: `domain-testing` (`perf-district.md`).
  Tests: `vision/cone_same_after_savings`, `perf/match_npc_vision_relative`, `perf/match_npc_vision`.

## Played in a window

The headless tests never open a window, so the change was played in one (2026-11-01, Metal, Apple M2 Max, a shared machine with
load averages of 4 to 7). Each run had its own `--log-file`, and its whole log was read with
`python3 tools/scan_godot_log.py <log> --from=0`. The matches ran on `a9bb08d7`, the tests on `cd92abf4`; the two commits hold the
same `scenes/` and `addons/`, `cd92abf4` changing one test only. Perf was not re-run at either (see "When the perf figures were
measured").

- **Five played matches of Main** (Start pressed by a scratch driver once the setup menu was up, 40 s of play, the game then quit by
  `get_tree().quit()`): all five exited 0 and every scan came back empty (no error, no warning). The view, in the group
  `player_view`, was there 8 s into each match and at its end.
- **Five windowed runs of the change's game tests** (the 20 `*_test.gd` added or changed since `origin/main`, except `perf/*`, which
  these runs do not play, and `_harness/log_gate_probe`, which logs an error on purpose), each played whole in the test runner's
  window with the log gate on (`--log-file <out>/godot.log`, the file the runner follows). On `cd92abf4`: 19 passed and 1 failed in
  each of the five, the one failure `ui/leader_overlay_draw`, and no engine error or warning in any log up to its `Queue done:`
  line. `ui/leader_overlay_draw` is not this change's: the same test fails the same way (its first checks read `[]` where a crown
  should be) played in a window from an `origin/main` checkout, and passes headless; its cause was not looked into.
- **What they found.** An earlier set of five, on `a9bb08d7`, passed 19 of 20 four times and failed `vision/at_rest_remembered` once
  ("a gun was seen both moving (0 frames) and at rest (694)", 3 frames not on `WORLD`) besides `ui/leader_overlay_draw`. The shooter's
  frag grenade sends fragments ricocheting round the arena, and one killed the victim (50 hp) at 5.9 s, before the test killed it on
  the run: a body that dies standing lets its gun go with no skid, which no change of place shows moving, so the test judged the gun at
  rest after 90 still frames while it still spun on `MOVING`. Alone the test passed ten of ten windowed runs, so it was not
  reproduced by waiting; a 60 hp hit standing in for the fragments made the old test fail the same way, in a headless run. The victim
  has 100 000 hp now and the test kills it with its own health: green with the stand-in, ten of ten headless runs, five of five in the
  windowed queue above. Nothing in the player's view was wrong: the gun was on `MOVING` while it spun and on `WORLD` after.
- **`vision/unseen_not_repainted`** (gone with the 2D render: its rule, a repaint skipped for what is unseen, was the 2D drawing's) failed twice at the 17th frame of its walker's check in two windowed runs made while the editor
  was reloading the changed file (an earlier review), and passed in the twenty or so runs after. It passed in each of the five
  queues above and in ten of ten windowed runs of its own on `cd92abf4`: not reproduced, and not explained.
- **The shutdown noise.** Every log shows `BUG: Unreferenced static string to 0: ...` (33 or 34 lines) and three
  `Pages in use exist at exit in PagedAllocator` lines, all after the `Queue done:` line: the engine's shutdown noise when it is
  ended by a signal, not this change's. The test runner scene has no command server to quit through, so these runs ended by `SIGTERM`
  to the pid they started, and the same lines come out of an `origin/main` checkout ended the same way, in a count that varies from
  run to run on both, because the signal lands at a different point of the teardown. One of the five logs also holds about thirty-five
  `Can't emit non-existing signal ""` / `Attempt to connect nonexistent signal ''` lines, again after `Queue done:`, in the same
  teardown; it was not compared with `origin/main` (it came once in five and did not come again). The five matches of Main, which
  quit through the game, print none of this.
