# General: shared helpers (`scenes/general/`)

Static holders and small classes every domain may use; their signatures are architecture interface 11. Beside them in the file map:
`PhysicsLayers` and `ViewLayers` (`SKILL.md`, "Shared ids").

## WorldRng

`WorldRng` (`world_rng.gd`, statics) is each world's own chance and order. `MatchBuilder.stage` registers the world node with the
match `seed` (`WorldRng.register(root, seed)`); anything under it finds its world by walking up (`WorldRng.of(node)`), so there is
no global state a second world could share. `of(node)` is the world's `RandomNumberGenerator`; draw from it, never the global
`randf`, wherever chance steers the fight: a shot's spread, a casing's side, a blast's fragments, a chip of debris,
a fall's jolt, a stun's sway, a dropped item's toss, the seed of a dent (it becomes the collider) and a character's gait phase, drawn as it
spawns (it feeds the muzzle in a waver stance and a stunned stride). The NPC's blind-fire roll seeds from it and the spawn order.
`Character._enter_tree` calls `enrol`, which hands each character the next place (from 0) in its world; a character moved into
another world (the scene's player, joined to the match) takes that world's next place and drops the old. `order_of(instance_id)`
reads it and `before(a, b)` is the one "who was spawned first" test. Every order or timing in the AI that used to read an instance id
(the sight cadence, give way, a stack slot or doorway two claim) reads this instead, since an instance id follows what the process
allocated before. An id stays the key to look a character up by.

`WorldRng.frame_of(node)` is the `GameClock` frames its world has run since its first character took its place (still while paused): the frame every AI cadence and phase counts (the sight cadence, the house look), never the process's `Engine.get_physics_frames()`, which follows what ran before the world. The first character's place also puts the game clock's ms grid on that frame (`GameClock.align`, below).

Left on the global stream on purpose, because it only looks and changes no fight: blood and hit particles, the spin and toss of a
dropped item, a thrown grenade and its spoon, an explosion's look, the painters, world-gen, lighting and audio. Tests:
`tests/general/world_rng_two_worlds_test.gd`, `match_seed_plays_its_own_fight_test.gd`, `tests/ai/perception/sight_checks_spread_test.gd`.

## WeightedPick

One `rng.randf()` over the total weight; each entry takes the next stretch. `strict` keeps each caller's edge behaviour: false, a roll on the end of a stretch takes that entry and one past them all takes the last; true, it takes the next entry and one past them all takes the first. The room dresser, room wear and street marks, the Lighting rhythms (not strict) and the Character's style (strict) draw through it. Test: `tests/general/weighted_pick_suite.gd`.

## MatchVerdict

`MatchVerdict.decide(combatants)` is the one rule the MatchHUD banner and the command server's `match` decide by: `{}` while every faction has someone alive; once one is wiped out, `{ winner, survivors, sides }` (`winner` null for a draw). It reads `faction` and `is_dead` only and leaves a freed combatant out. Tests: `tests/ui/match_hud_verdict_test.gd`, `command_server_verdict_suite.gd`.

## ViewLayers

`view_layers.gd` holds the visibility bits (`CanvasItem.visibility_layer`) the player's view sorts the world by: `WORLD` 1 (Godot's default: the house and what has come to rest, which the view remembers), and `MOVING` 2 (what moves: Art's `WorldMirror` reads it off the 2D node to hide its mesh outside the cone, `domain-vision`; it stays after the 2D render's deletion, the mirror needs it). `set_moving(item, moving)` writes `visibility_layer` only when it changes, so a caller may ask every frame (Character, Items, Projectile, Physics and Vehicles call it for what they own); `overlay(item)` hands the debug overlays and markers to `GroundLayer.adopt` (no z, no bit: they lie flat on the ground over the 3D view), called in their `_init` / `_ready` (a subclass that overrides `_ready` calls `super()`). A light is not a canvas item to the engine, so these bits never reach it (`domain-lighting`).

## SightRay

`sight_ray.gd` is the one sight rule, real heights (#194 D9, `docs/player-vision.md` V2). **The eye ray** is a 3D ray in the twin space (`TwinSpace`, interface 29) on `MASK` (`TWIN_WORLD | TWIN_VEHICLE`: walls, doors, furniture, vehicles; a body never blocks): `hit(space3d, from, to, exclude)` returns the first blocker or {}, looking through a twin whose body's surface says `transparent` (a glass-panel door) and through the twin rids in `exclude`; `sees` / `visible_heights` ask it of a list of heights over a plan point from an eye point, the first clear one ending the ask (a target costs 1 ray to 3 rays, never more). A viewer's eye is `eye_point(viewer)` (its plan position lifted to `BodyHeights.eye` of its posture), a body's points `target_heights(target)` (`BodyHeights.sight_points`: head at the eye, chest, hips, at its posture); `visible_parts(viewer, target)` and `visible_centre` are the public query (which points show, and their middle: what an aim at the visible part reads). **The plan cast** serves the player's cone, a floor-plan polygon: `plan_hit(space2d, from, to, exclude, see_over)` walks the line on `PhysicsLayers.SOLID`, looking over each collider whose `top_of` is at or below `see_over` (the eye's height, px) and casting again past it, and returns the first one taller or {}; `top_of(collider)` is the collider's twin's top (`TwinShapes.top_of`), 0 for a `transparent` surface and a character, `INF` for a collider with no twin yet (a wall's worth: Vision asks again rather than keep it). An instance keeps `looks_over`, a `rated` dictionary (tops by collider instance id, which the caller owns and fills only with colliders whose top cannot change) and `leave_out(rids)` once, then `cast(space, from, to)` walks without handing the exclude list to the physics server again: the view's cone casts hundreds of rays a frame this way. AI perception's `AgentVision` casts eye rays and the cone casts through an instance, so the NPCs and the view see alike. Tests: `tests/general/sight_ray_suite.gd` (the plan cast over a twin space of hand-placed pieces, `tests/_general/sight_ray_world.gd`: a wall, a table, a piece just under and just over the eye, a body with no twin, a character, the exclude list), `sight_ray_eye_suite.gd` (the eye ray), `sight_visible_parts_test.gd`.

## SeenArea

`seen_area.gd` is the part of the world the player's view shows live (`docs/player-vision.md` V11). Vision writes it when it rebuilds the cone (`set_area(polygons, bounds)`: the cone's and the bubble's polygons) and clears it when the view lifts (`clear()`). What is only ever seen inside the cone asks `reaches(center, radius)` for a disc (Art's mirror: a mover's reach; the shot layer's casings) and skips its work while the answer is false. With no area set (no view, a view lifted, the switch off) it is true, so nothing is skipped. `contains(polygon, point)` is the one point-in-polygon test (the view's `sees` asks it), an even-odd rule, not `Geometry2D.is_point_in_polygon`: the engine's says a point is inside some simple polygons it lies well outside of (a cone with many collinear corners along a wall). Tests: the native suites `tests/general/seen_area_suite.gd`, and `vision/unseen_keeps_running`; `vision/view_sees_suite` holds `sees` at a cone the engine's rule gets wrong.
