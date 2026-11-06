# Player vision

In a played match the screen shows only what the human's character sees. What it saw before is drawn as the world it last
saw, in a dark cool greyscale (black where it never looked), and nothing that moves is drawn out of view. Behaviours V1 to V11
are the spec; each has its tests named under it, following the convention of `docs/lighting.md`. The tests are in `tests/vision/`
(`tools/run_tests.sh --domain=vision`) through `tests/_vision/vision_probe.gd`, which keeps the spec's numbers as its own consts
and reads the game only through the names interface 25 publishes, so a test checks this file and not the code. The code is the
Vision domain (`scenes/vision/`, skill `domain-vision`, `docs/adr/0011-the-vision-domain.md`); the shared rules it stands on are
General's (`SightRay`, `ViewLayers`, `SeenArea`, `DrawLayers.VISION` and `OVERLAY`: `architecture` interface 11).

All distances are px and angles degrees unless said. The numbers are `VisionConfig`'s (`scenes/vision/`) and, for what a character
sees by, `CharacterVisionConfig`'s (`scenes/character/`).

## What is built

`PlayerView.watch(root, character)` (the match builder's `populate` for Main's human, the Testing world for its viewer) adds one
`PlayerView` node under the world, in the group `player_view`, with the reads `cone()`, `bubble()`, `sees(point)`, `viewer()`,
`rebuilds()` and the parts it draws with: the **capture** (a `SubViewport` sharing the main world, the camera's size and canvas
transform, whose cull mask leaves out `ViewLayers.MOVING` and `OVERLAY`), the **memory** (a world-space `SubViewport` over the
floors' bounds, `memory_scale` texels a px, never cleared, which the cone's polygon paints from the capture each frame), the
**mask** (a screen-sized `SubViewport` holding the cone, its edge feathered) and the **composite** (a screen polygon drawn at
`DrawLayers.VISION` whose shader cuts the live world out where the mask says inside and draws the memory in the look outside).
The world's own things carry the rest: each moving thing's domain sets its `visibility_layer` (`ViewLayers.set_moving`), and each
overlay owner makes its node an overlay (`ViewLayers.overlay`).

The words the spec uses: the **view** is the whole of this; the **cone** is the polygon of what the viewer sees now (the cone
round its facing and the bubble round it); the **memory** is the picture of what it saw; a thing is **moving** or **at rest**
by the bit it sits on; the **seen area** is what General's `SeenArea` says the cone shows live (`GLOSSARY.md`).

## Behaviours

**V1. The cone.** The human sees what the NPCs see, by their default numbers: a 110° cone round its `facing` out to 2520, a 48
bubble all round, and a line of sight on `PhysicsLayers.SOLID` that walls and pieces of `coverage` above 60 break and lower
pieces (tables, beds, counters) do not. The numbers are a Character holder's (`CharacterVisionConfig`, read through
`character.sight()`; the native suite `character/character_vision_config_suite` holds them to the spec and equal to the NPCs'
default `NpcSensesTuning`), so any character carries the same view. The cone is exact at corners: nothing behind a wall corner
or a doorway's end is in it. A wall or tall piece that is seen shows its top: the cone reaches the far face of the shapes the
ray met. It is complete however many blockers are in reach (the shape query is asked again with more room while it comes back
full, so no cap drops one). Doors (`docs/doors.md`) follow the same rule: a shut solid door blocks, a glass-panel door
(`transparent`) is seen through, an ajar door's gap is seen through, a knocked-down door does not block. The cone is rebuilt
only when its output can change: the eye moved or turned, the viewer's sight numbers changed, or where a ray can pass (the sector the viewer looks along and the bubble round it,
within the view distance) a blocker moved,
changed shape (a dent, a wall re-cut, a door's swing, fall or shattered panes) or joined or left; plus a forced rebuild every
`VisionConfig.rebuild_every` (10) physics frames, a backstop. A skipped frame's cone equals a fresh rebuild's, vertex for
vertex. Tests: `vision/cone_follows_sight` (two rooms joined by a doorway, a wardrobe and a table, the eye turned: points over
the table and inside the cone are in the polygon; points behind the wardrobe, beyond the wall, behind the eye past 48 are not;
points within 48 behind it are), `vision/cone_exact_at_corners` (eyes near the room corners and the doorway's ends, facing along
and across the walls: no sampled point behind a corner is inside the polygon and every sampled point the eye sees is; a seen
wall's far face is in the polygon, the room beyond is not), `vision/cone_exact_with_many_blockers` (more solid shapes in reach
than any query cap: every wardrobe keeps its corner rays), `vision/cone_same_after_savings` (the live cone against the reference
cone, the plainest form of the cone, vertex for vertex, over a grid of eyes and facings in generated houses and after a door, a
shove and a freed piece move through it), `vision/cone_skip_exact` (a still then a turning viewer through a dent, a shove, a
door's swing, panes shattered, a door knocked down, a piece added and freed, a posture change and a death: every frame the
polygon equals a fresh rebuild's, vertex for vertex; a still viewer rebuilds far less than every frame and never goes more than
`rebuild_every` frames without a rebuild). `vision/cone_follows_sight` also hangs three doors in the wall the rooms share, and
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

**V2. One sight rule.** The look-over-low-furniture ray is one rule in General (`SightRay`, interface 11), used by the NPCs'
sight (`AgentVision.sight_hit` delegates to it) and by the view; a `transparent` surface (a glass-panel door) is looked through
however tall, and a collider that cannot say its coverage blocks like a wall. The NPCs see exactly as they did before it moved.
Tests: `general/sight_ray_suite` (native: the rule over a built space: a wall, a table, a piece at and just over the limit, a
body that cannot say its height, a `transparent` piece looked through however tall and its coverage read as 0, the caller's
exclude list left alone) and every `ai` vision test unchanged
(`tools/run_tests.sh --domain=ai`; `objects/door_blocks`).

**V3. Inside the cone** the live world is seen as it is, characters and all. A character at the edge is cut by the edge per
pixel (the composite is transparent inside the mask and feathered at its edge). The main viewport draws the whole world live: a
single world draw (the still world drawn once, in the capture, and the main viewport left with what moves) was planned and
dropped. Godot 4.4 draws a canvas item in a viewport only if the item and every ancestor share a bit with its
`canvas_cull_mask`, and an item's bit defaults to 1, so a main viewport that left out `WORLD` would also have left out the HUD, the
world root and every unmarked child of a moving thing. Tests: `vision/memory_follows_cone`.

**V4. Outside the cone** each place is drawn **as the human last saw it**, the memory, in the picked look: greyscale (`grey`
1.0), contrast 0.9 about 0.3, brightness 0.55, tint (0.88, 0.96, 1.12), "Darkwood cool". A place never seen is **black**. The edge
is feathered over **16** screen px, laid inside the edge (a disc of 32 shifted copies of the polygon, averaged). The memory starts
empty when the match starts (the engine does not clear it, so a wipe writes "nothing seen" over it for its first two frames) and
holds only what was on screen when it was seen. It is `memory_scale` (2) texels a px over the floors' bounds, and drops below that
to fit Godot's 16 384 px texture limit. Tests: `vision/memory_follows_cone` (the memory covers the floors' bounds at its scale,
starts empty, is emptied once and never again; its painter paints the cone polygon from the capture; the composite is at
`DrawLayers.VISION` and carries the look and feather of `VisionConfig`), `vision/memory_fits_texture_limit` (a 20 000 px arena).
A headless run has no pixels: these tests read what the parts are told, and the look is judged by eye in a window.

**V5. Never remembered while moving:** living characters (allied and hostile) and what they hold, bullets and tracers, grenades
in flight, hit particles, flying debris, blood spray, an explosion's look, a shot's or a burst's flash light, and a vehicle while
it moves. They sit on `ViewLayers.MOVING` and are drawn only inside the cone, since the capture leaves that bit out. A `Light2D`
ignores a viewport's cull mask, so the flash lights are kept out of the memory by living under a `CanvasLayer` of the main
viewport, which the capture does not draw, and still light the world on screen. Tests: `vision/moving_never_remembered` (the
living puppets and their gun, a bullet, a grenade in flight, hit particles, debris, blood spray and an explosion's look on
`MOVING` and not drawn by the capture; furniture, a wall and settled blood are; the flash lights are on a canvas the capture does
not draw and still light the screen where they burst).

**V6. Remembered once at rest:** a dead body once its ragdoll sleeps, a dropped item, a spent casing, a grenade lying still, a
parked vehicle, and the house and street (floors, walls, doors, furniture where last seen, settled blood, scorch, debris chips).
A door is always `WORLD`: it is remembered where last seen at whatever angle, mid-swing included. Once at rest a thing is part of
the memory where it was seen; moved again, it is moving again. Only a body and a vehicle can be moved again: a dropped item, a
casing and a grenade at rest stay at rest for good (nothing shoves them: a dropped item stops its physics for good, a casing's
toss runs once, a resting grenade does nothing but wait for its fuse), so the "moved again" case is the corpse a blast wakes.
Tests: `vision/at_rest_remembered` (a dead body on `MOVING` until its ragdoll sleeps, on `WORLD` after and on `MOVING` again from
the frame a blast wakes it; a dropped gun, a casing and a frag lying still on `WORLD`, in flight on `MOVING`; in a world of its
own a wooden door swung open and shut is on `WORLD` and drawn by the capture in every frame of its swing),
`vision/vehicle_rest_remembered` (a car driven, then parked).

**V7. Debug overlays and markers are drawn over the view, in colour:** the AI debug overlays (an NPC's own too, out of view),
the navigation and leader overlays, the contact, stack and order markers. They sit at `DrawLayers.OVERLAY` (absolute, above
`VISION`) on `ViewLayers.OVERLAY`, which the capture leaves out, so they are never remembered. Tests: `vision/overlays_over_view`
(an NPC with every overlay on, the navigation holes, the leaders' crowns and the stack, order and contact markers).

**V8. Whose view.** In Main the view is built in a played match (Start) for the human only; Watch and Endless (no human) draw
everything. In a test world any one character can be the viewer, an NPC included (`TestSetup.view(actor_id)`): the screen then
shows what that NPC sees, by the same rules, so a test (the perf guard among them) runs the view's real cost. Viewing an NPC
changes nothing in its AI. Tests: `vision/view_only_for_the_human` (a declared match with a human has one view, of the human),
`vision/no_view_without_a_human`, `vision/main_view_for_start_only` (Main run whole: Start builds one view, Watch none),
`vision/view_on_npc` (one view, its polygon from the NPC's eye and facing as it turns; the same scripted run with and without the
view gives the same decisions, places and arrival tick).

**V9. The viewer's death lifts the view** (the human's, or a viewed NPC's in a test): everything is drawn again at once, live, for
the rest of the match. So does the viewer leaving the tree without dying; a viewer already dead gets no view. Tests:
`vision/death_lifts_view` (the node, its composite and its viewports are gone within a frame and none comes back; and
nothing is hidden after: `SeenArea` holds no area, so a disc and a box far from where the viewer stood reach it again, which they
did not while the view stood, for the human's death, a viewed NPC's, and a viewer freed or removed).

**V10. The switch.** `VisionConfig.enabled` (default on) gates the view in Main's match; the test world's `vision.enabled`
switch is off unless a test asks, so existing tests and sandboxes look as they do; with it on, the world views its `player`
actor, or the actor `TestSetup.view` names. Tests: `vision/switch_off` (no `PlayerView` and no `SubViewport` under the world, and `SeenArea` holds no area: a far disc and
box reach it, so no repaint is skipped).

**V11. Unseen characters are not repainted.** A character whose drawn reach (a 60 px disc round it) lies wholly outside the cone
and bubble is not repainted while it stays there; its pose, aim, hands, footsteps and ragdoll keep running (gameplay reads those,
never the drawing). The frame any of its reach enters the cone it is repainted before it is drawn. A dead body at rest keeps its
last drawing (it is remembered). A blood pool is not redrawn while the box its cells cover is wholly outside the cone, and is
redrawn the frame the cone reaches it. With no view (Watch, Endless, the switch off, the view lifted) everything is repainted as
before. The seen area is General's `SeenArea`: Vision writes the cone's polygons each rebuild and clears them on a lift; a disc
(`reaches`) or a box (`reaches_rect`) asks it. The one test of a point inside a polygon is `SeenArea.contains`, an even-odd rule (the view's `sees` asks it too), since the engine's
`Geometry2D.is_point_in_polygon` said inside for points well outside a cone with many collinear corners; a pool asks about its
box, not the circle round it, whose radius reaches into the viewer's 48 px bubble when the box does not. A character decides in
`_process` and a pool in `_process` too (marked stale in physics), after the view has written the frame's area in its physics tick,
so a repaint is never a frame late. Tests: `vision/unseen_not_repainted` (a walker outside the cone: its repaint count is flat and
its pose keeps updating, a bullet hits the same zone with and without the view; walking in, it is repainted the frame its reach
enters; a settled body outside keeps its drawing; a pool outside is never redrawn and is redrawn the frame the cone sweeps onto
it; repainted again when the view lifts), `general/seen_area_suite` and `general/seen_area_rect_suite` (native: the disc and box
tests over polygons laid out by hand, an L-shaped polygon, no area set), `vision/view_sees_suite` (native: `sees` at a cone the
engine's point-in-polygon gets wrong, the bubble, no polygon).

**Sound.** There is no on-screen hint for gunfire or footsteps heard out of view; sound stays as it is (`docs/hearing.md` is the
AI's side).

## Out of scope

Any view in Main's Watch and Endless (no spectator view, no side views), a view for NPCs in Main's matches (a test world can view
one, V8), more than one viewer at once, an on-screen hint for sounds, the memory fading with time, capturing what is off screen,
a view of the dead human.

## Technique

A *capture* viewport shares the main world, at the camera's size and canvas transform, culling `MOVING` and `OVERLAY`; a world-space
*memory* viewport (never cleared) the cone polygon paints from the capture each frame, so it keeps the world as it was last seen
and stays transparent where nothing was seen; a screen-sized *mask* viewport draws the polygon (blurred for the feather); the
*composite* is drawn in the world's own canvas at `DrawLayers.VISION`, unshaded, so overlays at `OVERLAY` stay over it in
colour. The three viewports are siblings (a viewport nested in another makes the engine log an error).

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
entered the tree; a character that blocks (its posture covers more than the viewer looks over, so it
may move, turn its shape off or die in any frame: the cone is rebuilt every such frame and the one after); and
`rebuild_every` frames since the last. A low piece is looked over, so it is in no ray and is not watched. A piece's coverage and a
door's `transparent` are read once and kept: a piece's coverage is set once in `ObjectFactory`, a door's is always 100 and its
`transparent` is fixed at spawn (a shatter changes only the look's `broken`); a character's coverage follows its posture and is
read each build. **`ViewWatch` does not watch either**, though the rebuild
rule as first written lists a changed `coverage` or `transparent` among its triggers: Objects promises that neither changes in play
(interface 03). Should one ever change, the cone is stale until the next rebuild, at most `rebuild_every` (10) frames later, the
backstop that bounds it; a feature that makes one change must tell `ViewShapes` and `ViewWatch`.

## Tunables

`VisionConfig`: `enabled` true; the look `grey` 1.0, `contrast` 0.9, `pivot` 0.3, `brightness` 0.55, `tint` (0.88, 0.96, 1.12);
`feather` 16; `memory_scale` 2; `cone_rays` 64, `bubble_rays` 48, `corner_offset` 0.0002 rad; `far_depth` 120, `far_bleed` 14;
`rebuild_every` 10. `CharacterVisionConfig`: `fov_degrees` 110, `view_distance` 2520, `awareness_radius` 48,
`see_over_coverage` 60. The repaint reach is `CharacterVisuals.SEEN_REACH` (60). The look and the 16 px edge were picked by eye,
against a flat 45 % grey (too dark and flat), a full-brightness grey (too close to the live world), a hard edge (a harsh line) and
a 40 px feather (it smears the cone).

## Measured cost

The perf tests run headless and see only the CPU side, so the GPU side was measured by hand, windowed, as `docs/lighting.md`
"Measured cost" does. **Each figure below says where it comes from.** *Recorded* means a commit's test header or message holds it
(the commit is named). *Not reproduced* means it comes from the ticket's own measurements and its slices' notes, was first
written down in this document (commit 6ecb4659) and has been re-run by no one since: take it as the order of magnitude it
gave, not as a number to hold the code to.

**When the perf figures were measured.** Every perf figure below but the last two bullets (the district, 2026-11-02) was taken before commit 6bd7cc63 (a blood pool's repaint
decided on the frame's view, by its box), and **no perf test was run after it or after the later fixes of the review, until the district run of 2026-11-02 (the bullet below)**. 6bd7cc63
does not touch the cone, the change check or the ratio the second guard reads, so the cone figures and the ratio stand. It does
touch the frame the first guard reads: a pool now asks `SeenArea.reaches_rect` (a box, a little cheaper to refuse than the
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
  `perf/match_npc_vision`). #192 made that rebuild cheaper without changing a vertex: a rebuild reuses the previous ray's blocker
  shapes for the far face when the collider, shape and face normal are the same and nothing else blocking overlaps the shape;
  static blockers' corner polygons are kept across rebuilds until the collider moves, is dented or is re-cut; the angles are built
  without lambda sort or map. `vision/cone_same_after_savings` holds a walking, turning eye past moved, dented and re-cut blockers to
  `tests/_vision/reference_view_cone.gd`, frame by frame, and counts both reuses. The guard now also plays rounds where the viewer
  walks a scripted loop (eye and facing change every timed frame, a premise it checks) and holds the moving view's median cost to
  `MOVING_BUDGET_MS`. **That budget is provisional**: it was set from runs on a loaded machine (load 8 to 12; medians 16.6 and
  17.2 ms, live cone at 0.27 of the reference's), and the wrap-up re-sets it from quiet runs at about 4x their baseline.
- **The perf matches run with `worldgen.doors` off** until #178 and #159 make the entry door-aware, which the shared perf probe
  (`tests/_perf/perf_probe.gd`) says. `perf/match_npc_vision`, the absolute guard on the same match, is red on the district with
  `perf/match_10v10_stress`, `perf/match_5v5_stress` and `perf/grenade_match_stress` (avg 25.0, p95 48.7, max 70.1 ms): the AI's
  decisions in open combat, #190 (`domain-testing` (`perf-district.md`)).

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
- **`vision/unseen_not_repainted`** failed twice at the 17th frame of its walker's check in two windowed runs made while the editor
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
