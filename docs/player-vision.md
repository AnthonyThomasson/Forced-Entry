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
bubble all round, and a line of sight on `PhysicsLayers.SOLID` that walls and pieces of `coverage` above 60 break and lower pieces
(tables, beds, counters) do not. The numbers are a Character holder's (`CharacterVisionConfig`, read through `character.sight()`),
so any character carries the same view. The cone is exact at corners: nothing behind a wall corner or a doorway's end is in it. A
wall or tall piece that is seen shows its top: the cone reaches the far face of the shapes the ray met. It is complete however
many blockers are in reach (the shape query is asked again with more room while it comes back full, so no cap drops one). Doors
(`docs/doors.md`) follow the same rule: a shut solid door blocks, a glass-panel door (`transparent`) is seen through, an ajar
door's gap is seen through, a knocked-down door does not block. The cone is rebuilt only when its output can change: the eye moved
or turned, the viewer's sight numbers changed, or within reach a blocker moved, changed shape (a dent, a wall re-cut, a door's
swing, fall or shattered panes), joined or left, or changed coverage or `transparent`; plus a forced rebuild every
`VisionConfig.rebuild_every` (10) physics frames, a backstop. A skipped frame's cone equals a fresh rebuild's, vertex for vertex.
Tests: `vision/cone_follows_sight` (two rooms joined by a doorway, a wardrobe and a table, the eye turned: points over the table
and inside the cone are in the polygon; points behind the wardrobe, beyond the wall, behind the eye past 48 are not; points
within 48 behind it are), `vision/cone_exact_at_corners` (eyes near the room corners and the doorway's ends, facing along and
across the walls: no sampled point behind a corner is inside the polygon and every sampled point the eye sees is; a seen wall's far
face is in the polygon, the room beyond is not), `vision/cone_exact_with_many_blockers` (more solid shapes in reach than any
query cap: every wardrobe keeps its corner rays), `vision/cone_same_after_savings` (the live cone against the cone before any
saving, vertex for vertex, over a grid of eyes and facings in generated houses and after a door, a shove and a freed piece move
through it), `vision/cone_skip_exact` (a still then a turning viewer through a dent, a shove, a door's swing, panes shattered, a
door knocked down, a piece added and freed, a posture change and a death: every frame the polygon equals a fresh rebuild's, vertex
for vertex; a still viewer rebuilds far less than every frame and never goes more than `rebuild_every` frames without a rebuild).
What no vision test asserts directly: the room beyond a shut glass-panel door is in the polygon and the room beyond a shut solid
one is not (the rule is V2's, and `objects/door_blocks` holds it for an NPC's sight).

**V2. One sight rule.** The look-over-low-furniture ray is one rule in General (`SightRay`, interface 11), used by the NPCs'
sight (`AgentVision.sight_hit` delegates to it) and by the view; a `transparent` surface (a glass-panel door) is looked through
however tall, and a collider that cannot say its coverage blocks like a wall. The NPCs see exactly as they did before it moved.
Tests: `general/sight_ray_suite` (native: the rule over a built space: a wall, a table, a piece at and just over the limit, a
body that cannot say its height, the caller's exclude list left alone) and every `ai` vision test unchanged
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
the memory where it was seen; moved again, it is moving again. Tests: `vision/at_rest_remembered` (a dead body on `MOVING` until its
ragdoll sleeps, on `WORLD` after and on `MOVING` again from the frame a blast wakes it; a dropped gun, a casing and a frag
lying still on `WORLD`, in flight on `MOVING`), `vision/vehicle_rest_remembered` (a car driven, then parked).

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
`vision/death_lifts_view` (the node, its composite and its viewports are gone within a frame and none comes back).

**V10. The switch.** `VisionConfig.enabled` (default on) gates the view in Main's match; the test world's `vision.enabled`
switch is off unless a test asks, so existing tests and sandboxes look as they do; with it on, the world views its `player`
actor, or the actor `TestSetup.view` names. Tests: `vision/switch_off` (no `PlayerView` and no `SubViewport` under the world).

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
tests over polygons laid out by hand, an L-shaped polygon, no area set).

## Technique

A *capture* viewport shares the main world, at the camera's size and canvas transform, culling `MOVING` and `OVERLAY`; a world-space
*memory* viewport (never cleared) the cone polygon paints from the capture each frame, so it keeps the world as it was last seen
and stays transparent where nothing was seen; a screen-sized *mask* viewport draws the polygon (blurred for the feather); the
*composite* is drawn in the world's own canvas at `DrawLayers.VISION`, unshaded, so overlays at `OVERLAY` stay over it in
colour. The three viewports are siblings (a viewport nested in another makes the engine log an error).

The **cone polygon** is a fan from the eye over ray ends sorted by angle. The rays are an even fan (`cone_rays` 64 across the cone,
`bubble_rays` 48 round the eye) plus, exactly at corners, three for each corner of each blocking shape the eye can see (the
corner's own angle and `corner_offset` either side), so a chord of the fan never cuts across the shadow behind a corner. The shapes
come from a physics shape query on the solid layer (a circle of the view distance), never a walk of the scene tree. Every ray is
cast leaving out the low pieces in reach, so it meets its first blocker in one cast; where it ends on a blocker it runs on to where
it leaves the solid (the farthest exit over the blocking shapes holding a point 0.1 px along it, at most `far_depth` 120; `far_bleed`, 14, in
when it leaves through no edge). Two choices make a rebuild independent of which of several overlapping shapes the
engine names: the far-face pick reads the shapes that hold the point and not the shape the ray hit, and two corners less than half
a pixel apart are one, the lesser (x, then y) standing for them. Without both, a fresh rebuild was not deterministic.

**What triggers a rebuild** (`ViewWatch`): the eye, the facing, the sight numbers and the cone's `VisionConfig` numbers; any
blocker's transform or collision layer, each frame; by signal a blocker's shapes coming or going, its leaving the tree, a door's
`changed`; a collider that entered the tree; a character that blocks (its posture covers more than the viewer looks over, so it
may move, turn its shape off or die in any frame: the cone is rebuilt every such frame and the one after); and
`rebuild_every` frames since the last. A low piece is looked over, so it is in no ray and is not watched. A piece's coverage and a
door's `transparent` are read once and kept: a piece's coverage is set once in `ObjectFactory`, a door's is always 100 and its
`transparent` is fixed at spawn (a shatter changes only the look's `broken`); a character's coverage follows its posture and is
read each build.

## Tunables

`VisionConfig`: `enabled` true; the look `grey` 1.0, `contrast` 0.9, `pivot` 0.3, `brightness` 0.55, `tint` (0.88, 0.96, 1.12);
`feather` 16; `memory_scale` 2; `cone_rays` 64, `bubble_rays` 48, `corner_offset` 0.0002 rad; `far_depth` 120, `far_bleed` 14;
`rebuild_every` 10. `CharacterVisionConfig`: `fov_degrees` 110, `view_distance` 2520, `awareness_radius` 48,
`see_over_coverage` 60. The repaint reach is `CharacterVisuals.SEEN_REACH` (60). The look and the 16 px edge were picked by eye,
against a flat 45 % grey (too dark and flat), a full-brightness grey (too close to the live world), a hard edge (a harsh line) and
a 40 px feather (it smears the cone).

## Measured cost

The perf tests run headless and see only the CPU side, so the GPU side was measured by hand, windowed, as `docs/lighting.md`
"Measured cost" does. Figures below are from the ticket's own measurements and the runs its slices recorded; **the wrap-up ran no
perf test** (the user chose to skip it): slice 16's eight quiet runs stand for the final state.

- **Before the savings:** a windowed 10v10 (the view on an NPC) cost the view about +7.4 ms a frame, 4 to 5 ms of it the cone's
  CPU, about 3 ms the second world render (the capture) and about 2 ms GPU. A measurement of the same match before slices 13 and 14 (a shared,
  loaded machine, load average 1.2 to 4.0; Vulkan, 1152×648, `--fixed-fps 60`, vsync off) put the median frame at 18.78 ms headless
  and 29.95 ms windowed, and the cone's rebuild at 4.86 ms headless and 3.81 ms windowed, the characters' visual update at 3.78 and
  7.00 ms, blood 1.69 and 1.51 ms (0.73 and 0.50 ms of it pools wholly outside the cone). The cone's cost depends on where the
  viewer stands (2.6 to 6.0 ms between runs).
- **Slice 11 (the cone's own caches, the same polygon):** the view's cost 5.68 to 3.65 ms, and the cone's headless bench down 45 %.
- **After slices 13 and 14** (unseen characters not repainted; the cone rebuilt only when its inputs changed), eight quiet runs of
  `perf/match_npc_vision_relative` (the `--quiet` gate passed, none marked loaded) gave the view's cost over the unviewed match as
  0.33, 0.36, 0.63, 1.18, 1.58, 1.70, 2.50 and 2.51 ms, median 1.38; before the savings ten quiet runs gave 2.92 to 5.46 ms,
  median 4.36. **The budget is 3.2 ms**: the highest quiet run plus 25 %, rounded, by the user's choice. Median plus 25 % (1.73
  ms) was not taken, because the spread is between runs (each plays a different fight) and it would fail two of these eight correct
  runs; 3.2 ms still fails the cost before the savings, every one of whose runs was over it. The second check is a ratio: the live
  cone's per-frame cost (the change check, and the rebuild when there was one) over the reference cone's, built from the same eye in
  blocks of its own, at most **0.75**. The eight runs gave 0.27, 0.31, 0.39, 0.39, 0.40, 0.42, 0.49 and 0.59, median 0.40; with the
  savings off it reads 1.00 to 1.02 and with only the skip off about 0.65.
- **Windowed, after the savings** (Vulkan, `--fixed-fps 60`, vsync off, 1152×648, the same 10v10 with the view on an NPC,
  interleaved on and off, three runs): the view on minus off was −4.74, −1.54 and −2.18 ms a frame, with the cone ratio 0.47,
  0.22 and 0.35. The view is a net gain windowed because unseen characters are not repainted while the off blocks repaint
  everyone; the GPU was not separated from the CPU in these runs.
- **The pool skip** alone measured 0.13 to 0.5 ms a frame (12 to 25 % of the pools' draw time), the whole frame's change within
  noise.
- **Dropped, not measured to hold:** the single world draw (V3). An earlier probe that drew only what moves in the main viewport
  read +2.6 to +6.2 ms windowed and about 3 to 4 ms of GPU saved; it is unverified, since by the ancestor rule above it probably drew
  none of the characters' children.
- **The perf matches run with `worldgen.doors` off** until #178 and #159 make the entry door-aware, which the shared perf probe
  (`tests/_perf/perf_probe.gd`) says. `perf/match_npc_vision` is red with its unviewed sibling
  `perf/match_10v10_stress` until #98.
