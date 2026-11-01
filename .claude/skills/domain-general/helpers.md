# General: shared helpers (`scenes/general/`)

Static holders and small classes every domain may use; their signatures are architecture interface 11. Beside them in the file map:
`DrawLayers`, `PhysicsLayers` and `LightMasks` (`SKILL.md`, "Shared ids").

## FillBatch

`FillBatch.new(canvas, base)` draws plain-coloured polygons and circles as ONE triangle array (`fill`, `fill_convex`, `circle`, then `flush`) in place of one draw command each, because the windowed renderer builds a vertex buffer per polygon command. It cuts the same triangles the engine would and each disc into `draw_circle`'s 64-gon, so the pixels match. A polygon that cannot be triangulated goes to the engine alone after what was added, which reports it as `draw_colored_polygon` does.

Under the headless display (`FillBatch.batching` false) nothing renders and gathering costs more than it saves, so each shape goes to the canvas as it comes; code that draws plain commands itself there (the chip chunk, the blood splat) is deliberate. `FillBatch.unit_circle()` and `fan(base, n)` feed the Character's `BodyMeshes.Solid`. Test: `tests/general/fill_batch_matches_draw_calls_test.gd` (headless: the triangles; `--windowed`: identical pixels).

## WeightedPick

One `rng.randf()` over the total weight; each entry takes the next stretch. `strict` keeps each caller's edge behaviour: false, a roll on the end of a stretch takes that entry and one past them all takes the last; true, it takes the next entry and one past them all takes the first. The room dresser, room wear and street marks, the Lighting rhythms (not strict) and the Character's style (strict) draw through it. Test: `tests/general/weighted_pick_suite.gd`.

## MatchVerdict

`MatchVerdict.decide(combatants)` is the one rule the MatchHUD banner and the command server's `match` decide by: `{}` while every faction has someone alive; once one is wiped out, `{ winner, survivors, sides }` (`winner` null for a draw). It reads `faction` and `is_dead` only and leaves a freed combatant out. Tests: `tests/ui/match_hud_verdict_test.gd`, `command_server_verdict_suite.gd`.

## ViewLayers

`view_layers.gd` holds the visibility bits (`CanvasItem.visibility_layer`) the player's view sorts the world by: `WORLD` 1 (Godot's default: the house and what has come to rest, which the view remembers), `MOVING` 2 (what moves: drawn only inside the cone) and `OVERLAY` 4 (overlays, markers and the view's own composite). The Vision domain's capture leaves `MOVING` and `OVERLAY` out of its `canvas_cull_mask` (`domain-vision`). `set_moving(item, moving)` writes `visibility_layer` only when it changes, so a caller may ask every frame (Character, Items, Projectile, Physics and Vehicles call it for what they own); `overlay(item)` sets `z_index` to `DrawLayers.OVERLAY`, `z_as_relative` off and the `OVERLAY` bit, for the debug overlays and markers, called in their `_init` / `_ready` (a subclass that overrides `_ready` calls `super()`). A light is not a canvas item to the engine, so these bits never reach it (`domain-lighting`).

## SightRay

`sight_ray.gd` is the one sight rule: `SightRay.hit(space, from, to, exclude, see_over)` walks the line on `PhysicsLayers.SOLID`, looking over each collider whose `coverage` (its `get_surface()`, 0 to 100) is at or below `see_over` and casting again past it, and returns the first hit too tall to see over (`intersect_ray`'s dictionary: `collider`, `rid`, `position`, `shape`) or {} when the line reaches `to`. The caller's `exclude` is never changed (a copy grows by one rid a pass). `coverage_of(collider)` is the read: a surface that says `transparent` (a glass-panel door) reads 0, so it is looked through however tall; a collider that cannot say its coverage reads 100, a full blocker. The static `hit` borrows one shared instance; an instance keeps `looks_over`, a `rated` dictionary (the coverage already known by collider instance id, which the caller owns and fills only with colliders whose coverage cannot change) and `leave_out(rids)` once, then `cast(space, from, to)` walks without handing the exclude list to the physics server again: the view's cone casts hundreds of rays a frame this way. AI perception's `AgentVision.sight_hit` delegates to `hit` with the NPC's `see_over_coverage` (60), and the cone casts through an instance, so the NPCs and the view see alike. Test: the native suite `tests/general/sight_ray_suite.gd` (a space of hand-placed pieces: a wall, a table, a piece at and just over the limit, a body that cannot say its height, the exclude list).

## SeenArea

`seen_area.gd` is the part of the world the player's view shows live (`docs/player-vision.md` V11). Vision writes it when it rebuilds the cone (`set_area(polygons, bounds)`: the cone's and the bubble's polygons) and clears it when the view lifts (`clear()`). What is only ever seen inside the cone asks `reaches(center, radius)` for a disc (Character's visuals: a body's 60 px reach) or `reaches_rect(rect)` for a long thin box (a blood pool's cells: the circle round a long box reaches far past its ends, and into the viewer's 48 px bubble when the box does not), and skips its repaint while the answer is false. With no area set (no view, a view lifted, the switch off) both are true, so nothing is skipped. `contains(polygon, point)` is the one point-in-polygon test (the view's `sees` asks it), an even-odd rule, not `Geometry2D.is_point_in_polygon`: the engine's says a point is inside some simple polygons it lies well outside of (a cone with many collinear corners along a wall). Tests: the native suites `tests/general/seen_area_suite.gd` and `seen_area_rect_suite.gd`, and `vision/unseen_not_repainted`; `vision/view_sees_suite` holds `sees` at a cone the engine's rule gets wrong.
