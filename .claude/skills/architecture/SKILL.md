---
name: architecture
description: The architecture map for this Godot project (Forced-Entry) — the sixteen isolated domains, the cross-cutting conventions, the whole sanctioned cross-domain interface surface, and the dependency graph. Load this BEFORE planning any change or exploring the codebase, and whenever you need to know where something lives or how two domains are allowed to talk. Points to each domain's `domain-<name>` skill for that domain's deep implementation detail.
---

# Forced-Entry architecture

A small top-down Godot 4.4 demo: a pixel-art character you walk with WASD (run on **Shift**, crouch on **C**) around a
procedurally furnished house, aiming at the mouse, with a punch on **F**, a kick on **V**, a gun (pistol, SMG or assault rifle)
that fires on left-click and reloads on **R**, stun and frag grenades thrown on left-click, items picked on **1**–**9**, object
interactions on **Space** (sit, lie, …) and, in the sandbox, a car or van to get into on **E**. The code is
organized into **sixteen isolated domains** so each can be changed on its own. The world is lit at dusk with real 2D
lights and shadows (the Lighting domain).

This skill is the **map**: the domains, the sanctioned cross-domain surface (the vital
interfaces), and the dependency graph. Keep changes inside a domain, and cross a boundary only
through the interfaces listed here. **When working *inside* a domain, also load its
`domain-<name>` skill** — that is where the deep implementation detail lives. A domain that has been split into
sub-domains keeps a short overview skill and one `domain-<domain>-<sub>` skill per sub-domain (listed in the table below); the
composition root is `domain-main`.

## The sixteen domains (one folder each under `scenes/`)

| Domain | Folder | Skill | Owns |
|---|---|---|---|
| **World Generation** | `worldgen/` | `domain-worldgen` | Picking a logical floorplan (front door, exits, hallways) and building/furnishing a house, and placing its run-down dressing (clutter, neon, where wear gathers) and the street round it with its street lamps. |
| **Objects** | `objects/` | `domain-objects` | The world's objects (furniture, walls, floors, the street), their wear and decals: their data, how they're hit/pushed, and their painters (what each piece looks like, in the run-down style). |
| **Items** | `items/` | `domain-items` | The things the character holds and the actions they perform, and what it wears (outfits: garments, armour plates). |
| **Character** | `character/` | `domain-character` (+ `domain-character-body` for `character/body/`) | The player character (built so other character types can exist). |
| **Interaction** | `interaction/` | `domain-interaction` | Object interactions: finding a reachable object and running one of its actions (sit, lie, …). |
| **Projectile System** | `projectile/` | `domain-projectile` | Shooting: penetration (the target's and the bullet's own power), a character's armour stopping a round, damage, cover, ricochet; and a grenade's burst (`Explosion`: the frag's blast and fragments, the stun's flash and bang). |
| **Physics System** | `physics/` | `domain-physics` (+ `domain-physics-blood` for `physics/blood/`) | Physical reactions: forces, knockback, deformation, debris and hit particles, a grenade burst's look (flash, fireball, smoke, scorch: `Physics.spawn_explosion`), ragdoll, and blood (its own sub-folder, `physics/blood/`). |
| **Art** | `art/` | `domain-art` | The procedural pixel-art engine every painter draws through: the canvas, the cached renderer, the shared light/tone/surface tuning. |
| **Audio** | `audio/` | `domain-audio` | The procedural sound system: every sound is synthesized in code, picked by event (gunshots per gun, bullet impacts per surface / outcome / round weight, footsteps per floor and gait, reloads, a grenade's throw, bounce, burst, a vehicle's ignition, doors, crashes, engine and skid loops) and played by the `Sound` autoload through a capped pool of positional voices; a deafened `Sound.focus` (the human) gets a muffle and a tinnitus whine. |
| **Lighting** | `lighting/` | `domain-lighting` | The world's dusk lighting, a leaf like Audio (`docs/lighting.md`): the ambient and the sky, a light per light-giving piece (declared by the piece) and per room fixture within a per-floor budget, their seeded rhythms, the shot and explosion flashes, and who stands in a light. |
| **Navigation** | `navigation/` | `domain-navigation` | Baking the house into a walkable nav map so characters can path around walls. |
| **General** | `general/` | `domain-general` | Infrastructure: input (Keybinds), saved settings (`Settings`), the event bus (`EventBus`), the log (`GameLog`), the pausable game clock (`GameClock`), despawner, camera, dev command server, shared physics-layer ids (`PhysicsLayers`), the draw-order ladder (`DrawLayers`), the light masks (`LightMasks`), the batched plain-colour drawing (`FillBatch`), the shared weighted roll (`WeightedPick`) and the match verdict (`MatchVerdict`). |
| **UI** | `ui/` | `domain-ui` (+ `domain-ui-menus`, `-hud`, `-overlays`, `-testing` for `ui/<folder>/`) | All HUDs and menus, one sub-domain per folder: menus (pre-game setup window, settings page), hud (debug player panel, match HUD, spectator inspector and its contact markers, stun screen, stack markers, the human leader's command menu and order markers), overlays (overlay registry, toggle bar, performance overlay, the squad-leaders overlay) and testing (test browser window, test result banner). |
| **AI** | `ai/` | `domain-ai` (+ `domain-ai-perception`, `-snapshot`, `-decision`, `-behavior`, `-combat`, `-coverage`, `-watch`, `-entry`, `-debug`, `-team`) | Non-player brains: one generic controller that drives every NPC. Plus `ai/team/`, the human's side of the entry radio (`PlayerStack`, interface 17) and each side's squad, its leader and its orders (`Squad`, interface 21): not a fifth sub-domain, but with a skill of its own, `domain-ai-team`. Internally split into four isolated **sub-domains** under `ai/` — perception (`ai/perception/`), decision (`ai/decision/`), behaviour (`ai/behavior/`), debug (`ai/debug/`) — around a thin orchestrator (`ai/goal_controller.gd`). A doorway's stack as the radio describes it lives once, in perception's `ai/perception/stack/` (`StackClaim` the claim's wire format and step lists, `ClaimLedger` the claims one listener has heard, `DoorStack` every slot rule and the slots' points): the seam behaviour and the team read it through (`AgentPerception.entry_stack(opening, into := "") -> DoorStack`; behaviour, the orchestrator and the team preload `StackClaim` / `DoorStack` / `ClaimLedger` themselves). `domain-ai` is the overview; each sub-domain has a `domain-ai-<name>` skill. |
| **Vehicles** | `vehicle/` | `domain-vehicle` | Drivable vehicles (a car and a van, only in the sandbox): the rigid body and its driving model, doors and seats, getting in and out (the character's `CharacterVehicleUse` component and the ride), collisions and the harm to a character struck, the dents, the vehicle art and its events. |
| **Testing** | `testing/` | `domain-testing` | Game tests: a second composition root that builds a declared world (arena, hand-laid room layout or generated house) with chosen behaviour switches, runs a test's script against it and asserts what happened; the in-game test browser + runner, and the gdUnit4 suites the headless CLI runner (`tools/run_tests.sh`) and the editor's GdUnit panel run. Test cases live in `tests/<domain>/*_test.gd`, or one folder deeper by topic (`tests/ai/entry/`), each played through its folder's wrapper suite (`*_suite.gd`); pure-logic native suites (`tests/<domain>/<name>_suite.gd`) only add to them; sandboxes to play by hand (`GameTest` scripts with no assertions) live outside `scenes/` in `sandboxes/*_sandbox.gd`. |

`scenes/main.gd` (`main.tscn`) is the **composition root** — with the Testing domain's runner
(interface 13), the only code that knows every domain. It keeps the UI flow: the setup window, the settings page, the endless run, the HUDs
and the overlay bar; the setup window's **Tests** button sends it to the test browser instead. A match itself is built by the root's
match-assembly module, **`MatchBuilder`** (`scenes/match_builder.gd`, interface 23), with its placement helper `scenes/match_spawner.gd`:
a match spec goes in (`Main.start_match(spec)` is Main's one way into a match), a match handle comes out. It asks World-Gen for a house,
bakes the nav map and lights it (`WorldLighting.light`, interface 20) right after the bake, waits until the navigation maps answer with the
new house, places the NPCs, arms and styles every character for its side (its loadout; the match's police unit or a defender's crew style
and weapon style, read off `CharacterConfig.styles`), ranks the unit and builds the squads. The Testing domain's world stages its own
worlds and binds its NPCs through the same module, and builds a declared match or declared squads with it, so a test measures the match Main
plays. Match lifecycle (Start / Watch / Endless, teardown, the Von-server wait), the placement rules and the exports are the
**`domain-main`** skill. `project.godot` autoloads only five: `Keybinds`, `Despawner`, `EventBus` and `GameClock` (all
General) and `Sound` (Audio).

## The vital interfaces (this is the whole cross-domain surface)

Everything not listed here is private to its domain. The signatures live only here: a domain's skill names the
interfaces it takes part in (by number) and describes how they're implemented.

1. **Main (through `MatchBuilder`, interface 23) → World Generation**
   - `WorldGen.generate(seed, force_plan, front_entrance_world, parent) -> Node2D` — seeds one RNG
	 for the whole run (plan pick is its first draw), prints `House: <plan>  seed: N`, builds
	 the house; every doorway is an open archway.
   - `WorldGen.get_rooms(house) -> Array` — the house's rooms as `{ key, type, rect }` dicts
	 (world-space `rect`), read from the house's `rooms` metadata.
   - `WorldGen.get_openings(house) -> Array` — the house's doorways as `{ pos, width, front, exit, rooms }` dicts
	 (world-space `pos`, `rooms` = keys of the rooms it joins; `front` = the one front entrance, on the south
	 wall, `exit` = a back/side/garage door, each with one room), read from the house's `openings` metadata.
   - The run-down dressing a generated house carries, read from its `wear`, `clutter` and `street` metadata the same way (empty
	 for a hand-laid layout): `WorldGen.get_wear(house) -> Array` — `{ room, pos, layer }` per wear cluster (0-3 a room, by a wall,
	 a corner or furniture; `pos` its world-space centre, `layer` the CanvasItem drawing that room's wear, one per room);
	 `WorldGen.get_clutter(house) -> Array` — `{ room, key, node }` per walk-over clutter piece (0-2 a room, no `key` twice; a
	 non-solid catalogue piece, never carved into the nav map); `WorldGen.get_street(house) -> Array` — `{ kind, rect, node }` per
	 piece of the street ring round the house (`kind` `street` or `sidewalk`, world-space `rect`, `node` the floor drawing it;
	 none registers a `SoundSurface`, interface 16, so footsteps out there stay `outdoor`); `WorldGen.get_streetlights(house) -> Array`
	 (its `streetlights` metadata) — `{ pos, node }` per street lamp along the front sidewalk (`pos` its world-space centre, `node` the
	 placed piece under the house: a solid, anchored metal post, carved into the nav map, its arm and head an overhang; about
	 `WorldGenConfig.streetlight_every` px apart, none within `streetlight_door_clear` px of a front or exit doorway's centre nor in the
	 strip straight out of one: a lamp that would be is dropped).
   - Read-only catalogue lookups (used by the Testing domain to place single pieces):
	 `WorldGen.object_definition(key) -> Dictionary` (for `ObjectFactory.spawn`),
	 `WorldGen.floor_definition(key) -> Dictionary` (for `FloorFactory.spawn`) and
	 `WorldGen.wall_style() -> Dictionary` (the house wall `style` for `WallFactory.spawn`).
   - `WorldGen.annotate_layout(root, rooms, doors = [])` — for the Testing domain's hand-built arenas and layouts: stores the
	 same `rooms` / `openings` metadata a generated house carries (a door on one room's wall only is the front entrance), so
	 `get_rooms`, `get_openings` and `NavBuilder` read them unchanged. No other caller writes those keys.
   `MatchBuilder` (interface 23) generates the house with its front entrance where the spec puts it, fixes draw order and builds the nav
   map from the rooms (interface 9); its `match_spawner.gd` drops each defender at a clear spot in a random room (its centre unless solid
   furniture is within `spawn_clearance` or another combatant within twice that — read off `NavBuilder.furniture_holes` — else a random
   clear point) and the invader team in one group just outside the house (`spawn_invader_team`, `docs/leadership.md` LD27: packed round a
   point against the outside wall beside the front entrance, 120 px along the wall from the doorway's centre on a side drawn from the house
   seed, no member in the doorway's straight strip; round the human invader's spot when there is one; in a house with no front entrance,
   round a point of the ring `invader_margin` out of the rooms' bounding box, drawn from the house seed) (all via `get_rooms` /
   `get_openings`), and hands every NPC the house's `get_openings` (for tactical entry) and an invader the front entrance; it never touches
   world-gen internals.

2. **World Generation → Objects** (the only way world-gen makes entities)
   - `ObjectFactory.spawn(definition: Dictionary, position, parent, opts) -> Node` — `opts`: `name`, `rotated`, `color`, `facing`,
	 and `neon` (`"cyan"` / `"magenta"` / `""`: the piece's neon trim or screen; omitted, Objects picks it per piece for a share of
	 the light-giving pieces, from where it stands). Two definition fields shape a piece beyond its look: `anchored` (true: a solid
	 piece that never moves, frozen static: no push, kick, round or blast shoves or turns it, it is still struck, dented and throws
	 debris) and `overhang` (`{ size, reach }`: an overhead part drawn beyond the footprint by the piece's painter with
	 `part: "overhang"`, `size` across x out, centred `reach` px out along its facing; a child CanvasItem named `Overhang` with
	 `get_rect() -> Rect2` (the area it draws, in its own frame), at `DrawLayers.OVERHEAD` above the characters, with no collider).
   - `WallFactory.spawn(rect: Rect2, thickness, openings, name, parent, style = {}) -> Node` —
	 `style` is the cap's look (`art`, `color`, `art_opts`); empty = a flat gray line.
   - `FloorFactory.spawn(rect: Rect2, definition: Dictionary, name, parent) -> Node` — a room's
	 floor or a piece of the street (no collider), from a floor definition (`art`, `color`, `material`, `art_opts`, and optionally
	 `sound_surface` (false: registers no `SoundSurface`, the street), `marks` (`{ seed, lane, edges }`: the street's world-placed
	 marks, curb and gutter litter, laid by Objects over the piece), `tile_from` (the point in `parent`'s space its repeating
	 tile is laid from, so neighbouring pieces share one grid) and `light_layer` (`"street"`: the piece and its canvas items on
	 `LightMasks.STREET`, interface 20)).
   - `WearFactory.spawn(rect: Rect2, floor_definition: Dictionary, wall_thickness, clusters: Array, name, parent) -> Node2D` — a
	 room's wear: World-Gen places the clusters (`{ pos, wall, seed }`: centre, the free stretch of wall `[a, b]` it is by or `[]`,
	 the seed of its marks, in `parent`'s space); Objects decides each cluster's marks (on the floor, following its pattern, and
	 often on that wall) and draws them. Built after the house's floors and walls; one node per room.
   - `WallFactory.openings_for(rect: Rect2, doors: Array) -> Array` — the `{ pos, width }` doorways that lie
	 on `rect`'s walls, as the `openings` `spawn` takes (World-Gen and the Testing domain's layouts use it).
   - `Wall.Side` — the enum inside those `openings` (callers get them from `openings_for`).
   World-Gen owns the *catalogue*; Objects owns the *field schema* and turns a plain definition
   dict into a node. World-Gen never touches an object's fields.

3. **Objects/Character/Vehicles ↔ strikers: the "hittable" contract**
   Every world object (furniture **and** walls), **the Character domain's `character.gd`** and **the Vehicles domain's `vehicle.gd`**,
   implements:
   - `get_surface() -> Dictionary` → `{ coverage, penetration, material, color }` — `coverage` is a height on a 0–100 scale: a bullet
     flies at one height and strikes what stands above it (a character's is its posture's; `docs/cover-and-stance.md`)
   - `take_hit(hit: HitInfo) -> void`
   - optionally `get_surface_at(height, direction) -> Dictionary` (the character: where its armour lies, `docs/outfits.md`): the surface a
     round flying at that height along that direction meets — `get_surface()`, or over armour that surface with the armour's `penetration`,
     `material` and `color` plus `stop_power` (round-power units: a round whose power × speed factor is below it is stopped) and
     `inner_material` (what a round that beats it strikes: flesh). The projectile asks it before `get_surface()` when it exists.
   `HitInfo` (`physics/hit_info.gd`) carries `position, normal, direction, damage,
   speed_factor, penetrated, source`, plus `has_exit` / `exit_position` / `exit_normal` (where a penetrating
   bullet left the body), `blood` (0..1, blood a bullet carries out of a character onto the next
   surface) and `height` (the 0..100 height the striker flew at, which picks a character's hit zone; −1 = none: a blast strikes the
   whole body). The projectile decides the ballistic outcome, then hands
   the struck body a HitInfo; the body decides what a hit *does to it* — an object spawns debris
   (interface 4), the character is dented, throws debris (blood, or its armour's chips when the armour stops the round) and bleeds
   (its `BloodWound` component, interface 4), a vehicle is dented
   (`Deformable`), throws debris and is shoved at the hit (`Physics.impact_impulse`) and is never destroyed. A round that meets a `stop_power` and does not
   beat it is blocked; one that beats it always penetrates, so an armoured body reads `penetrated == false` as "stopped by the armour" (it
   then takes only the armour's blunt share, no wound). The
   projectile and the grenade's `Explosion` (Projectile System: the frag's blast, `Explosion.frag`) are the strikers that call `take_hit`
   (a blast hit carries `speed_factor` 0 and `height` −1: its shove is the grenade's own `blast_impulse`, applied through the pushable contract below, a
   character's through `blast_push`); a melee punch shoves through the "pushable"
   contract below, deals its damage through `take_damage(amount)` (the character's plain damage entry, no HitInfo;
   tests wound a character with it too) and does **not** deform, and reads `get_surface()` only for the struck
   `material` it posts. `Explosion` finds the characters under the world by the group `characters` (interface 7), reads their `is_dead`, `facing`, `get_surface()`, and calls
   `take_stun` / `take_damage` / `blast_push` / `take_hit` on them, and `apply_impulse` on a pushable (capped by `get_mass()`): the sanctioned surface. Its
   cover rule (G7, `docs/grenades.md`) is published as two read-only line queries the AI's perception asks of a grenade, so the AI keeps no copy:
   `Explosion.shields(space, burst, p, height, exclude, cover_reach := INF) -> bool` (whether a wall, or a piece of furniture whose `coverage` is
   above `height`, stands between a burst and a body `height` tall at `p`; with a finite `cover_reach`, a stun's flash, a piece only when `p` is
   within that many px of it) and `Explosion.first_stop(space, a, b, height, exclude) -> Dictionary` (the first wall or piece on the line that
   stops it for that height, as its ray hit, or `{}`). An object also carries `object_name` (its display name), which the AI's wording reads.

4. **Objects/Character/Vehicles → Physics** (objects, the character and a vehicle compose physics; Physics is a leaf domain)
   - `Knockback` (Node child): RigidBody2D adapter — configures its parent body and owns
	 `apply_impulse(v, at_world)`; `mass` (the body's mass, which its owner sets from the catalogue `weight` before `_ready`).
   - `Deformable` (Node child): `record(hit, turn = 0.0)`, `impacts`, `damage_total`, `changed`
	 signal (`turn`: the body's drawn turn beyond its node rotation; the character passes its facing), and three per-body knobs its owner
	 sets: `max_depth` (the deepest one dent caves, px), `allow_chunks` (a hard hit carves a missing piece) and `max_impacts` (how many
	 dents it remembers), each defaulting to `PhysicsConfig.deform_*` (the character sets its softer flesh values from `CharacterConfig`). A
	 vehicle composes one (no `Knockback`: it is its own `RigidBody2D`) with chunks off and does not rebuild its collider from the dents.
   - `Deformation` (static): silhouette/collider polygons + drawing (`draw_shape` and
	 `draw_wall` optionally textured — `draw_shape` also turned by `texture_angle`, its hit marks
	 optional for a caller drawing them over later layers with `draw_marks` — so pixel art is drawn
	 through the dented silhouette). The polygons are `base_ring(shape, size)` (a primitive's undented ring),
	 `shape_polygon(shape, size, impacts)` (a piece's or the character's dented silhouette, cached), `wall_polygon(a, b, thickness, impacts)`
	 (a dented wall segment), `is_valid_polygon(poly)` (callers skip a self-touching one that frame), `convex_pieces(polygon)` (the
	 convex pieces a dented collider is rebuilt from, as their points) and `shapes_of(pieces)` (their `ConvexPolygonShape2D`s); and
	 `cut_shape(shape, size, impacts)` / `cut_wall(a, b, thickness, impacts)` -> `[polygon, pieces]`, a dented silhouette and its pieces
	 computed without the caches: all pure, so they may run on a worker thread). An impact record (the dicts in `impacts`) is built by
	 `new_impact(pos, inward, damage, blood, max_depth, allow_chunks)` and kept by `push_impact(list, impact, max_impacts)` (oldest
	 dropped past the cap): `Deformable.record` and Objects' wall, which keeps an impact list per segment, both build through them. `NO_COLOR` is the sentinel a caller passes to take a
	 drawing call's default colour. `darken(damage_total) -> float` is how far `draw_shape` darkens a shape that has taken that
	 damage (`Color.darkened`'s weight; a textured shape is white darkened by it), for a caller that draws a textured shape's polygon its
	 own way (the character's kept meshes, `domain-character-body`) in the same colour.
   - `Physics.impact_impulse(hit) -> Vector2`, `Physics.spawn_debris(world, hit, surface)` (objects, the character and a vehicle)
	 `BloodWound` (Node child, character: `record(hit)` on a hit throws a splatter spray and owes drips, one
	 `BloodSplat` every `BloodConfig.drip_interval_min..max` s from the body's blood origin; `stop()` on death)
	 and `Physics.bleed_out(parent, source, exclude)`
	 (a dead character, once its body comes to rest: one slow, wide pool). A blood source may expose
	 `blood_origin() -> Vector2` (where its blood leaves it, in world space); pools emerge there instead
	 of at its position, so a fallen body bleeds from where it lies. Master switches:
	 `BloodConfig.enabled` off → `BloodWound.record` / `bleed_out` spawn nothing (`bleed_out` returns null);
	 `PhysicsConfig.debris_enabled` off → `spawn_debris` spawns nothing. Splatters and bleed-out
	 pools are added with readable names (`BloodSplat`, `BloodSplat2`, … / `BloodPool`, …).
   - `BloodField` (static registry, Physics-internal: `BloodSplat`/`BloodPool` register themselves) /
	 `BloodDecals` (a batched layer under a world node, `BloodDecals.layer(parent)`) /
	 `BloodFootprints` (Node child, character: `step(foot, at, direction, length, width, inner, speed)` on
	 each footfall prints a sole if the foot is carrying wet blood) / `BloodSmear` (Node child, objects:
	 `set_footprint(local_polygon)`, then drags blood out of a puddle as feathered, wandering ribbons while the body slides).
	 Both need `BloodConfig.enabled` and their own switch (`footprints_enabled` / `smear_enabled`).
   - `BloodSurface` (static registry): `register(rect, groove: Callable(world, half_width) -> 0..1, porous) -> id` /
	 `unregister(id)` — Objects' `Floor` registers its room so a bleed-out flow runs along grout/seams, and rugs register as porous
	 (blood sinks into carpet and rugs, `is_porous(pos)`)
	 (`resistance(pos)` is read only by Physics' `BloodFlow`; `BloodConfig.surface_flow` off ignores floors).
   - `Ragdoll` (`RefCounted`, character on death): a generic 3D point-mass body over the floor plane
	 (x/y + height z). Built with `add_point(at, radius, mass)`, `add_bone(a, b)` / `add_rigid(indices)`,
	 `add_frame(origin, up, right, forward_hint)`, `add_swing(frame, joint, child, rest, limits)`
	 (cone limit) and `add_hinge(frame, parent, joint, child, rest, bend, min, max, slack)` (one-way
	 hinge), seeded with `push(i, v)`, stepped with `step(delta, space, origin)` until `asleep`; read
	 with `point(i)` / `point_count()` / `frame_basis(f)`; `exclude` lists colliders its wall sweep
	 ignores. The Character domain owns the humanoid skeleton built on it.
   - `Physics.spawn_explosion(world, at, kind)` (`kind` `&"frag"` / `&"stun"`; called by the Projectile System's `Explosion`): the look of a
     grenade's burst, `ExplosionFx` nodes `ExplosionFlash` and `ExplosionFireball` (frag only: a stun's white flash is the Lighting domain's flash
     light, interface 20) and `ExplosionSmoke`, which draw themselves in stepped
     pixel rows and free themselves (Despawner-tracked), and a frag's scorch mark in the world's `ScorchDecals` layer (batched like `BloodDecals`,
     capped by `Despawner.max_scene_objects`). Looks and timings are `PhysicsConfig.explosion_looks`; `PhysicsConfig.explosion_fx_enabled` off
     spawns none of it. `Ragdoll.wake()` restarts a sleeping body's clocks so an explosion's push is simulated (the character's `blast_push`).
   - `PhysicsConfig` (`class_name` static holder, see below) — the deformation tuning
	 (`deform_depth_per_damage`, `deform_max_depth`, `deform_chunk_damage`, `deform_max_impacts`,
	 `deform_update_collider`) that Objects reads directly when recording damage, and the ragdoll
	 solver's `ragdoll_*` tuning (read only by `Ragdoll` itself).
   Physics imports nothing from other domains but General's infrastructure (`Despawner` for debris, hit particles, blood and
   the explosion effects, `PhysicsLayers` for `PhysicsConfig.wall_mask`, `DrawLayers` for its z knobs, `FillBatch` for its many
   plain-coloured shapes).

5. **"Pushable" contract** — anything shoveable exposes `apply_impulse(v, at = Vector2.ZERO)` + `get_mass()`,
   `at` the contact offset from the piece's origin (in world orientation; omitted = a central shove).
   Furniture is a `RigidBody2D`, so its native methods (this is their signature) serve the contract and a shove off
   the centre turns it; the character ignores `at` and integrates knockback into locomotion. Used by
   furniture→character contact transfers, bullet impacts, an explosion's blast (central), and the character's punch,
   kick, leg press and walking push (each at its contact point). A vehicle (`vehicle.gd`, a `RigidBody2D`) is pushable through
   its native methods too (a bullet shoves it at the hit); it shoves furniture through the physics solver and a character it
   strikes through the character's `apply_impulse` (interface 19), and a piece pressed against a character it strikes (or
   that it presses against one) through the piece's `apply_impulse`, read against its `linear_velocity`. To carry a piece at walking pace instead of launching it,
   a pusher may also read a `RigidBody2D` pushable's `linear_velocity` / `angular_velocity` and the inverse inertia the
   physics server holds for it (`PhysicsServer2D.body_get_direct_state`), and cap its shove by them; a pushable without
   them (a character) is shoved uncapped.

6. **Items ↔ Character**
   `Item` (`items/item.gd`): `display_name`, `reach`, `hand_stance(hand) -> StringName` (how that
   hand is held — the name of a `CharacterConfig.stances` entry: `relaxed`, `guard`, `aim`, `support`;
   the character's pose eases each hand to it and the rig bends the arm to reach it; the character itself overrides it with `run` while running
   and, while blind, puts the free hand in `eyes` and a gun's weapon hand in `one_hand`, `docs/grenades.md` G13), `primary(user)` (F), the melee hooks the character's hands read, `strike_direction(aim, amount)` / `strike_end(aim, amount)` / `strike_forward()` / `strike_short()` / `strike_support_gap()` / `strike_tempo()` (a long gun's punch swings it nearly across the body, butt leading; `GunItem` overrides `strike_ahead()` / `strike_turn()`, from which the direction, end and forward follow, and the short, support gap and tempo),
   `secondary(user) -> bool` (LMB; true = a round left the barrel), `tick(delta)` (the item's own clocks; the character ticks
   every item it carries each physics frame), `is_automatic()` (holding the trigger keeps firing), `weapon_hand()`,
   `muzzle_ahead()` (px past the weapon hand where bullets leave; negative = the character's `CharacterConfig.muzzle_ahead`),
   `raises_at_contact()` / `raised_stance(hand)` (a long gun's barrel against a wall or object: held pointing up, cannot fire),
   `draw_weapon(canvas, user)`, `drop(user, velocity) -> Node2D` (let go
   as its user dies: a gun leaves a skidding `DroppedItem` in the world, the default leaves
   nothing; the dropped node's `DroppedItem.item` is that very item) and `draw_dropped(canvas, at, angle, modulate, opts)` (how it looks lying loose; `opts.flip`
   is which side landed up), and `drawn_art() -> Array` (the textures its last draw, `draw_weapon` or `draw_dropped`, painted: every call in
   the frame it was last drawn, e.g. a lying item's shadow and art; pixel art is cached by what it depicts, so a test compares drawings by
   them, like `CharacterVisuals.drawn_art()`). The character
   calls `drop` on death and removes the item from its inventory if a node came back. `ItemRegistry.create(id, rounds, magazine)` / the slot ids `UNARMED_SLOT`, `FISTS_SLOT` and `KEY_SLOT` (the AI selects its fists with `ItemRegistry.FISTS_SLOT`, and names its grenades by `STUN_SLOT` / `FRAG_SLOT` (`AgentThrow.SLOTS`, the bang entry's stun, or the frag of an entry its leader ordered in with one); the debug panel lists the grenade rows through `LoadoutConfig.grenade_options()`; the UI's command menu reads a teammate's stuns and frags as `item_count(ItemRegistry.STUN_SLOT)` / `item_count(ItemRegistry.FRAG_SLOT)`; an interaction's `requires_item` is a slot id, the key's) /
   `default_inventory()` / `inventory_for(slots, rounds, magazine, grenades, style := &"police")` (an optional `magazine` type the gun starts loaded with; `grenades` = slot -> count; `style` the weapon style stamped on every item made) /
   `create_magazines(type_ids)` (full `Magazine`s for those `MagazineConfig` types: the character's spare-magazine store) /
   `random_gun_slot(rng)` / `loadout_for(gun_slot, stuns, frags)` / `spares_for(gun_slot)`. The grenades (`docs/grenades.md`) are `Item`s too: slots `ItemRegistry.STUN_SLOT` 7 / `FRAG_SLOT` 8, a *count*
   carried (`Item.uses_left()`, -1 = unlimited for every other item; `Item.is_throwable()`; `Item.throw_stats() -> Dictionary` (`{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }` for a grenade, from its `GrenadeConfig` row via `GrenadeConfig.stats_of`; `{}` default; `ThrownGrenade.throw_stats()` answers the same for a live one); `ItemRegistry.create(slot, count)`), thrown by `secondary` after a `windup` in the `throw` stance (the `GrenadeItem` posts `&"throw"` as it leaves the hand) as a `ThrownGrenade`
   (a world node in the group `live_grenades`: `kind`, `fuse_left()`, `throw_stats()`, `thrower`, and `item`, the grenade item that draws it, in
   the thrown item's weapon style) that posts `&"grenade"` events and, when its fuse ends, calls the Projectile System's `Explosion.frag` / `Explosion.stun` (`(at, world, source, row)`, `row` = its `GrenadeConfig` row). `LoadoutConfig` (static holder) is what the match
   builder (`MatchBuilder.arm`, interface 23) hands a character: `options()` (plain dicts for the setup window: `RANDOM`, then every `GunConfig` gun with its magazines),
   `grenade_options()` (the Stun and Frag rows: `{ id, label, slot, max }`; a loadout names their counts `stuns` / `frags`, 0..3), `grenade_counts(loadout)`,
   `outfit_options()` (the outfit rows: `[{ slot, label, choices: [{ id, label }] }]`, one per slot, a "None" choice `id` `&""` first where the slot may be empty; the
   vest choice that holds plates marked `plates: true`, each plate row `plate: true`),
   `normalize(loadout)` (a `{ weapon, magazine, spares, stuns, frags, outfit }` dict made valid; `outfit_of(loadout)` fills every outfit slot, a missing or unfitting
   id taking `default_outfit`'s: plain clothes, and clears both plates unless the vest holds plates), `apply(character, loadout, rng, style := {}) -> gun id` (arms it through `Character.set_loadout` and dresses it in the whole
   outfit through `Character.set_outfit`; `style` = how it is all drawn, looks only: `look` / `seed` /
   `rank` passed to `Character.set_style`, absent = the character's style left as it is, and `weapon`, the weapon style passed to
   `Character.set_loadout`, absent = `police`) and `random(rng)` (with `random_outfit(rng)`, drawn after the gun). **Weapon style:** every `Item` has a `style`
   (`&"police"` for the invaders, `&"scrap"` / `&"pipe"` for a defender; default `police`), the look it is drawn in, never what it does: a gun
   or grenade draws its `GunConfig` / `GrenadeConfig` row's `looks` row for it (the painter and its colours; `GunConfig.look(gun, style)` /
   `GrenadeConfig.look(kind, style)`, `default_style` `police` for a style it has no row for), held, dropped (either side up) and, for a
   grenade, in flight and at rest; a dropped gun is the item it was, and a thrown grenade's `item` takes its thrower's item's style. **Outfits** (`docs/outfits.md`): `OutfitConfig`
   (static holder: the garment and plate rows, a garment's `looks` per character style (`zenitex`, `trauma`, `merc`, `borg`: its `kind` and a `color`
   or a `palette` name, `default_style` for a style it has no row for), `GARMENT_SLOTS` / `PLATE_SLOTS` (String keys `head body vest pants feet
   front_plate back_plate`), `choices(slot)`, `fits(slot, id)`, `name_of(slot, id)`) and `Outfit` (`RefCounted`, one character's worn set: `set_ids(ids)`, `ids()`, `worn(slot)`, `condition(slot)`,
   `layer(zone, side)` (the armour a round meets there: `{}` or `{ stop_power, penetration, material, color, blunt, reduction, blast, plate }`), `wear(zone, side, damage)`,
   `weight()`, `look(style)` (what the art draws, in that character style), `view()` (what the UI shows) and `revision` (bumped by every change, which the art watches)). The
   character API an item may call: `facing`, `is_dead` and `current_item()` (a grenade gives up its windup when its user dies or switches away), `punch(hand)`, `punch_amount(hand)` (0..1, how far that hand is thrown: a long gun swings round by it),
   `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)` (the held item's `muzzle_ahead()` past the hand),
   `world_root()` (also read by the AI: the characters it perceives are the group `characters` under it), `report_shot(body, dmg)`, `kick(hand, strength := 1.0)` (recoil: throws that hand back; `strength` scales it),
   `weapon_facing()` (the drawn weapon direction, trailing the aim; shots still use `facing`), `aim_target()` (the aim point a grenade is thrown to) / `aim_sway()` (rad, the stun's wandering turn of every shot and throw; 0 unstunned), `one_handed()`
   (a held gun is in the weapon hand alone, the free hand over the eyes while blind: a gun's round then adds its row's `one_hand_spread_deg`) and `weapon_raise()` (0..1, how far
   a long gun is raised off a wall, for its art). **Guns:** every firearm is a `GunItem` (`items/gun.gd`) tuned by its row in
   `GunConfig` (damage, `fire_interval`, `automatic`, `penetration`, `muzzle_speed`, `spread_deg`, `one_hand_spread_deg`, `recoil`, its default magazine,
   `raises_at_contact`); `PistolItem` / `SmgItem` / `RifleItem` supply only their sizes and hold (the look is the row's `looks`, above). **Ammo:** `Item` has inert hooks
   `rounds_loaded()` / `ammo_capacity()` (-1 = no ammo), `reload_time()`, `can_reload(user)`, `finish_reload(user)` and a
   `reloading` flag the character sets. **Gun identity:** `gun_id()` (the `GunConfig` id, `&""` for a non-gun) and `round_power()`
   (the penetration power of its rounds, 1 for a non-gun), which the character reads for its `reload` event. A `Magazine` (an `Item` subclass, types in `MagazineConfig`, each tied to one `gun` id,
   with its own capacity and optional `reload_time`) is carried
   by the character, never held or selectable; a gun loads one and each shot spends a round. For a reload
   an item calls the character's `best_magazine(gun)` / `take_magazine(gun)` / `stow_magazine(m)`. Items reach into the
   Projectile System in two places. A gun fires through `ProjectileSpawner.spawn(position, direction, parent, ignore = null, item_damage = 0.0,
   muzzle_speed = -1.0, penetration = 1.0, max_range = -1.0, strikes_shooter = false) -> Node` (the round; the gun connects its
   `hit(body, damage)` signal to its user's `report_shot`) and ejects a case through `CasingSpawner.spawn(position, direction, parent) -> Node`;
   a `ThrownGrenade` calls `Explosion.frag` / `Explosion.stun` (above).

7. **Character ↔ Controller** (enables non-player characters)
   The character reads intent from a pluggable **controller child** — any node with
   `control(character, delta)`. The controller writes `move_input` / `aim_point` / `run_input` (hold run: a
   faster pace that spends stamina while moving, dry = walk until it refills; only a standing character runs) and calls the
   character's action API: `set_posture(p) -> bool` (`stand` / `crouch`; idempotent, so a controller may write it every frame; the player's C calls
   `toggle_crouch()`), `melee()` (F), `leg_kick() -> bool` (a right-leg kick along the facing, whatever is held; false while dead, crouched, busy or a kick is under way; reads `is_kicking()`; **not** the recoil `kick(hand, strength)` above), `shoot() -> bool` (LMB; true = a round left the barrel; ignored while running, reloading,
   or with a long gun's barrel against a wall or object, and a gun holds back between rounds per its fire rate; a controller re-presses it
   every frame while the trigger is held when `is_automatic()`), `reload()` (R: a timed swap to
   the fullest carried magazine, taking the item's `reload_time()`; refused while running or busy and cancelled by running, switching items or
   dying), `select_slot(id)`, `try_interact()` /
   `interact_with(object, id)` / `end_interaction()`, `try_use_vehicle()` (E: get in or out, interface 19), and may read `damage_taken()` (accumulated hit
   damage, for injury sensing), `posture()`, `is_running()` / `stamina_fraction()`, `run_speed()` / `walk_speed()` (px/s standing, running / walking, slower while stunned or weighed down by the outfit: how an AI works out whether it gets somewhere in time) / `posture_coverage(posture)` (the body's height on the coverage scale in `stand` / `crouch`, what furniture must stand above to shield it), the ammo reads `ammo(slot := -1)` / `ammo_capacity(slot)` / `can_reload(slot)` /
   `spare_magazines()` / `is_reloading()` (the held item for slot -1; -1 rounds = no ammo), `item_name(slot := -1)`, `current_item()` / `current_slot()` / `item_reach()` / `has_item(id)` (the held item, its slot and reach, and whether a slot is carried — what the AI's wording, the debug panel and `requires_item` interactions read), `is_attacking()` (a punch swing is under way), `gun_slot()` (the
   gun it fights with: the held item if it takes ammo, else the lowest such slot, else −1), `weapon_blocked()` / `weapon_raise()` /
   `is_automatic()`, `item_count(slot := -1)` (a grenade slot's count, 1 for any other item, 0 for none), `throw_stats(slot := -1)` (what a grenade carried in the slot tells its holder, `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, `{}` for any other item or an empty slot: how the AI reads a grenade's numbers, instead of keeping a copy), `throw_release_offset(slot := -1)` (where a grenade leaves its hand when it throws one standing: the hand of its `throw` stance, as `Vector2(px ahead of the body centre, px to its right)` in its own frame; the AI judges a lob from there, instead of keeping a copy of the stance), `aim_target()` (the swayed aim point a grenade
   is thrown to, interface 6: where the AI expects its own grenade to come down), `set_loadout(slots, hold_slot, spare_types, loaded_magazine := &"", grenades := {}, weapon_style := &"police")` (carry only those slots, holding one, with those spare
   magazines, the gun loaded with that type when it fits, a grenade slot with `grenades[slot]` of them, every item in that weapon style (`Item.style`): how `MatchBuilder.arm` arms a spawn with its side's loadout, interface 23);
   how it is drawn (`docs/outfits.md` O15, looks only): `style` (exported; a `CharacterConfig.styles` key: `zenitex` / `trauma` the police units, `merc` / `borg`
   the defenders' crew; `zenitex` when never given one), `look_seed` (exported: its own variety within the style), `rank` (a police unit's: 0 trooper, 1 sergeant,
   2 lead) and `set_style(style, seed, rank := 0)` (`LoadoutConfig.apply` calls it);
   what it wears (`docs/outfits.md`): `set_outfit(ids)` (`{ head, body, vest, pants, feet, front_plate, back_plate }`, replacing the whole outfit; `LoadoutConfig.apply`
   calls it), `outfit() -> Outfit` (what its art reads `look(style)` and `revision` from) and `outfit_view()` (each garment slot -> its name, "" for none; each plate slot ->
   `{ type, name, condition }`: what the debug panel and the spectator inspector list), and where a round strikes it: `hit_zone(height)` (`feet` / `legs` / `torso` /
   `head` by height over the posture's coverage; `&""` below 0) and `hit_side(direction)` (`front` / `flank` / `back` against the shoulders' facing), with
   `get_surface_at` (interface 3); an outfit's weight slows `run_speed()` and every pace;
   while the character rides a vehicle (interface 19, from the E press to its last step out) `is_busy()` is true, and `current_item()` is null
   while it is posed by the ride (the item put away);
   the stun (a grenade's flash and bang): `take_stun(blind, deaf)`, `is_blind()`, `is_deaf()`, `stun_level()` (0..1 disorientation: slowed to `CharacterConfig.stun_speed`, no running, aim sway;
   drawn hunched and staggering, the free hand over the eyes while blind), `one_handed()` (blind, a held gun is in the weapon hand alone: its rounds spread wider), `stun_view()` (`{ blind, blind_total, deaf, level }`, for the UI) and `blast_push(from, impulse)` (an explosion's shove: knockback, or the fallen body's ragdoll thrown) and `faction` (allegiance tag, for AI hostility). The AI also reads
   another character's `facing`, `damage_taken()`, `is_reloading()`, `posture()`, `current_item()` and `faction` — but only while it can SEE that character
   (aim, visible wounds, a reload in progress and the posture are things it perceives); the exceptions are three reads of an unseen character's `faction`,
   which stand for knowing who its own team is: the faction of a character whose footstep it hears (the `footfall` event's `character`, interface 10), so its
   own side's steps are never taken for a stranger's (`docs/hearing.md` H1); of the attacker of a hit on or near it (the `hit` event's `attacker`), so an
   ally's round striking nearby is not fire at it; and of the thrower of a grenade that bursts (the `explosion` event's `attacker`), so it knows a burst as its
   own team's (`docs/grenades.md`). A member also knows its squad unseen (interface 21, `docs/leadership.md`): who is in it and leads it, and an
   order names its recipients and its side (`to`, `faction` on the `&"order"` event), so an NPC takes only its own side's orders that name it; and
   its squad reads the leader's `global_position` and `facing` (and its members' `global_position`) unseen, to lay the spots its followers keep
   to and the leash they fight within (LD19 to LD23). Every character joins the group `characters` in its `_ready`:
   that group is how the AI (its perception and tactics), the Projectile System's `Explosion` and a vehicle tell a character in the world, so it
   is part of this interface and is not renamed lightly.
   `player_controller.gd` is the human one and
   is the only *gameplay* file that touches `Keybinds` (observers read one thing each: Main `MENU`; the test runner `MENU`, `PAUSE` and the camera actions;
   the spectator inspector `PAUSE`; the human leader's command menu `COMMAND`, and `MENU` only to close itself; the camera its pan and zoom actions). Signals:
   `hit_landed(body, damage, hand)` (hand 0/1 = melee punch, hand 2 = leg kick, hand −1 = shot),
   `died` (with `is_dead` / `health` to read; a dead body
   falls as a ragdoll, leaves layer 1 and draws beneath the living). Observers (debug HUD, match HUD, camera) attach by
   exported node path and read only the public API/signals; the AI controller joins the group `npc_controllers` in its `_ready`, and
   the HUDs find an NPC's controller as its child in that group (the UI's `hud_probe.gd`; a player's controller is never one). The AI controller also exposes
   `current_act()` (its live decision path as ids, e.g. `combat/t_12/flank/side_left`) and
   `debug_status()` (the same path as labels, every level: `COMBAT - Intruder - FLANK - their left
   side (kitchen)`), `debug_state() -> Dictionary` (the deep snapshot the dev command server's `ai` verb dumps), `debug_zones() -> Array`
   (the tactical points the spectator inspector picks from; it rings the one it describes on the NPC's tactics overlay through the
   controller's `debug_focus(point)` / `debug_clear_focus()`), the draw-only overlays' `debug_*` getters (e.g. `debug_entry_view()` for the tactical-entry ones), `known_contacts_for_display()` (the spectator inspector's contact list) for those observers to show. Each overlay is a child of the NPC with a `show_<x>` export named in the UI's `OverlayRegistry` (`show_grenades` reads `debug_grenades()`: `{ known: [{ point, kind, fuse_left, fuse, radius, source }], escape: Vector2 (INF: none), throw: {} }`);
   `MatchBuilder.set_overlay` (interface 23: Main's match and the Testing world's alike), the spectator inspector and the Testing world's
   actor spawn set those flags by that name, so an overlay's export is part of this surface. Every NPC is the same generic goal-driven agent
   driven by `ai/goal_controller.gd`; the defender (`ai/npc_defender.tscn`) and the invader
   (`ai/npc_invader.tscn`), both inherited from `ai/npc.tscn` (itself an inherited scene of the controller-less
   `character/character_base.tscn`), differ only in data authored on the scene —
   a plain-language `goal` plus generic primitives (hostility rules, pursuit, territory) and
   decision-tree config. Its composer injects only `rooms` and `openings` (and `entry_point`), by the one bind rule `MatchBuilder.bind_npc`, before the
   NPC joins the tree (interface 23; the controller found by its contract, the child with `control` and `rooms`), and its side's `squad`
   (`MatchBuilder.bind_squad`, interface 21); the AI finds and categorizes
   the characters it perceives by sight. Von walks a data-driven DECISION TREE ranked against the
   goal — a broad mode (combat / reload_quiet / investigate / search / idle), then a tactic (engage / flank / advance /
   retreat / reload / locate …), then a concrete option (a place, a firing spot, an object) — one `choice`
   request per level, ending in a behaviour primitive (move / engage / melee / interact / hold / reload / entry / throw / defend / ambush / follow) — no
   per-goal or per-NPC-type code. `goal_controller.gd` is only the thin orchestrator; the work is split
   across four isolated AI sub-domains (perception / decision / behaviour / debug). See the `domain-ai`
   overview and its `domain-ai-<name>` sub-skills.

8. **Interaction ↔ Character & Objects** (kept deliberately isolated so it iterates alone)
   The character composes a `CharacterInteraction` component (`interaction/`) and exposes only
   opaque forwards: `try_interact()` (the player's **Space** toggle), `interactions_in_reach()`
   and `interact_with(object, id)` / `end_interaction()` (for a controller/AI), `is_busy()`
   (movement/actions lock) and `interaction_label()` (HUD). It discovers objects through the
   **interactable contract** — every world object implements `get_interactions() -> Array` (plain
   data dicts: `id`, `label`, optional `move_to` / `requires_item`), advertised via the optional
   `interactions` object field. The character never learns what an interaction *means*. The component touches only its host's
   `global_position` (a `move_to` action snaps the body onto the object and back), `facing` (the reach query sits ahead of the body, on
   `PhysicsLayers.SOLID`, interface 11, excluding the body's own `get_rid()`), `aim_point` (the player's Space picks the reachable object
   nearest the cursor) and `has_item(id)` (an action's `requires_item`), and takes Godot's own collision exception
   (`add_collision_exception_with`) with the object a `move_to` puts it on. When an interaction ends the component hands
   the object to the character's `keep_clear_of(body)`, which keeps their collision exception until the character's circle no longer
   overlaps it (then drops it; a freed body is forgotten), and calls `stop_clearing(body) -> bool` when the character goes straight back
   onto that object, so its exception stays.

9. **Main / Testing (through `MatchBuilder`) / AI → Navigation** (leaf: builds the map, everyone else just pathfinds)
   - `NavBuilder.build(house, rooms, parent, agent_radius=14.0) -> NavigationRegion2D` — bakes
	 one `NavigationRegion2D` whose walkable area is the house footprint plus an outdoor ring minus the house's
	 **static** wall colliders (doorways stay open) **and minus each solid furniture footprint**
	 (baked in as a hole: every `RigidBody2D` with a collider, an anchored piece frozen static among them; walk-over decor has
	 none), so paths route around furniture.
   - The re-bake is the Navigation domain's own: its `nav_updater.gd` (built by `MatchBuilder.stage`, below) re-carves the furniture holes in place at the
	 pieces' **current** positions, the planning bake on the NavigationServer's worker thread. `NavBuilder.rebake` / `rebake_async` /
	 `rebake_steering` are test-facing seams, not part of this surface (`domain-navigation`).
   - `NavBuilder.furniture_holes(house) -> Array` — the carved furniture footprints (the anchored pieces' included) as world-space
	 polygons: what the Navigation domain's draw-only `nav_debug.gd` overlay draws and its `nav_updater.gd` watches for a
	 moved piece, and what the match builder's `match_spawner.gd` keeps a spawn's clearance from.
   - **Characters at rest are holes too, on a second map.** `NavBuilder.character_holes(root) -> Array` (the footprints of the
	 living characters at rest under the region's parent), `NavBuilder.OBSTACLE_MARGIN` (the px every carved footprint is grown by: the AI's
	 entry geometry grows a body at rest by it to match the steering map's carve), `NavBuilder.steering_map(planning_map) -> RID` (a map of its own, holding
	 the furniture *and* those holes; named from the frame `build` returns, before it has synchronized (`ready` tells when it answers);
	 invalid when the world has none) and `steering_region(region)` (re-baked by `nav_updater.gd` too). The world's own map stays furniture-only, because the AI
	 plans on it; the AI's `Locomotion` puts its `NavigationAgent2D` on the steering map for a walk that goes round a body at rest it
	 knows of (the map carves every one; what a walker accounts for is the AI's rule, `domain-ai-behavior`).
   - **Map queries**, what the AI asks of a baked map when it weighs a point or a route: `NavBuilder.ready(map) -> bool`
	 (valid, synchronized at least once and has taken in every region `build` put on it, so a map still showing the previous
	 navmesh counts as unbaked), `snap(map, p) -> Vector2` (`p` on the navmesh; unchanged before the bake),
	 `route(map, from, to) -> PackedVector2Array` (the navigated waypoints; a straight segment before the bake or with no
	 path) and `path_length(path) -> float`. The AI's locomotion, tactics geometry, entry geometry, grenade escape plan, snapshot options and
	 routes overlay, the squad's follow spots (`snap`), the human's `PlayerStack` (how near a doorway it is) and the match builder's wait for the
	 maps (`MatchBuilder.stage`, interface 23: `ready` on the planning map and the steering map before any NPC is placed), all go through these, so the "is the map baked yet" rule lives in one place.
   - **Avoid maps**, for a walk that keeps out of some stretch of floor (the AI's doorway views, `docs/tactical-entry.md` E18):
	 `NavBuilder.avoid_map(region, key, holes) -> RID` (`region`: the planning region `build` returned, found from a world map by
	 `NavBuilder.planning_region(planning_map) -> NavigationRegion2D`; `holes`: world-space polygons; `key` names the set): a map of its
	 own with the planning bake plus those holes, baked on the NavigationServer's worker thread, cached by `key` (re-baked when the
	 planning bake has been redone since), freed by the next ask for another set once nobody has asked for it for 20 s, and with its
	 world, and `ready` as any map. The world's map and the
	 steering map are untouched. The AI's `Locomotion` walks it and `AgentDoorViews.walk_route` measures on it.
   `MatchBuilder.stage` (interface 23: Main's match and every test world alike) calls `build` once after the house is built (and builds the
   `nav_debug.gd` overlay and the `nav_updater.gd` re-baker right after), then, with the spec's `wait_nav` (on by default), waits until both
   maps are `ready`. Any `NavigationAgent2D` then pathfinds
   against the global map automatically — the AI's locomotion sets `target_position` and steers at
   `get_next_path_position()`. It does **not** enable RVO avoidance: instead the navmesh is
   **periodically re-baked** (`nav_updater.gd`, only when a piece has moved) so furniture that gets
   shoved around is re-carved as a hole at its new spot and paths route around scattered objects.
   Between re-bakes (and for non-solid decor, never carved) a displaced piece is simply bulldozed by
   the character's push physics.

10. **Any domain ↔ General (EventBus)** — a generic decoupled notification bus (General autoload).
    - `EventBus.post(topic: StringName, data: Dictionary)` — broadcast an event.
    - `signal posted(topic, data)` — listeners connect and filter by `topic`.
    These topics are in use:
    - `&"hit"`: the Projectile System posts one per damaging hit and the Character one per landed
      punch (`{ position, victim, direction, damage, attacker }`; `attacker` = the striking
      character or null). The AI controller consumes it for combat awareness, hostility ("attacked
      me") and gunfire heard farther off. It also says *how* the
      hit met the surface, for the Audio domain: `outcome` (`&"blocked"` / `&"penetrate"` /
      `&"ricochet"` for a bullet, `&"punch"` for a fist or a kick, `&"blast"` for a frag's blast: posted by the Projectile System's
      `Explosion` with the thrower as `attacker` and `speed_factor` 0, which Audio does not voice as an impact: the burst has its own sound), `material` (the struck surface's, `""` for a
      wall; for a round armour stopped, the armour's: `metal`, `ceramic`, `composite`, `fabric`; for one through it, the flesh under it), and for bullets
      `speed_factor` and `power` (its penetration power). Its `damage` is the striker's, before the struck character's zone, blunt and reduction
      scaling (`docs/outfits.md`; the same for `hit_landed` / `report_shot`). A shot that flies over cover posts nothing.
    - `&"explosion"`: `Explosion.frag` / `Explosion.stun` (Projectile System) post one when a grenade goes off (`{ position, kind` (`&"frag"` / `&"stun"`)`,
      attacker` (the thrower, or null)`, radius` (the blast radius of a frag, the flash radius of a stun)` }`), before the burst's hits and stuns, for
      Audio (`explosion/<kind>`), the camera (General: `Camera2D.offset` shake by distance and kind) and the AI (`docs/grenades.md`). The grenade's other topics: `&"throw"` (Items, the `GrenadeItem` as it leaves the hand: `{ position, kind, attacker }`), `&"grenade"` (Items, `ThrownGrenade`:
      `{ position, kind, stage }` with stage `bounce` / `rest`) and `&"stun"` (Character, `take_stun`: `{ character, position, blind, deaf }`). Audio voices the
      `throw` (`throw/<kind>`), a `grenade` `bounce` (`grenade/<kind>/<floor>`, the floor from `SoundSurface.at`; a `rest` is silent) and the `explosion`, and of the `stun`
      only a deafening of its `focus` (interface 18); the AI hears where a grenade comes down from its `bounce` / `rest`, and the UI's `StunScreen` reads the human's own `stun` event to freeze the frame of the flash.
    - `&"shot"`: a gun (Items) posts one per round that leaves the barrel (`{ position` (the
      muzzle)`, gun, attacker, power }`). Audio voices it and the Lighting domain lights a muzzle flash (as it lights a burst on an
      `&"explosion"`).
    - `&"footfall"`: `CharacterFootsteps` posts one each time a foot lands (`{ position` (the sole)`,
      foot` (0 left / 1 right)`, speed, running, character` (the walker)`, crouched }`). Audio voices it; the AI hears it
      (`docs/hearing.md` H1: a stranger's steps through walls, out to a range set by `running` / `crouched`).
    - `&"reload"`: `Character` posts one when a reload starts (`stage = &"start"`) and one when it finishes
      (`&"done"`, never after a cancelled one): `{ position` (weapon hand)`, gun, stage, power, character }`.
    - `&"sound"`: the Audio domain's `Sound` service posts one for every sound it accepts (`{ kind,
      profile, variant, position, volume_db, pitch }`), which is what tests assert on.
    - `&"callout"`: an AI controller posts one when it adopts a combat or investigation decision —
      its team radio (`{ speaker, faction, position, status, path, label, target_id, point }`, and with a combat decision `target_pos`:
      the hostile's last-known spot as the speaker knows it, else where the shots at it came from, `Vector2.INF` when it knows neither;
      an ally reads it as a fight in that room, `docs/grenades.md` G18) — and one
      per step of a tactical entry, which adds `opening`, `into` (the room it leads into), `slot`, `side` (the side of the door it stacks on: a stack split across the door, E19, has both), `entry_step` (claim / ready / bang /
      going_in / in / clear / cover / rear / done / abort), `bang` (this member goes in with a stun thrown first), `bang_off` (it gave the bang up: the stack goes in quietly), `stuns` and `frags` (how many stun / frag grenades it carries), `cleared_room` (with a clear) and `covering` (with a cover:
      the doorway on out of the cleared room it watches), `claim_frame` / `claim_pos` (the `GameClock` frame its slot was claimed on and
      where it stood then, kept by every repeat of that claim: two claims on one slot made on the same frame settle by distance, E2),
      `move_up` (the slot it moved up from, while it walks into the lower one it took; 0 otherwise, E2), `pie` (it has begun slicing the
      pie: nobody moves up behind it) and `crossed_frame` (the `GameClock` frame its crossing began on, its step reaching `going_in` or a
      through step, -1 before it: an NPC's first, the human's latest, D14) (`docs/tactical-entry.md`), and from a member of a stack its leader ordered
      `order_id`, `order_bang` (a grenade first), `order_mode` (`quiet` / `stun` / `frag`, LD14), `order_hold` (the order holds the stack
      for the leader's go, LD13), `order_go` (that go has come), `order_side` (the side of the door the order names, 1 / -1 along its
      wall, 0 for a split stack) and `order_frame` (the order's `frame`, -1 unknown): a stack with such a claim goes in the order's way (`docs/leadership.md` LD9), and from a member of a join
      (the squad's rally, LD24) `join: true` (its claims are never its own, D30); a human invader's `PlayerStack`
      (interface 17) posts the same entry steps for the human as a full claim (E16: every field above, `claim_frame` / `claim_pos` stamped
      on each new claim and kept by its repeats, `crossed_frame` restamped each time its step goes from `claim` / `ready` to `going_in` /
      `in`, `bang: true` and `bang_off: false` (it never holds a stack back nor turns it), `stuns: 0` /
      `frags: 0` (it throws nothing for the stack), `move_up: 0`, `pie: false`), with `human: true` (no AI moves up into its slot), `leader`
      (true while the human leads its squad: a stack it ordered waits for it, LD17) and `own` (true for the human's own claim at a doorway
      nobody stacks at, which the squad rallies the team to, LD24; false for a slot it is reserved in an allied stack, E16). These entry
      fields are encoded by one function and decoded by one, `StackClaim.encode` / `StackClaim.decode`
      (`ai/perception/stack/stack_claim.gd`, each field's default in its `DEFAULTS`): the NPC controller's `_post_entry_call`, the
      `PlayerStack` and every reader of a stack go through them, and no reader takes a claim key off a raw callout. A live grenade has its own statuses, which an ally in range reads as "a
      grenade is down there" and not as what the speaker is doing: `status = "grenade"` (an NPC that saw or heard a grenade come down and
      is in its danger zone: `point` the spot it landed, `kind` `&"frag"` / `&"stun"`; the NPC repeats it once if the grenade then comes to rest
      30 px or more away), `"frag_out"` / `"bang_out"` (the thrower of a frag or a stun, `point` the landing; the GRENADE tactic's call, G17, and `frag_out` from the
      thrower of a frag entry its leader ordered, LD14), all
      from `docs/grenades.md` G16. Allied AI
      controllers within `callout_range` consume it (which flank an ally holds, whom it fights, where to
      support it, which stack slot is taken, when the point is through, which room is clear, which doorway on is
      covered, when the team moves on, which grenade to get clear of). A member carrying out an order (`docs/leadership.md` LD7) radios its
      progress as a callout with `order_id` (the order's `id`) and `order_step` (`moving` / `in_position` / `done` / `refused`); allies leave
      such a call out of what they weigh, and its squad (interface 21) keeps it as that member's latest step.
    - `&"order"`: a squad (`ai/team/squad.gd`, interface 21) posts one per order its leader gives (`docs/leadership.md` LD5):
      `{ id, leader, faction, to` (the recipients, characters)`, kind` (`defend_room` / `stack` / `go` / `ambush` / `cancel`)`, room?`
      (`defend_room`: the room key; `ambush`: the room it lies in wait in, on the click's side of the doorway's wall, D17)`, opening?, into?,
      stack_at?, split?, mode?, bang?, wait_go?` (`stack`: the doorway's id, the room it goes into, the click the stack's side is read from
      or a split stack, `mode` `quiet` / `stun` / `frag` (LD14) or `join` (the squad's own rally on its leader's own entry claim, to the
      followers holding no order, LD24: no side or mode pinned, the member's own entry joining the leader's stack) with `bang` true for
      `stun` and `frag`, and `wait_go`, the stack holds at
      its slots for the leader's go, LD13)`, beyond?` (`ambush`: the room the doorway leads into from its `room`, "" for an exterior door)`,
      auto?` (`go`: the squad's own release of the held stacks of a leader that died, D12)`, pos?` (`defend_room` / `stack` / `ambush` /
      `go`: the target point, the room's centre or the doorway's, which the UI's order markers draw)`, frame }` (the `GameClock` frame it
      was issued on, on every order: a held stack takes the human's crossing as its go only from then on, D14). A `go` (`opening`, `pos`) goes
      to the living members holding a held stack at that doorway and replaces nothing: it releases their order (latched, D13). Range is
      unlimited: every AI controller named in `to` of the same faction takes it, and it holds it until it is done, cancelled or replaced
      (never on a timer); an `ambush` is done on first contact (a hostile seen or shots at the member, D18). Besides its leader's orders a
      squad posts its own: the rally's `join` stacks, a `cancel` of them when its leader radios `abort` at that doorway (LD25), and a `cancel`
      to the members holding a `defend_room` or `ambush` when the human leader dies (LD26).
    - `&"leader"`: a squad posts one when its leader dies and the next in line leads (`docs/leadership.md` LD4): `{ faction, leader, previous }`
      (`leader` null when nobody is left).
    - `&"vehicle"`, `&"engine"`, `&"skid"`: a vehicle (Vehicles) posts `&"vehicle"` `{ position, kind` (`&"car"` / `&"van"`)`, stage }` with
      stage `ignition` (a driver sat down; the vehicle's centre), `door_open` / `slide_open` (a shut door starts to open; at its handle),
      `door_close` / `slide_close` (the frame it shuts), `crash` (a new impact above `VehicleConfig.crash_min_speed` on anything but a
      character, + `speed` (the closing speed) and `material` (the struck `get_surface().material`, `""` for a wall)) or `bump_character`
      (a character struck, + `speed`); `&"engine"` `{ vehicle, kind, stage }` `start` / `stop`; `&"skid"` `{ vehicle, stage }` `start` /
      `stop` (the tyres begin / stop sliding). Audio voices the one-shots and keeps one looping voice per vehicle for its `engine` and its
      `skid`, following the vehicle each frame through `engine_state()`, `slip()` and `speed()` read duck-typed off the event's `vehicle`
      (the `Sound.focus` pattern, interface 18), so it stays a leaf.
    Emitters and listeners never reference each other (like `Despawner`).

11. **General → every domain: shared ids, `PhysicsLayers.SOLID`, `DrawLayers`, `GameClock` and the shared rules**
    - `PhysicsLayers` (`general/physics_layers.gd`, a `class_name` static holder) — `SOLID` names
	  the physics layer bit (1) that "walls + solid furniture" live on. Interaction's reach query
	  (`character_interaction.gd`) and AI perception's sight/line-of-fire rays (`agent_vision.gd`; the
	  vision overlay asks the controller's `debug_sight_end` instead of casting) raycast on this one shared constant instead
	  of each redefining the same magic number — the single point of truth for that layer id. The character's
	  hand queries and leg sweeps (`character/body/`), a dropped item's glance (`items/dropped_item.gd`), a thrown grenade's flight (`items/thrown_grenade.gd`), the
	  bullet's `collision_mask` (`projectile/projectile.gd`), the blast's lines (`projectile/explosion.gd`), Physics' `PhysicsConfig.wall_mask` and a vehicle's body layer and mask, door
	  checks and pile queries (`scenes/vehicle/`) and the character's clearing check (`keep_clear_of`) read it too.
    - `LightMasks` (`general/light_masks.gd`, a `class_name` static holder) — the light masks every domain builds its shadows and
	  light layers on, so who shadows whom is decided in one place (`docs/lighting.md` L6): the occluder bits `WALL` 1,
	  `FURNITURE` 2, `EMITTER` 4 (a solid piece that gives light: it shadows only the flashes), `CHARACTER` 8, `TALL` 16 (a solid
	  piece with no light of its own as tall as `TALL_COVERAGE` 75 `coverage`, above a standing person); the shadow masks the
	  Lighting domain gives its lights by their height (`OVERHEAD_SHADOWS` walls: an overhead light; `LOW_SHADOWS` walls + tall
	  pieces: a low light; `ALL_SHADOWS` everything: a flash); the item light layers `HOUSE` 1 (Godot's default) and `STREET` 2
	  (the street, lit only by the street lamps, the flashes and its own sky); `shadows` (whether occluders are built: off with
	  the Testing domain's `lighting.enabled`) and `occluder(polygon, bit) -> LightOccluder2D` (null while `shadows` is off; wound
	  and culled so the shape itself stays lit). Read by Objects (walls, solid pieces, the street floors), Character (the living
	  body) and the Lighting domain (interface 20).
    - `DrawLayers` (`general/draw_layers.gd`, a `class_name` static holder) — the world's draw-order ladder, one rung per kind of thing,
	  so what lies on the floor, what a vehicle covers and what flies over it keep one order across domains: `FLOOR` −5 (Objects' `Floor`,
	  via `ObjectArtConfig.floor_z_index`) < `RUG` −4 (rugs and mats, `ObjectArtConfig.rug_z_index`) < `BLOOD` −3 (Physics: splats, a
	  bleed-out pool, prints and smears, the scorch decals; `BloodConfig.z_index` / `print_z_index`) < `LYING` −2 (a dead body,
	  `CharacterConfig.ragdoll_z_index`; a spent casing, Projectile; a `DroppedItem` and a grenade at rest, Items) < `UNDER_VEHICLE` −1
	  (a vehicle's `Chassis`) < `STANDING` 0 (Godot's default: the living, a vehicle's occupants, furniture, walls) < `ABOVE` 1 (a
	  vehicle's `Roof`, a grenade in flight, the UI's `StackMarkers`, `OrderMarkers` and `LeaderOverlay`) < `OVERHEAD` 2 (a piece's `Overhang`, Objects:
	  `ObjectArtConfig.overhang_z_index`, a streetlight's arm and head; a room's ceiling fixture, Lighting) < `EFFECTS` 4 (Physics' `ExplosionFx`). A domain's own z knob is initialised from its rung,
	  never a bare number; within a rung the scene tree decides. `docs/vehicles.md` V3 / V6 (a body struck down lies under the vehicle).
    - `GameClock` (`general/game_clock.gd`, an autoload node, `PROCESS_MODE_PAUSABLE`) — the pausable game clock: it counts physics
	  frames in `_physics_process`, so it stands still while the tree is paused. `GameClock.msec() -> int` (frames × 1000 /
	  `Engine.physics_ticks_per_second`: deterministic under `--fixed-fps`, however far a headless run outpaces the wall clock),
	  `GameClock.seconds() -> float` and `GameClock.frame() -> int`. Every AI ttl, timer and age reads it (`docs/leadership.md` LD1: the
	  memory's ages, callout ages, the controller's stamps and force age, the leaf age, burst ages, the grenade replan, the debug overlays'
	  ages and blink), so a pause of any length expires nothing; only what measures real time stays on `Time` (the Von launcher's boot
	  timeout and the planner's per-level `ms`, Von's latency). A per-frame key (`DecisionBudget`'s claim, the learn and sight offsets,
	  a once-a-frame check) may still read `Engine.get_physics_frames()`: it measures no age.
    - `FillBatch` (`general/fill_batch.gd`, a `RefCounted`) — plain-coloured shapes drawn as one triangle array instead of a polygon
	  command each, the same triangles the engine would cut and `draw_circle`'s own 64-gon, in order, so the same pixels:
	  `FillBatch.new(canvas, base := IDENTITY)`, `fill(poly, color, xform := IDENTITY)`, `fill_convex(poly, color, xform := IDENTITY)`,
	  `circle(center, radius, color, xform := IDENTITY)`, `flush()`; `FillBatch.batching` (false under the headless display, which renders
	  nothing: each shape is then drawn by its own command). Used where many are drawn each frame: the Character's limbs and shadow, the
	  Physics domain's blood splats, chip and print chunks and wound marks.
    - `WeightedPick` (`general/weighted_pick.gd`, a `class_name` static holder) — the one weighted roll: one `rng.randf()` over the total of
	  the weights, each entry in order taking the next stretch. `WeightedPick.pick(rng, rows, key_index := 0, weight_index := 1, strict := false)`
	  (the drawn row's `key_index` value), `key(rng, weights: Dictionary, strict := false)` (a key, by its weight) and
	  `index(rng, rows, weight_index := 1, strict := false) -> int`; `strict` is the caller's edge rule (false: a roll on a stretch's end
	  takes that entry, one past them all the last; true: the next entry, one past them all the first). World-Gen's room dresser,
	  Objects' room wear and street marks, the Lighting domain's rhythms and the Character's style draw through it.
    - `MatchVerdict` (`general/match_verdict.gd`, a `class_name` static holder) — who has won a match, the one rule:
	  `MatchVerdict.decide(combatants) -> Dictionary`, `{}` while every side (faction) still has someone alive; once a side is wiped out
	  `{ winner, survivors, sides }` (`winner` the faction left standing, null for a draw: nobody, or more than one side, left; `survivors`
	  the living combatants; `sides` faction -> how many it fields). It reads the combatants through the Character API (`faction`,
	  `is_dead`; a freed one is left out, its side not counted for it). The UI's `MatchHUD` (its banner) and the dev command server's `match` verb (`verdict_of`,
	  which `tools/match.py` scores by) both decide by it, each wording the result its own way (the HUD names a lone survivor in any match,
	  the `match` verb only in a 1v1).

12. **Objects / Character / Items / Vehicles → Art** (leaf: the pixel-art engine; each domain owns its painters)
    - `PixelArt.render(painter, size, color, facing, material, opts) -> Texture2D` — a painter's art
	  at a cardinal facing (the image is turned); furniture, walls, floors.
    - `PixelArt.render_turned(painter, size, color, angle, material, opts) -> Texture2D` + `PixelArt.snap_angle(angle)`
	  — canonical art lit for a snapped angle, drawn rotated by the caller to the exact one;
	  characters, hands, the guns, a vehicle's body, doors, wheels and lamps.
    - `PixelCanvas` — the surface a painter draws on (`static paint(canvas, base, material, opts)`):
	  shapes (`rounded`/`ellipse`/`disc`/`bowed`), `fill`, `bevel`, `outline`, `surface`, `grain`,
	  `speckle`, `glare`, `cast_shadows`, `tones(base)` …; `PixelCanvas.ConvexShape.new(rect, x0, x1, y0, y1)` (a shape from its per-row
	  and per-column spans) is built from outside by the Vehicles domain's `art/vehicle_art.gd`; `PixelCanvas.line_points(a, b) -> Array[Vector2i]` (the
	  points of a 1 px line, the one Bresenham `line` draws along) is walked by Objects' `art/decay.gd` for its lines and scratches. **What gives light** (a screen's
	  face, a tube, a bulb, an LED) a painter draws inside `canvas.glowing(draw: Callable, area := Rect2i())`, which marks every pixel
	  the drawing changes as emissive; `PixelArt.emissive(painter, size, color, facing, material, opts) -> Texture2D` returns those
	  pixels of `render`'s texture for the same inputs (same paint, cached beside it; transparent elsewhere, null when nothing in it
	  glows), for a caller that draws light sources unshaded. A painter's options carry a big look (a character style's resolved look,
	  a weapon style's colours) as an int handle, never the look itself: `PixelArt.handle(look) -> int` registers it (the look's hash) and
	  `PixelArt.look_of(opts) -> Dictionary` reads `opts.look` back ({} for none); the Character's and Items' painters and their callers use them.
    - `ArtConfig` (`class_name` static holder) — the shared resolution, light, drop/cast shadow,
	  turn steps, tone ramp and surface-finish tuning.
    Objects' painters + `ObjectArt` registry, Character's body, head, hand, limb, trunk and vest painters, Items' painters
    (`items/art/`: one gun and one grenade painter per weapon style, police, scrap and pipe, drawing the guns held and dropped and the frag and stun grenades, and the spoon) and Vehicles' painters (`scenes/vehicle/art/`: car, van, door, wheel, lamp) all render through
    these; Art imports nothing from other domains.

13. **Testing → every domain** (a second composition root, like `main.gd`)
    `scenes/testing/` builds a test's world and drives it through the interfaces above only:
    WorldGen (1, incl. the catalogue lookups) or an arena / hand-laid room layout from the three
    factories (2, incl. `WallFactory.openings_for`), staged as Main stages a match, through the match builder (23: `MatchBuilder.stage`
    over the house, layout or arena it built with its objects in place, so `NavBuilder` and `nav_updater.gd` (9) and the dusk lighting
    (20: `WorldLighting.light` after the nav bake) are Main's own path, then the wait until both navigation maps are `ready` before any
    actor enters), the character scenes plus the controller contract (7: each NPC actor bound by the match's one rule, `MatchBuilder.bind_npc`,
    before it joins the tree: the house's `rooms` / `openings` and, for an invader, the front entrance as its `entry_point`,
    `MatchBuilder.entry_point_for`), a declared match (`TestSetup.match`: `MatchBuilder.populate` over the staged world, read with
    `TestContext.match()`) or declared squads over the actors (`TestSetup.squads`: `MatchBuilder.build_squads`, the human leader handed its
    stack radio through `MatchBuilder.bind_player`, read with `TestContext.squad(faction)` / `player_stack()`) — a puppet
    `ScriptedController` or `player_controller.gd` on `character/character_base.tscn` (the
    controller-less character), the vehicle scenes (19: `TestSetup.vehicle(id, kind, pos, rotation := 0.0, props := {})` instances
    `res://scenes/vehicle/<kind>.tscn` under the world root after the nav bake (not carved) and waits one physics frame so the new bodies
    are in the space; `t.vehicle(id)` reads it back; the puppet presses E with `use_vehicle()` and drives with
    `drive(throttle, steer, handbrake)`, writing `move_input` / `run_input` as the player's keys do) — and `EventBus` / character
    signals (7, 10) for its event log.
    Behaviour switches set existing exported props and config-holder `static var`s by name
    (duck-typed, like the overlay flags); a test can also script the Von answers through the AI
    decision sub-domain's `DecisionStub` statics (`decision_stub.gd`, read by `decision_client.gd`; the test session also drives the
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
    (`test_browser_window.gd`, `test_result_hud.gd`) take plain dicts and emit signals. Nothing
    depends on Testing. Its one outward dependency beyond the game is the gdUnit4 addon (`addons/gdUnit4/`, v5.1.1): its
    base suites `GameTestSuite` and `UnitSuite` extend `GdUnitTestSuite`, and its session hook (`test_report_hook.gd`, named in
    `project.godot`'s `[gdunit4]` section) writes a run's report, steps the editor's GdUnit panel's run as `--fixed-fps` steps
    the command line's and keeps its reports out of the checkout (`domain-testing`, "The GdUnit panel"); no game domain names it.

14. **Main → General settings, UI settings page** (the composition root wires them; they never meet)
    - `Settings` (`general/settings.gd`, a `class_name` static holder): `load_file()` (Main calls it once in
      `_ready`, after seeding `Settings.debug` from its own export — not `Keybinds._ready`, so tests never
      read a developer's file), the saving mutators `set_debug(on)`, `set_setup(config)`, `set_overlay(flag, on)`, `rebind(action, event) -> bool`,
      `reset(action)`, `reset_all()`, and `binding_rows() -> Array` (plain dicts for the page). It persists
      the Debug switch, the setup window's last choices (`setup`), the overlay toggles (`overlays`) and the `Keybinds`
      bindings that differ from the defaults to `user://settings.json`.
    - Main ↔ the dev command server (General, `general/command_server.gd`): it finds the match's nodes through the
      `match_world` group, restarts through `Main.return_to_setup()`, hands a seed over through the Engine metas
      `skip_setup` / `match_seed`, and drives the node named `Player`; those names are the whole contract.
    - `SettingsMenu` (`ui/menus/settings_menu.gd`): `open({ debug, rows })`, `set_rows(rows)`; signals
      `debug_changed`, `rebind_requested(action, event)`, `reset_requested`, `reset_all_requested`,
      `back_requested`. It takes plain dicts and knows nothing of `Keybinds`/`Settings`; Main opens it from the
      setup window's `settings_requested`, applies each signal to `Settings` and redraws with `set_rows`.

15. **Any domain → General (`GameLog`)** — `GameLog.say(message)` (`general/game_log.gd`, a `class_name` static
    holder) is how every domain prints its "what is happening" log (shots, punches, house seed, Von decisions,
    perf numbers). `GameLog.enabled` is true in the game; a `tools/run_tests.sh` run sets it from `--verbose`, so
    test runs are quiet unless asked. Plain `print` is not used for gameplay logs.

16. **Objects → Audio: `SoundSurface`** (a floor tells Audio what it is made of; Audio stays a leaf)
    - `SoundSurface.register(rect: Rect2, material: String, pattern: String = "") -> int` /
      `SoundSurface.unregister(id)` — Objects' `Floor` registers its world rect with its `floor_material` and
      the painter's `pattern` in `_ready` and unregisters in `_exit_tree` (the same way it already feeds
      `BloodSurface`); a floor whose definition sets `sound_surface: false` (the street round a house) registers none.
    - `SoundSurface.at(pos) -> StringName` — what the ground is at a world point (`wood tile stone concrete
      carpet`, or `outdoor` when no floor covers it; the newest floor wins). Read only by the Audio domain's
      `Sound` service, to voice a footfall.
    Everything else Audio hears arrives as an EventBus event (interface 10): the gun, projectile and character
    domains only *post*; none of them references Audio.

17. **Main / Testing (through `MatchBuilder`) → AI team: the human's place in a stack** (`scenes/ai/team/player_stack.gd`; a human invader
    is one of the stack)
    - `PlayerStack.attach(character, rooms, openings) -> Node` attaches a `PlayerStack` child to the human with the house's `rooms` and
      `openings` and returns it; the match builder's `bind_player` (interface 23, beside `bind_npc`) is its one caller, for a match's human
      (`populate`) and a test world's human leader (`TestSetup.squads`' `human`) alike.
    - `PlayerStack.view() -> Dictionary` — `{}` with no reservation, else `{ opening, door, slots: [{ n, point, mine, held }], mine, step }`
      (`n` the slot, numbered in claim order; `point` where it stands, on its holder's side of the door: both sides on a split stack, E19):
      the UI's `StackMarkers` (`ui/hud/stack_markers.gd`, `watch(stack)`, built by Main under `World` on the match handle's `player_stack`) draws it on the floor and reads
      nothing else. The stack radios the human's claim as entry `&"callout"`s (interface 10), a full claim encoded by `StackClaim.encode`,
      and hears the allies' off the same bus through a `ClaimLedger` of its own (`ai/perception/stack/claim_ledger.gd`: its side only,
      within its `callout_range`, lapsing after its `callout_ttl` on `GameClock`); its slot, side, point, the crossing order and the markers'
      slots come from the reserved doorway's `DoorStack` (`ai/perception/stack/door_stack.gd`), asked with the human's own claim
      through `DoorStack.claim`, the chain an NPC's entry claims by too, so
      `view()` lays the stack the AI stands. The AI's entry code treats it as any teammate (E16 in `docs/tactical-entry.md`), but for `human`
      (no AI moves up into its slot, and the human never moves up itself nor throws the stack's grenade) and, when the human leads, `leader`.
    - `PlayerStack.squad: Node` — the human's side's squad, handed in by `MatchBuilder.bind_squad(player, squad, stack, own_claims)` with the stack `bind_player` returned (interfaces 21, 23); its claims say
      `leader: true` while `squad.leader()` is the human (`docs/leadership.md` LD17). `PlayerStack.own_claims: bool` (false unless set;
      `MatchBuilder.build_squads` sets it through `bind_squad` on the invaders' side only, D29): while it is set and the human leads a squad with another living
      member and no allied stack forms in its reach, it also claims of its own (LD24): stepping up to a doorway nobody stacks at (on its stack
      side against the wall beside the opening, out from the wall plane and past the jamb each within `PlayerStack.STEP_UP_REACH`, 60 px,
      for `STEP_UP_TIME`, 0.5 s) it claims slot 1 there, marked `own: true`, which the squad hears as its leader's own claim and rallies the
      team to; that claim stands while nobody else stacks there. A slot it is reserved in an allied stack (E16) is never `own` and never
      rallies.
    - `StackMarkers.watch_squad(view: Callable)` — Main (`_watch_side_stacks`, every played match) hands the markers the human's side's
      `Squad.view`, whose `stacks` they draw too (LD18): every stack of that side, a ring per slot, a slot both views give drawn once.
      `StackMarkers.drawn() -> Array` is what is shown: `[{ n, point, mine, held, there, side, row, opening }]`.

18. **Main → Audio: `Sound.focus`** (whose ears the player has; Audio stays a leaf)
    - `Sound.focus: Node` (a plain var on the `Sound` autoload): the character a bang deafens *for the player*. Main sets it to the human when there is
      one (`_build_stun_screen`) and clears it at teardown; null = nobody (a spectator match, a test). Audio reads only the focus's `stun_view()` (interface 7)
      duck-typed: while `stun_view().deaf` > 0, `Sound.muffled()` is true, the game audio goes through a low-pass and one `tinnitus/whine` sound
      (kind `&"tinnitus"`) plays per stun, following the deafness (`docs/grenades.md` G14). A blind-only stun, or the stun of any other character, changes nothing.
    - The sight half of the same stun is the UI's `StunScreen` (`ui/hud/stun_screen.gd`, `watch(character)`, `drawn()`), built by Main for the human and reading
      `stun_view()` (`blind`, `blind_total`) and the `&"stun"` event; it knows nothing of Audio, nor Audio of it.

19. **Character ↔ Vehicle: the drivable contract** (`scenes/vehicle/`; spec `docs/vehicles.md`)
    - **The character's side.** `character.gd` composes the Vehicles domain's `CharacterVehicleUse` (`vehicle/character_vehicle_use.gd`,
      preloaded and added in `_ready` like `CharacterInteraction`) and forwards opaque calls: `try_use_vehicle()` (E, refused while dead or
      in an object interaction: board by the door whose handle is nearest, or get out), `vehicle() -> Node` (the vehicle it is boarding, riding
      in or getting out of; null on foot) and `is_in_vehicle()` (seated only). It steps the component once a physics frame right after its
      controller (`control(delta)`), so a ride overrides that frame's intent, and calls `abandon()` from `_die` (the ride ends where the body is).
      It asks the component `is_active()` (true from the E press to the last step out): while a ride lasts `is_busy()` is true and
      `try_interact()` / `interact_with` are refused.
    - **What the Vehicles domain calls on the character.** During the walk to the door its controller fields `move_input` / `aim_point` /
      `run_input` (interface 7), and from the driver's seat it reads `move_input` / `run_input` as the drive intent; then the ride API:
      `set_ride_pose(at, toward, fold, step := Vector2.ZERO)` (world point, facing, fold 0 standing .. 1 seated, and `step`, the legs' motion
      through the vehicle's frame in px/s, so a carried body does not walk at the vehicle's speed): the first pose cancels a reload, puts the
      held item away (`current_item()` null) and disables the collision shape; the fold is the drawn crouch fold (`posture_folded()` reads it);
      and `end_ride()` (on its own feet again, shape on, item back). It also reads `facing`, `radius`, `speed`, `global_position`, and for a
      character it strikes (a body in the group `characters`, interface 7) `is_dead`, `health`, `velocity`, `get_mass()` and calls
      `apply_impulse` / `take_damage(amount)`; collision exceptions are Godot's own (`add_collision_exception_with` / `remove_...`); after a
      ride the vehicle goes to the character's `keep_clear_of(body)` (as in interface 8: the exception is dropped once the body is clear of it),
      and boarding the vehicle just left calls `stop_clearing(body)`.
    - **The vehicle** (`vehicle.gd`, a `RigidBody2D` on `PhysicsLayers.SOLID`, found by the group `vehicles`): `doors() -> Array`
      (`[{ id, kind` (`swing` / `slide` / `rear`)`, seat, handle, open` (0..1)`, hinge, angle, offset }]`, world space), `seats() -> Array`
      (`[{ id, occupant }]`), `driver() -> Node`, `board(character, door_id) -> RefCounted` (the ride, or null when that door cannot be used
      now), `exit(character) -> bool`, `drive_input(character, throttle, steer, handbrake)` (driver only, engine running), and the reads
      `speed()` (px/s, unsigned), `engine_state()` (`{ running, rpm, load }`), `slip()` (0 while the tyres grip), `wheel_angle()`,
      `brake_lights()` and `view_zoom_out()` (`VehicleConfig.drive_zoom_out` × speed / top speed: how far a camera following someone
      aboard zooms out). Its two draw layers are part of the contract too (the tests find them by name): the child `Chassis` (`layer`
      export `"chassis"`, at `DrawLayers.UNDER_VEHICLE`) and the child `Roof` (`layer` `"roof"`, at `DrawLayers.ABOVE`). Everything else on it (`half_size`, `outline`, `row`, `door_list`, `seat_point`, `occupant`, `is_free`, `reserve`,
      `change_seat`, `release`, `open_door` / `close_door`, `start_engine` / `stop_engine`, `brake_input`, `exit_door`, `hit_marks`) is
      Vehicles-internal, for its ride and visuals.
    - **Its other contracts:** hittable (3), Deformable / debris / impulse (4), pushable (5), the `vehicle` / `engine` / `skid` topics (10)
      and its painters (12). General's camera reads `target.vehicle().view_zoom_out()` duck-typed (`has_method`), never `VehicleConfig`;
      `player_controller.gd` calls `try_use_vehicle()` on `Keybinds.USE_VEHICLE` (E). Only the sandbox and the tests place a vehicle:
      Main, World-Gen, the nav map and the AI do not know them.

20. **Main / Testing (through `MatchBuilder`) → Lighting, and the world's lights and shadows** (`scenes/lighting/`; spec `docs/lighting.md`; Lighting is a
    leaf: it imports only General and reads the world duck-typed)
    - `WorldLighting.light(root: Node2D, seed_value: int, rooms: Array = []) -> WorldLighting` — lights the built world under `root`:
      adds one `WorldLighting` node under it, in the group `world_lighting` (`rooms` = `WorldGen.get_rooms`, for the fixtures;
      `seed_value` seeds the rhythms); null, building nothing, while `LightingConfig.enabled` is off. The match builder's `stage` (interface
      23) calls it after the nav bake with the spec's seed: Main's match with the house seed, the Testing world with its setup's. Its reads: `lights()` (every piece and fixture
      PointLight2D), `fixtures()` (`{ room, light }`), `flashes()` (the pooled flash lights) and `budget()` (`{ per_floor, dropped }`,
      `dropped` = `{ piece, index }` per declared light left without a light). `LightingConfig` (static holder): `enabled`,
      `ambient_color`, `sky_color` and the rest of the dusk, fixture, flash and budget tuning; the Testing domain's `lighting.enabled`
      switch sets `LightingConfig.enabled` and General's `LightMasks.shadows`.
    - **Objects → Lighting: `get_lights() -> Array`** on a light-giving piece (an EnvironmentObject; read duck-typed, like Audio
      reads a vehicle): one plain dict per light in the piece's frame, `offset` (Vector2), `turn` (rad, the pool's long axis),
      `colour`, `energy`, `radius` (px, along the long axis), `shape` (`round` / `wide` / `tube`), `rhythm` (`[[mode, weight],
      ...]`, modes `steady buzz failing blink shimmer pulse`), `room_light` (it lights its room: no fixture there), `street` (it
      lights the street too), `height` (`overhead`: above the heads, a lamp's bulb, a street lamp's head; `low`: a screen, a tube,
      LEDs; the Lighting domain picks the light's shadows and pool by it, `docs/lighting.md` L2 / L6) and `glow` (the piece's
      `Emissive` overlay, dimmed with the light; or null). The Lighting domain parents each light it keeps to the piece, so a
      shoved piece carries it.
    - **The shadows and light layers** (on General's `LightMasks`, interface 11): Objects' walls (one occluder per wall run,
      `WALL`) and solid pieces (their footprint, `EMITTER`, `TALL` or `FURNITURE`) and Character's living body (an oval turned
      with `facing`, `CHARACTER`, freed on death) build their own `LightOccluder2D` children with `LightMasks.occluder`, like
      their colliders; Objects' street floors (catalogue `light_layer: "street"`) put their canvas items on `LightMasks.STREET`;
      Objects' `Emissive` overlays draw unshaded. The Lighting domain reads the floors, found by the group `floors` every Objects `Floor` joins in
      its `_ready` (their `size` and the `light_mask` of their canvas items), for the per-floor budget, and each frame the characters in the group `characters` (`is_dead`,
      `radius`, interface 7) for whom stands in a flash.
    - **The flash events:** the `&"shot"` and `&"explosion"` topics (interface 10) light its flash pool.

21. **Main / Testing (through `MatchBuilder`) → AI team: the squads, their leaders and their orders** (`scenes/ai/team/squad.gd`; spec
    `docs/leadership.md`)
    - The match builder builds one `Squad` (a `Node`) per side after arming the characters (`MatchBuilder.build_squads`, interface 23: under
      Main's `World` in every match, under a test world for a declared match or declared squads):
      `Squad.setup(faction, roster, openings, rooms, human := null, claim_ttl := 0.0)` (`roster` the side's characters in spawn order; `human` when the human
      leads; `claim_ttl` how long the side's NPCs keep a callout they heard, their controllers' `callout_ttl`, read by `MatchBuilder.callout_ttl_of(members)`
      off each one's controller (interface 7): the squad keeps a member's entry claim as long), and hands each member its own through
      `MatchBuilder.bind_squad(member, squad, stack := null, own_claims := false)` (beside `bind_npc`: the controller's `squad`, found by the
      same contract, and the human's `PlayerStack.squad` through `stack`, the node `bind_player` returned, interface 17, with its `own_claims`,
      true for the invaders' side only, D29). The squad reads its members only through the
      Character API (`rank`, `is_dead`, the `died` signal, `global_position`, and the leader's `facing`; a member is an NPC, one that may
      follow, when a child of it is in the group `npc_controllers` at `setup`, interface 7) and lays its stacks and its follow spots on the
      navigation map and physics space of its own viewport's `World2D` (`NavBuilder.snap`, interface 9; a wall ray for the leader's sight).
      Every squad coordinates, with no switch (`docs/leadership.md` LD3, LD19 to LD26).
    - Reads: `leader() -> Node` (LD3: the human when it leads; else the highest `rank`, the first in spawn order among equals, so the invaders'
      unit lead and the defenders' first spawned), `members() -> Array`, `alive(member) -> bool`, and `view() -> Dictionary`
      (`{ leader, members: [{ node, order, step, held, follow_spot }], stacks, trail, leash }`: the order each member holds, the posted dict or {} (a held stack a `go` released
      carries `go: true`), its latest `order_step` and `held` (its order is a stack that waits for the leader's go and no go has released yet,
      LD13: the one rule the UI reads instead of working it out; released by the squad's own `go`, or by one read off the claims,
      `DoorStack.released(order_id, into, since)`, `since` the order's `frame`: a claim under that order says `order_go`, or a member of that
      stack, under the order or the human, is crossing or through into the order's room, the human on a crossing begun since (its
      `crossed_frame` at or after `since`; -1 on either releases nothing) (D14: the human leader stepping in is its go; a claim left from
      an earlier entry through the doorway releases nothing), latched once heard as each member latches its own); an order radioed `done` is no longer held, {} with the
      step `done`, while a `refused` one is; `stacks` every stack the side is forming, ordered or its own, read off the side's entry claims
      through the squad's own `ClaimLedger` (unlimited range: the side's whole view; `claim_ttl`) and laid by each doorway's `DoorStack.layout`,
      `[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]` (LD18: slots 1 to the last claimed, each where
      the AI stands it; `holder` the instance id, 0 free; `there` its holder in it; `mine` the human's; `row` 1 against the wall, 2 a step out),
      from a stack's first claim until everyone in it is through; `follow_spot` the member's `follow_spot`, `trail` the leader's trail
      (`Array` of points, oldest first) and `leash` (px), LD28), what observers draw.
    - Following reads (LD19 to LD23): `follows(member) -> bool` (alive, the squad has a leader, not the leader, an NPC), `follow_spot(member)
      -> Vector2` (the spot it keeps to now, `Vector2.INF` when it does not follow: on the leader's trail while it moves, a ring slot behind
      it once it has stood `follow_still_time`, out of the leader's way), and the tunables the AI reads, vars on the squad: `follow_gap` (55),
      `follow_step` (45), `follow_ring` (80), `follow_still_time` (0.8 s), `follow_retarget` (20), `follow_arrive` (10), `leash` (320) and
      `leash_break` (1.3). The squad keeps the leader's trail every physics frame and lays the spots through its `SquadFollow`
      (`ai/team/squad_follow.gd`, the team module's own, which reads the tunables, `leader()`, `members()`, `alive` and `follows` off the
      squad). The controller reads `follows`, `leader()`, `leash` and `leash_break`; the behaviour's `follow` primitive `follow_spot` and the
      follow tunables, and faces away from the leash centre the controller pushes (its leader's live position), reading no `leader()`.
    - `Squad.issue(request) -> Dictionary`: a leader's request in plain terms (`{ kind, to: [characters], pos?, room?, bang?, mode?, wait_go? }`:
      no `to` = every living member but the leader; a stack's `mode` one of `Squad.MODES`, `quiet` / `stun` / `frag`; `Squad.JOIN`, `join`, is
      not one of them: only the squad's own rally posts it, and `Squad.is_join(order)` tells such an order) resolved into the AI's (a room key, or the room under `pos`; for a stack or an ambush the
      doorway nearest `pos` within its width, a stack's `into` the room on the far side of the wall plane from `pos`, an exterior door's house
      room, and `stack_at` = `pos` or `split` for a click on the opening; a stack's `mode` from the request's `mode`, else `bang` true is a
      stun; an ambush's `room` the one on `pos`'s side of the wall plane) and posted as `&"order"` (interface 10); a `{ kind: "go", pos }`
      posts a `go` to every living member holding a held stack, not yet released, at the doorway nearest `pos`, whatever its `to` (D13; {}
      when none waits there). Returns the order posted, or {}. Nothing outside the AI computes an AI id. When a leader that gave held stack
      orders dies, the squad posts their `go` itself (`auto: true`, D12).
    - `Squad.resolve(request) -> Dictionary` (read-only): the same resolution without posting, `{ room, pos }` for a `defend_room`,
      `{ opening, pos, into, split, stack_at? }` for a `stack`, `{ opening, pos }` for a `go` and `{ opening, pos, room, beyond }` for an
      `ambush` ({} when it names nothing): the one rule for which doorway a click means and which room "into" (or an ambush's room) is,
      which the command menu names its stack and ambush items from.
    - On the leader's `died` the next in line leads within the frame and the squad posts `&"leader"` (interface 10); the orders given stand,
      but when the dead leader was the human the squad posts one `cancel` to the members holding a `defend_room` or `ambush` (the takeover,
      LD26). The trail starts afresh at the new leader.
    - **The rally** (LD24, LD25): on an entry claim of its leader's own (an `&"callout"` from the leader with no `order_id` and no `join`: an
      AI leader's entry, or the human's own claim through its `PlayerStack`, the one marked `own`, interface 17; a join's claims never, D30) the squad posts one `stack` order with `mode` `join` to every
      follower holding no order, once per doorway per leader, and on the leader's `abort` there a `cancel` to the members holding those joins.
      The command menu never offers a join.
    - **The human leader's command menu and order markers** (UI, `docs/leadership.md` LD10 to LD12 and LD16), in the shape of interfaces 14 and 17:
      with the setup window's "Lead the team" on (its `current_config()["lead"]`, saved by `Settings.set_setup`; a played match only, read into
      the spec's `human.lead` by `MatchBuilder.spec_from_setup`) the match builder hands the human to `Squad.setup` (a human invader is ranked
      the unit's lead, 2, by `MatchBuilder.style`) and Main's `_build_command_menu`, over the match handle's squads, builds, under `World`, the
      `CommandMenu` (`ui/hud/command_menu.gd`, a `CanvasLayer`, `PROCESS_MODE_ALWAYS`): `setup({ rooms, teammates, view, resolve, leader,
      right_clear })` (the house's `WorldGen.get_rooms` dicts, the squad's members but the human, `view` and `resolve` the squad's `view()` and `resolve()`
      callables (the doorway a click is on and the room its stack goes into are the squad's `resolve`), `leader` the human: it opens only
      while the view names it the leader, `right_clear` the screen width from the right edge its panel keeps clear when docked on the right:
      Main hands it the overlay bar's `OverlayToggles.RESERVED_WIDTH` (interface 22) with Debug on, else 0, the default), `open_at(world)`, `close()`, `is_open()`, `items() -> Array`
      (`[{ label, disabled }]`, what it offers: on a teammate holding a held stack, "Go into the <room>"; on a doorway, "Go into the <room>"
      while a member holds a held stack there, the stack items quiet / with stun / with frag (the stun or frag one greyed, with a tooltip,
      while no recipient carries one, D1 / D15) and "Ambush the doorway from the <room>"; on a room, "Defend the <room>"; "Cancel order"),
      a "Hold for my go" checkbox (D19), and the signals `order_requested(request)` (`{ kind: "stack", to, pos, bang, mode, wait_go }`,
      `pos` the raw click, `wait_go` the checkbox; `{ kind: "go", pos }`; `{ kind: "ambush", to, pos }`; `{ kind: "defend_room", to, room }`;
      `{ kind: "cancel", to }`), which Main connects to `Squad.issue`, and
      `selection_changed(nodes)`; and the `OrderMarkers` (`ui/hud/order_markers.gd`, a `Node2D` at `DrawLayers.ABOVE`): `watch(view)` (the
      squad's `view()` callable), `set_selection(nodes)` (Main connects the menu's `selection_changed` to it) and `drawn() -> Array`
      (`[{ kind, point, node, from?, label?, refused? }]`, `kind` `order` (`from` where the member stands, `label` the words at its target,
      "Stack (frag, hold) · in position", "Join stack · moving", "Ambush · moving") / `selected`). `Keybinds.COMMAND` (`"command"`, right mouse) is read by the
      menu alone, so with "Lead the team" off nothing reads the right button. Neither holds an AI reference: they read the members through the
      Character API (`global_position`, `name`, `is_dead`, `item_count`) and the squad through `view()` (and the menu `resolve()`), and the menu
      emits plain requests.
    - **The squad-leaders debug overlay** (UI, `ui/overlays/leader_overlay.gd`, LD12): the match builder builds a `LeaderOverlay` (a `Node2D`
      at `DrawLayers.ABOVE`, hidden) with the squads (`MatchBuilder.build_leader_overlay`, interface 23: under `World` in every match, under a
      test world with its declared squads or match), the match handle's `leader_overlay`: `watch(views)` (every squad's `view()`
      callable), `show_leaders` (the overlay bar's global `OverlayRegistry.LEADERS` row, off by default, set through `MatchBuilder.set_overlay`)
      and `drawn() -> Array` (while shown, per squad: `{ kind: "crown", point, node }`, a crown over its living leader; `{ kind: "leash", point, radius,
      node }`, the leash ring round it; per follower with a follow spot `{ kind: "spot", point, node }` and `{ kind: "line", from, to, node }`;
      `{ kind: "trail", points }`, the leader's trail dotted, LD28). It reads the leader and the members through the Character API
      (`global_position`, `is_dead`) and the squads through `view()` only.

22. **Main → UI: setup window, match HUD, spectator inspector, overlay bar** (the composition root wires them, in the shape of
    interface 14: plain dicts in, signals out; the flow is `domain-main`'s)
    - `SetupMenu` (`ui/menus/setup_menu.gd`, the `SetupMenu` node of `main.tscn`): `open(defaults)` (the exports with the saved
      `Settings.setup` over them, plus the choice rows as plain data: `weapons` (`LoadoutConfig.options()`), `grenades`
      (`grenade_options()`), `outfits` (`outfit_options()`) and the run's `ticket`), `current_config() -> Dictionary` (`{ side, seed, lead,
      defenders, invaders }` as they stand, {} before `open`: Main saves it with `Settings.set_setup` when the window is left without
      starting) and `set_status(text)` (a status line while Main holds the start; "" hides it); signals `start_requested(config)` (`{ mode`
      (`play` / `watch` / `endless`)`, side, seed, lead, defenders, invaders }`, each side `{ count, weapon, magazine, spares, stuns, frags,
      outfit }`), `tests_requested` (Main changes scene to the test browser, interface 13) and `settings_requested` (Main opens the settings
      page, interface 14). It knows nothing of `LoadoutConfig`, `Settings` or Main.
    - **The Von-server wait** (AI decision: `ai/decision/decision_server_launcher.gd`, the `DecisionServerLauncher` node of `main.tscn`):
      before it builds a match Main asks `is_resolved()` and, while not, shows `set_status` and awaits `resolved(live)` (emitted exactly once;
      `live` false = no server coming: the match starts with NPCs holding steady). Read duck-typed (`has_method("is_resolved")`), so a scene
      without the launcher starts at once.
    - `MatchHUD` (`ui/hud/match_hud.gd`, the `MatchHUD` node of `main.tscn`): `begin(combatants, time_limit := 0.0)` (every character in
      the match, a human included; an endless run's `endless_time_limit` calls a match still undecided then a draw), `set_countdown(text)`
      (the endless run's next-match line, "" clears it) and the signal `match_ended(verdict)` (Main starts the endless countdown on it).
      Main also hides the player debug panel (the `DebugUI` node) behind the setup window and frees it in a spectator match; the panel
      itself watches the player by exported path (interface 7).
    - `SpectatorInspector` (`ui/hud/spectator_inspector.gd`, built by Main under `World` in a spectator match): `setup(combatants, flags,
      right_clear)` (`flags` the overlay toggles without the global ones; `right_clear` the bar's column its outfit panel keeps clear of,
      `OverlayToggles.RESERVED_WIDTH`) and `set_flag(flag, on)` (a toggle applied live to the selected NPC). What it reads of the characters
      and their controllers is interface 7.
    - **The overlay bar** (`ui/overlays/`, built by Main the first time a match starts with Debug on): `OverlayToggles` — `setup(flags)`
      (`{ flag: bool }`, a missing flag taking its default), the signal `overlay_toggled(flag, on)` (Main's `set_overlay` saves it with
      `Settings.set_overlay` and applies it: `PERF` to its own performance overlay, in a spectator match any NPC flag to the inspector's
      `set_flag`, and the rest to the match by the one rule, `MatchBuilder.set_overlay` (interface 23): `NAV_HOLES` to the `nav_debug.gd`
      overlay's `show_holes`, `LEADERS` to the `LeaderOverlay` (interface 21), any other to every NPC) and `RESERVED_WIDTH`;
      `PerformanceOverlay.set_shown(on)`; and `OverlayRegistry` (static: `defaults() -> Dictionary` (`{ flag: bool }`), `is_global(flag)`,
      `apply(npc, flags)` (sets each `show_<x>` on every child of the NPC that has it, interface 7), `GLOBAL` and the global flags
      `NAV_HOLES`, `LEADERS` and `PERF`). The Testing domain uses the same bar (interface 13): its runner builds an `OverlayToggles` and its
      own `PerformanceOverlay` (`PERF`), and its world seeds its flags from `defaults()`, applies them to each actor with `apply` at its spawn
      and routes a toggle through `MatchBuilder.set_overlay`, as Main's match does (so `LEADERS` shows the crowns of its declared squads).

23. **Main / Testing → MatchBuilder: building a match** (`scenes/match_builder.gd`, `class_name MatchBuilder`, a `RefCounted` of statics;
    part of the composition root, beside `main.gd`, with its placement helper `match_spawner.gd`, which only it uses; the flow and the
    placement rules are `domain-main`'s). Main's played, Watch and Endless matches and the Testing domain's worlds (13) build through it, so
    there is one way a match is staged, populated and bound. Nothing in the domains it wires knows it.
    - **The match spec**, a plain dict: `MatchBuilder.spec(overrides := {}) -> Dictionary` lays `overrides` over the defaults: `seed` (the
      house's, which also pins the placement, the guns and the styles; 0), `plan` (a floorplan key, "" = by the seed), `entrance` (where the
      front entrance lands), `house` (a house already built, a layout or an arena with its objects placed, staged in place of a generated
      one; null), `defenders` / `invaders` (`{ count, loadout, at }`: 1 each, the side's loadout, optional explicit start points, one NPC each,
      in place of placement; a side given keeps the defaults of what it does not name), `human` (`{ node, side, lead, at }`: the human's
      character, `&"defender"` / `&"invader"`, whether it leads its side's squad, an optional start; `{}` none), `wait_nav` (true),
      `spawn_clearance` (20 px), `invader_margin` (80 px) and `overlays` (`{ show_<x>: bool }` by `OverlayRegistry` flag, the debug overlays
      the match starts with; a flag it does not name starts off; `{}`). The side loadouts' defaults are `MatchBuilder.INVADER_LOADOUT`
      (1 stun, 1 frag, a helmet, a shirt, a plate carrier with a steel III plate front and back, tactical pants, boots; the gun the
      `LoadoutConfig` default) and `DEFENDER_LOADOUT` (`{}`), so a test's match carries what Main's does. `DEFENDER_FACTION` (`household`)
      / `INVADER_FACTION` (`invader`) are the scenes' faction tags.
    - **Building:** `build(match_spec, world: Node2D) -> Dictionary` (a coroutine: `stage`, then `populate`; `{}` when the match was torn
      down during the wait). `stage(match_spec, world) -> Dictionary` (a coroutine), the world stage: the spec's `house`, moved under
      `world`, or `WorldGen.generate` (1); `NavBuilder.build`, the `nav_debug.gd` overlay (`NavDebug`) and the `nav_updater.gd` re-baker
      (`NavUpdater`) (9); `WorldLighting.light(world, seed, rooms)` (20); then with `wait_nav` two physics frames and a wait until
      `NavBuilder.ready` holds on the planning map and on its steering map (at most `NAV_SYNC_MS`, 5000 ms of real time, then a
      `push_error`), so no NPC is placed before the maps answer with this house. `populate(match, match_spec) -> Dictionary` over a staged
      handle: the defenders and the invader team placed through `match_spawner.gd` from one RNG seeded with `seed` (or at the sides' `at`
      points), each NPC bound before it joins the tree; the human joined to its side (its faction, its start, reparented just above the
      house) and handed its stack radio; everyone armed, styled and ranked (`arm`); `build_squads`; `build_leader_overlay`; every overlay
      but the holes (the stage's) started through `set_overlay` by the spec's `overlays`.
    - **The match handle**, a plain dict: `{ world, house, rooms, openings, nav_region, nav_debug }` from `stage`, plus `combatants` (every
      character in spawn order, the human last), `squads` (faction -> `Squad`), `player_stack` (the human's `PlayerStack`, or null) and
      `leader_overlay` from `populate`.
    - **The bind rule, once:** `bind_npc(npc, rooms, openings, entry_point := Vector2.ZERO)` hands an NPC's controller its `rooms`,
      `openings` and, when given, `entry_point`, **before the NPC joins the tree**; the controller is found by its contract (interface 7: the
      child with `control` and `rooms`, since the `npc_controllers` group is joined only in `_ready`). `entry_point_for(faction, openings)
      -> Vector2` is the front entrance for an invader, ZERO for a defender (`front_entrance(openings) -> Vector2`, ZERO in a house with
      none). `bind_squad(npc, squad, stack := null, own_claims := false)` (21), `bind_player(player, rooms, openings) -> Node` (17) and
      `callout_ttl_of(members) -> float` (21) are the squad's and the human's.
    - **Arming and squads:** `arm(characters, match_spec)` (each by its faction's side loadout through `LoadoutConfig.apply`, interface 6,
      the guns from `seed` XOR `LOADOUT_SEED_SALT`), `style(characters, match_spec) -> Array` (one `apply` style per character, from `seed`
      XOR `STYLE_SEED_SALT`: the match's police unit and its ranks, lead 2, sergeant 1, troopers 0, a leading human invader the lead; each
      defender a crew style; read off `CharacterConfig.styles`, `styles_of(faction)`), `build_squads(world, combatants, openings, rooms,
      human := {}, stack := null, claim_ttl := -1.0) -> Dictionary` (one `Squad` per faction, interface 21, keeping claims `claim_ttl` s,
      or `callout_ttl_of` the side when it is negative) and `build_leader_overlay(world, squads) -> Node2D`.
    - **Overlay routing, once:** `set_overlay(match, flag, on)` on a handle, or any dict with its `nav_debug`, `leader_overlay` and
      `combatants`: `NAV_HOLES` to the `nav_debug`'s `show_holes`, `LEADERS` to the `leader_overlay`'s `show_leaders` (none, nothing), any
      other non-global flag to each combatant with an AI controller through `OverlayRegistry.apply`; `PERF` is the caller's own (22).
    - **The setup's specs** (Main's): `spec_from_setup(config, base := {}) -> Dictionary` reads the setup window's config (22) into a spec
      over `base` (its `seed`, each side's `count` and loadout keys, the human on its `side` with `lead` in a played match, none in Watch or
      Endless); `random_spec(rng, base, most) -> Dictionary` draws an endless run's next one (seed 0, each count in 1..its most, a random gun
      and outfit per side keeping the grenade counts).
    - **Main's one way in:** `Main.start_match(spec) -> Dictionary` builds `spec` under a fresh `World` node (`MatchBuilder.build`, the spec's
      `overlays` replaced by Main's flags) and wires the HUDs on the handle (17, 18, 21, 22); `{}` when the match was torn down while built.
    - The Testing domain (13): `TestWorld` stages through `stage` (`wait_nav` on), binds each NPC actor through `bind_npc` with
      `entry_point_for`, populates a declared match through `populate` (`TestSetup.match`, `TestContext.match()`), builds declared squads
      through `build_squads` / `bind_player` / `build_leader_overlay` (`TestSetup.squads`) and routes its overlay toggles through
      `set_overlay`; it has no bake, light, nav-wait or bind code of its own.

### Dependency graph (arrows = "calls / knows"; no cycles)

```
main ──(start_match: build; spec_from_setup / random_spec; set_overlay)──▶ MatchBuilder (the root's match module) ─▶ match_spawner (placement: the NPC scenes)
TestWorld (Testing) ──(stage / bind_npc / entry_point_for / populate / build_squads / bind_player / build_leader_overlay / set_overlay)──▶ MatchBuilder
MatchBuilder ─▶ WorldGen ─▶ ObjectFactory / WallFactory / FloorFactory / WearFactory ─▶ Objects ─▶ Physics
MatchBuilder ─▶ NavBuilder (build, ready, steering_map; match_spawner furniture_holes) ──(parses static colliders)──▶ NavigationServer2D;  MatchBuilder ─▶ NavDebug / NavUpdater (Navigation, overlay + re-bake)
main ─▶ Character ◀─ PlayerController ─▶ Keybinds
MatchBuilder (arm) ─▶ LoadoutConfig ─▶ GunConfig / MagazineConfig / OutfitConfig / ItemRegistry (random_gun_slot / loadout_for / spares_for) ─▶ Character.set_loadout / set_outfit / set_style;  main ─▶ LoadoutConfig (the setup window's rows, normalize)
MatchBuilder ──(the styles' side / weapons)──▶ CharacterConfig.styles
main ─▶ Settings ─▶ Keybinds   /   main ─▶ SettingsMenu (UI; signals only, no dependency on Settings)
main ─▶ SetupMenu / MatchHUD / SpectatorInspector / OverlayToggles / PerformanceOverlay / OverlayRegistry (UI; plain dicts in, signals out);  MatchBuilder ─▶ LeaderOverlay / OverlayRegistry (UI: build_leader_overlay, set_overlay)
main ──(is_resolved / resolved: the Von wait)──▶ DecisionServerLauncher (AI)
Character ─▶ Item ─▶ ProjectileSpawner ──(get_surface / take_hit)──▶ Objects;  Projectile ──(get_surface_at / take_hit)──▶ Character ─▶ Outfit (Items)
Character ─▶ Interaction ──(get_interactions)──▶ Objects
Character ─▶ CharacterVehicleUse (Vehicles) ─▶ Vehicle   (the ride and a strike call back only the character API of interface 19, as an Item calls its user's)
Character ─▶ Deformable / Deformation / BloodWound / BloodFootprints / Ragdoll / HitInfo / Physics.impact_impulse / spawn_debris / bleed_out (Physics)
Vehicle ─▶ Deformable / Deformation (draw_marks) / Physics.impact_impulse / Physics.spawn_debris (Physics);  Vehicle ─▶ PhysicsLayers (General)
Objects / Character / Item / Vehicle ──(painters)──▶ PixelArt / PixelCanvas / ArtConfig   (Art, a leaf)
AIController ─▶ NavigationAgent2D ─▶ NavigationServer2D   (writes Character.move_input; tactics query the nav map)
AI (perception / behaviour / team / debug) ─▶ NavBuilder (ready / snap / route / path_length, avoid_map, planning_region, steering_map)
AIController ─▶ ItemRegistry slot ids (Items: FISTS_SLOT, STUN_SLOT, FRAG_SLOT)
Physics debris / hit particles / blood / explosion fx, Projectile casings ─▶ Despawner
Projectile / Explosion / Character ──(&"hit" events)──▶ EventBus ──(posted)──▶ AIController
AIController ──(&"callout" events)──▶ EventBus ──(posted)──▶ allied AIControllers
PlayerStack (human) ◀──(&"callout" entry steps)── EventBus ──(&"callout": the human's claim)──▶ allied AIControllers;  StackMarkers (UI) ──(view())──▶ PlayerStack
AI behaviour (entry.gd, behavior.gd) / orchestrator / team (PlayerStack, Squad) ──(StackClaim / ClaimLedger / DoorStack, preloaded; AgentPerception.entry_stack)──▶ AI perception's stack/ (the stack seam)
MatchBuilder ──(build_squads: Squad.setup, bind_squad; bind_player: PlayerStack.attach)──▶ Squad / PlayerStack (AI team);  Squad ──(&"order")──▶ EventBus ──(posted)──▶ AIControllers;  Squad ◀──(&"callout" order_step, entry claims)── EventBus;  MatchBuilder.bind_squad ──(squad)──▶ PlayerStack;  StackMarkers (UI) ──(view(): stacks)──▶ Squad
CommandMenu (UI) ──(order_requested)──▶ main ──(issue)──▶ Squad;  CommandMenu / OrderMarkers / LeaderOverlay (UI) ──(view())──▶ Squad;  CommandMenu ──(resolve())──▶ Squad;  CommandMenu ─▶ Keybinds.COMMAND;  CommandMenu ─▶ ItemRegistry.STUN_SLOT / FRAG_SLOT (Items, via item_count)
AI perception ──(Explosion.shields / first_stop: the blast's cover rule)──▶ Explosion (Projectile)
ThrownGrenade (Items) ──(Explosion.frag / .stun)──▶ Explosion (Projectile) ──(take_hit / blast_push / take_stun, ProjectileSpawner fragments, Physics.spawn_explosion)──▶ Objects / Character / Physics
Item (&"shot") / GrenadeItem (&"throw") / ThrownGrenade (&"grenade") / Projectile (&"hit") / Character (&"hit", &"footfall", &"reload") ──(events)──▶ EventBus ──(posted)──▶ Sound (Audio) ─▶ SoundBank ─▶ SoundSynth
Character (&"footfall") ──▶ EventBus ──(posted)──▶ AIController (footsteps heard)
Objects Floor ──(SoundSurface.register)──▶ SoundSurface ◀── Sound   (Audio, a leaf: imports nothing but EventBus)
main ──(Sound.focus = the human)──▶ Sound   /   Character (&"stun") ──▶ EventBus ──▶ Sound (tinnitus + muffle for the focus), StunScreen (UI)
Explosion (&"explosion") ──▶ EventBus ──▶ Sound (the burst) / Camera (shake) / AIController
ThrownGrenade (&"grenade") ──▶ EventBus ──▶ AIController (a grenade heard coming down)
Vehicle (&"vehicle", &"engine", &"skid") ──▶ EventBus ──▶ Sound ──(engine_state / slip / speed, duck-typed)──▶ the vehicle's loops
Camera ──(target.vehicle().view_zoom_out(), duck-typed)──▶ Vehicle
UI (DebugUI / MatchHUD / SpectatorInspector) / Camera ──(exported path + signals)──▶ Character  (the inspector debug_zones / known_contacts_for_display / debug_focus / debug_clear_focus on the AI controller; DebugUI and the inspector outfit_view)
DebugUI ─▶ LoadoutConfig.grenade_options (Items)
main ──(Tests button: scene change)──▶ TestBrowser ─▶ TestRunner ─▶ WorldGen / factories / MatchBuilder (the world stage, binding) / Character scenes / EventBus
Sandbox (Testing) ──(own painter)──▶ PixelArt / PixelCanvas (Art);  Sandbox ──(recipe_for / render)──▶ SoundBank / SoundSynth (Audio) ─▶ its own AudioStreamPlayer2D
TestBrowser / TestRunner / TestWorld ─▶ UI (TestBrowserWindow / TestResultHUD / OverlayToggles / PerformanceOverlay / OverlayRegistry)
TestRunner / GameTestSuite ─▶ Camera (General: frame(targets), pan_enabled)
GameTestSuite / UnitSuite / test_report_hook (Testing) ─▶ GdUnitTestSuite / GdUnitTestSessionHook (the gdUnit4 addon);  TestRunner / GameTestSuite ─▶ TestSession (plays one test)
MatchBuilder (stage: main's match and every TestWorld) ──(WorldLighting.light)──▶ WorldLighting (Lighting, a leaf) ──(get_lights(), the groups `floors` and `characters`, duck-typed)──▶ the world
Item (&"shot") / Explosion (&"explosion") ──▶ EventBus ──▶ WorldLighting (flashes)
Objects (walls, solid pieces, street floors) / Character (the living body) ──(LightMasks.occluder, STREET)──▶ LightMasks (General)
MatchHUD (UI) / CommandServer `match` (General) ──(decide)──▶ MatchVerdict (General)
TestWorld ─▶ vehicle scenes (TestSetup.vehicle)
TestSession / TestWorld ─▶ DecisionStub / DecisionServerLauncher / NPC scenes (AI), config-holder statics (behaviour switches)
TestBrowser ──(Back: scene change)──▶ main
```

Physics, Navigation, Art, Audio, Lighting and World-Gen are leaves — apart from General's infrastructure (`GameLog`, `EventBus`,
`Despawner`, `GameClock`, `PhysicsLayers`, `DrawLayers`, `LightMasks`, `FillBatch`, `WeightedPick`), which every domain may use (World-Gen's only outward code dep is
the four factories; Navigation depends only on Godot's `NavigationServer2D`; Art
only on Godot's `Image`; Lighting reads the world only duck-typed). Tuning is split into fifteen `class_name` static holders: `BallisticsConfig`
(projectile), `PhysicsConfig` (impact, debris and hit particles, deformation, the explosion's look, the ragdoll solver), `CharacterConfig` (walking
push + punch + being stunned + hit zones, sides and the outfit's weight + the character's art and its styles, pose, stances and fall), `BloodConfig` (blood splatter, drips and bleed-out), `ArtConfig` (the shared pixel-art light,
shadows, tones and finishes), `ObjectArtConfig` (Objects' painter proportions/colors, props,
floor/wall tiles, the run-down look: palette grade, grime, neon share, wear marks, street), `WorldGenConfig` (World-Gen's
furnishing fill pass, the run-down dressing's placement, the street ring and its street lamps), `MagazineConfig` (Items: magazine
types, capacities and reload times), `GunConfig` (Items: one row per gun — damage, fire rate, penetration,
muzzle speed, spread, recoil, magazine, whether it raises at a wall, its looks per weapon style), `GrenadeConfig` (Items: one row per grenade kind — fuse, windup, range, flight, the blast or flash and bang numbers, its looks per weapon style), `OutfitConfig` (Items: the garment and plate rows — slot, name, weight, looks per character style, the armour's zones, sides and protection numbers, a plate's durability), `SoundConfig` (Audio: the master switch, category volumes, voice caps and ranges, pitch/volume jitter, sample rate, round-weight bands, the vehicles' engine, skid and crash numbers), `VehicleConfig` (Vehicles: one row per kind — size, mass, engine, brakes, steering, grip, doors and seats — one `looks` row per kind, and the shared getting-in, driving, harm, crash, camera and look numbers), `LightingConfig` (Lighting: the master switch, the dusk, the room fixtures, the flashes, the per-floor budget and the light textures) and `LoadoutConfig` (Items: the setup choices' bounds — spare magazines, grenades — and the default outfit). World-Gen's `LayoutRules` (which rooms may
hold the front door or an exit, which room types may share a door) is a rules table in the same style, not
tuning. There is no `Config` autoload. Three more static holders are not tuning but shared ids (General, interface 11):
`PhysicsLayers` (a physics-layer id, the same role `Wall.Side` plays for doorway sides), `DrawLayers` (the shared draw-order
ladder every domain's z knob starts from) and `LightMasks` (the occluder bits, shadow masks and light layers).

## Cross-cutting conventions

Two conventions hold across domains; the per-domain specifics live in each domain's skill.

- **Layered control / animate / draw.** Within an entity the three verbs live in separate files,
  wired via the scene tree (no `class_name` on scene scripts; cross-file calls resolve through
  `$` / `get_parent()`). A "draw" file is attached to its own child `Node2D` (Godot only draws
  from `CanvasItem`s). Ordering: a parent's `_physics_process` runs before its children's.
- **Runtime shapes.** Collision shapes are built **in code in `_ready()`**, not in the scene
  (layout is data-driven). Because of this the editor shows a "no shape" warning on the character scenes'
  `CollisionShape2D` (`character_base.tscn`, so `Player` and the NPCs) — **that is expected** (walls are built in code); don't add scene shapes.

## Running & verifying

- Main scene `res://scenes/main.tscn`.
- **Worktree editor:** `tools/editor.sh [--autorun]` opens a Godot editor on the checkout, named after the
  worktree directory (`GAME_TICKET`; Main passes it as `ticket` to the setup window, which shows it on top;
  a `--ticket=` user arg overrides it, and a run from any editor falls back to the directory name), unless
  one is already open there (it then prints that editor's pid, port and log). Each gets its own free
  command-server port (`GODOT_CMD_PORT`), importing first in a fresh worktree. `--autorun`
  makes the editor plugin `addons/ticket_autorun/` press Play once it is up.
- **The change's tests in a window:** `tools/play_tests.sh [ids…]` opens a game window on the checkout that plays the
  tests the change added or modified (since the merge-base with `origin/main`) one after another, for a person to
  watch; `show-me` runs it, `domain-testing` has the detail.
- **Verification ladder** — use the cheapest rung that proves the change:
  1. **Loads?** `godot-run` skill: headless load check (`tools/load_check.sh --import` when you add a `class_name` or a script).
     **Clean?** `tools/lint.sh [paths]` (about 14 s for the whole tree, nearly all of it the engine pass) prints every GDScript analyzer warning of the editor's
     Debugger > Errors tab (unused variable, integer division, shadowed names ...) per file, then every project lint rule
     (`tools/lint_rules/`, one section each), then gdstyle's two (`gdstyle fmt --check`: a script the formatter would change;
     `gdstyle check`: every rule of `gdstyle.toml` but `quality/*`, among them lines over 100 columns and member order); any
     finding fails it, and it runs first in every `run_tests.sh` and fails the run before a test starts. `tools/gdstyle.sh fmt PATH`
     formats a script. Fix the code; never silence a warning (`audit`).
  2. **Behaves?** `tools/run_tests.sh [words]` runs every test headless and deterministically through gdUnit4's command-line
     tool: the simulation tests (`tests/**/*_test.gd`, `GameTest`s, through their folder's wrapper suite) and the native
     pure-logic suites (`*_suite.gd` extending `UnitSuite`)
     (exit 1 on a lint finding, a failure, or any engine error/warning logged during a test). Useful flags: `--list`,
     `--changed` (the domains your uncommitted changes can break, in one run), `--id=<id>` / `--domain=a,b`
     (exact selection), `--failed` (rerun last run's failures), `--jobs=auto` (parallel shards),
     `--fail-fast`, `--summary` (failures + totals only), `--repeat=N` (flaky check), `--seed=N`,
     `--no-lint`, `--json`, `--report=FILE`, `--include-von` / `--require-von`. A failure prints actor state and a `bundle:` JSON path;
     each run's output dir also holds gdUnit's JUnit `results.xml` and HTML report.
     Writing tests: `domain-testing` skill; debugging one: `test-debug` skill. In the game, the setup
     window's **Tests** button opens the browser to play one; in the editor, the GdUnit panel runs one case, a suite or
     everything (`domain-testing`, "The GdUnit panel").
  3. **Exploratory / not yet scriptable?** `godot-run` skill: drive the live game through the dev
     command server (`tools/gcmd.py`).
  4. **Whole-AI outcomes?** `tools/match.py` scores full defender-vs-invader matches.
  **Fast enough?** `tools/run_tests.sh --domain=perf`: the performance tests (`tests/perf/`: eleven guards) hold a 5v5 and a 10v10 match, each built through `MatchBuilder` as Main builds one (its squads following their leaders, the sides in contact before the window), to one 60 fps
  frame on average and hold stress cases to their budgets: automatic fire, nav re-bakes and path queries, a whole match dying in one
  frame, a furniture pile shoved at once, house generation, hundreds of hits on one body, an NPC crowd, grenades thrown into a 5v5 and a
  frag and a stun bursting in a crowded room (`domain-testing` skill, "Performance tests"); a change to a per-frame path should leave them
  green, but for the 10v10's p95 and max, red on a quiet machine until #98 (an invader's decision weighing its grenades). Headless they measure the CPU; `tools/run_tests.sh --windowed` measures the render too.
  **What runs?** `tools/coverage/README.md`: a dev tool outside the game, kept out of it by the `coverage_isolation` lint rule.
  A bugfix starts with a failing test on rung 2 (`fix` skill).
- The relevant **`domain-<name>` skill** documents each domain's behaviour to verify (house
  generation, movement/pushing, items, interactions, combat).
