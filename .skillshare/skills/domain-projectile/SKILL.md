---
name: domain-projectile
description: Use when editing scenes/projectile/ or working on bullet impacts (the 3D ray, ricochet, armour, penetration), casings, the Ballistics* holders, or a grenade's burst (`Explosion`).
---

# Projectile System domain

Owns shooting and a grenade's burst. Specs: `docs/cover-and-stance.md` (H1, H2: a bullet is a 3D ray, and cover by real height), `docs/outfits.md` (O6 to O9: armour), `docs/grenades.md` (G7 to G12: blast, fragments, flash, bang; G9: friendly fire is on, the thrower is struck like anyone). Tests: `tests/projectile/` (also `physics/frag_blast_pushes`, `tests/character/stun_*`).

## Files

- `projectile.gd`; `casing.gd`; `projectile_spawner.gd` / `casing_spawner.gd` are the entry points the guns call (a bullet is named `Projectile`, `Projectile2`, … and the tests count by that name).
- `shot.gd` (`Shot`): a bullet's ballistics (`damage`, `muzzle_speed`, `penetration`, `max_range`, `strikes_shooter`, `height` (where it starts, px up) and `rise` (its slope), …), where a field left alone is the pistol round's. A gun and a grenade's fragments each fill one.
- `explosion.gd` (`Explosion`), `cover_rule.gd` (`CoverRule`).
- 3D (#193): `projectile_mesh_config.gd` (`ProjectileMeshConfig`), `art/projectile_meshes.gd` (`ProjectileMeshes`), `art/shot_layer.gd` (`ShotLayer`): see "Tracers and casings in 3D".
- Tuning: `BallisticsFlightConfig` (speeds, `vertical_spread_scale`, the surfaceless body's `wall_penetration`), `BallisticsPenetrationConfig` (penetration, exit probe, blood carry), `BallisticsRicochetConfig`. The burst's numbers are the grenade's row in `GrenadeConfig` (Items), received as a plain dict.

## Impact model

A bullet is a **3D ray in the twin space** (`TwinSpace`, interface 29): it has a plan `position`, a `height` (px above the floor, what its line gives it) and a plan `direction` with a `rise` (px of height per px of plan travel; the 3D travel is `(direction, rise)` normalised). `ProjectileSpawner.spawn(position, direction, parent, shot)` starts it at `shot.height` (default a standing muzzle) climbing `shot.rise`; a gun fills both (`GunItem._rise`: from the muzzle's height by posture to the `weapon.aim_height()` over the aim point, plus the vertical spread and a stunned aim's lift: `BallisticsFlightConfig.vertical_spread_scale`). Each physics frame it casts a `PhysicsRayQueryParameters3D` (`PhysicsLayers.TWIN_ALL`, `hit_from_inside`) forward and resolves **every twin it crosses** (`_resolve`), mapping the collider to its 2D body with `TwinSpace.owner_of` and reading that body's surface (`penetration`, `material`; a character gives `get_surface_at(height, travel)` because its armour depends on the height the round strikes at). It flies until `speed < projectile_min_speed` or `max_distance` (3D px). Non-solid decor has no twin. What its line passes over or under it never touches: there is no fly-over roll (H1, H2). The shooter's own twin is looked through (unless `strikes_shooter`); the ground (a floor has no body) spends a round that falls into it. Outcomes at a strike, first match wins:

1. **Ricochet**: surface penetration ≥ `penetration_bounce_min` and a glancing angle (`bounce_square_max`: squareness is `|travel · normal|` in 3D, the twin's face normal): the 3D travel is reflected.
2. **Armour** (surface has `stop_power`): stopped when `penetration_power × speed_factor < stop_power` (outcome `blocked`); otherwise the surface's material becomes its `inner_material` (flesh) and the round always penetrates. A stopped round reads `HitInfo.penetrated == false`.
3. **Penetrate**, or **blocked** when `speed < BallisticsPenetrationConfig.min_speed / penetration_power`. A penetration deflects the travel a little in both axes.

Damage scales by squareness and `speed_factor` (speed / the round's own `muzzle_speed`), so a gun's `damage` is what it deals at full speed head-on. A character's twin is an upright cylinder and its squareness is taken on the plan heading alone (pitch does not glance a body).

**Two penetrations.** The target's `P` belongs to its surface (flesh 15, wall 100); the bullet's power `penetration_power` comes from the gun's `Shot` (`GunConfig`). A higher power loses less speed to the same surface and needs less speed to get through: a pistol round dies in a wall where a rifle round leaves it fast enough to wound someone behind.

**What a damaging outcome does.** `body.take_hit(info)` (interface 3; `HitInfo.height` is the real height the round met the body at, which the character turns into a hit zone by the posture's `BodyHeights` bands), then the `hit` signal, then `&"hit"` on `EventBus` through `Projectile.post_hit`, the one place that payload is built (the blast posts through it too; interface 10). A round that clears a piece touches nothing and posts nothing.

**Exit and blood carry.** A penetrating hit fills `HitInfo.has_exit` / `exit_position` / `exit_normal` (plan values: `_find_exit` probes back from `exit_probe_distance`; none found = thicker than the probe). `HitInfo.position` and `normal` are the plan's (the normal's floor part, zero for a face that looks straight up or down). A round that penetrated `blood_material` (flesh) carries that blood to the next non-flesh surface within `blood_carry_distance`.

**Ray reuse.** A bullet owns one `RayQuery` (inner class of `projectile.gd`): a single `PhysicsRayQueryParameters3D`
(`hit_from_inside` set once) serves every forward sweep and every `_find_exit` probe, and holds the bullet's `exclude` list
(penetrated twins and the shooter's own). Each probe passes its own copy of that list.

## Casings

`casing_config.gd` (`CasingConfig`) tunes the flight. `CasingSpawner.spawn(position, direction, parent, height)` tracks them with the `Despawner`. A casing flies in the twin 3D space with General's `SmallFlight` (`CasingConfig`: size, hop, bounce, friction, `max_time`): let go at the port's height (`Gun.secondary` passes the shot's muzzle height), it falls, bounces off a wall's real face, lands on a desk's top or the floor, skids and rests; `altitude()` and `is_resting()` are what the `ShotLayer` reads.

## Tracers and casings in 3D (`ProjectileMeshes`, `ShotLayer`; interface 27)

Main's 3D view calls `ProjectileMeshes.install(mirror, world)` once the match is built: a `ShotLayer` (a `Node3D` under the mirror) follows the children of `world` that join and leave (`child_entered_tree`, matched by script: a `Projectile`, a `Casing`), so a spawner changes nothing and nothing is looked up per frame. Hundreds a second are too many for a node each, so each kind is one `MeshNodes.batch` in a `MeshPool` (Art): nothing is allocated while the game runs.

- **Tracer:** a bright bar (`tracer_length` × `tracer_width` px, `MeshNodes.glow`: lit whatever the light, no real light) along the bullet's `direction`, its tip on the bullet, at the bullet's own `height` (real px above the floor, never under `tracer_floor`); ballistics are untouched. Over the last `tracer_fade` px of `range_left()` it shortens to nothing; it goes with the bullet (a hit, the range, a penetration spent). Written each frame a bullet flies (it moves each frame); the layer does not process while none does. `tracer_capacity` places: a bullet past them shows none, and the layer says so once (`GameLog.say`).
- **Casing:** a brass box as long and wide as the 2D art (`casing_size`), one batch of `Despawner.max_scene_objects` (read at install), so the 3D shows what the 2D world keeps and loses one when the `Despawner` frees it; full, it says so once. Written each frame it flies at `Casing.altitude()` (real px: the floor or a piece's top), then once where its node came to rest and turned as it is: nothing runs once they all lie.
- Tests: `tests/projectile/tracer_mesh_test.gd`, `casing_mesh_test.gd` (headless, read the layer's `tracer_frame` / `casing_frame`); cost `tests/perf/shot_layer_cost_test.gd` (a full tracer pool, a Despawner's cap of casings: `_process` ms); pictures `tests/items/items_projectile_mesh_windowed_test.gd`. Hit particles, debris and the explosion's look are Physics' (`domain-physics/meshes.md`).

## Explosion: a grenade's burst

`ThrownGrenade` (Items) calls `Explosion.frag` / `Explosion.stun` when its fuse is out. Both post `&"explosion"`, call `Physics.spawn_explosion`, then do their work on the group `characters` under `world` (dead ones included).

- **The line is the cover rule, real 3D (#194 D10; no coverage number).** `frag` / `stun` take the burst's `altitude` (`ThrownGrenade.altitude()`: a grenade resting on a desk bursts at the desk top) and lift the plan point to `burst := PlanSpace.lift(at, altitude + BURST_CENTRE)`. `_reach` casts burst → each point of the body (`SightRay.target_heights`: head, chest, hips of its posture; the eye for the flash; the ground for a dead body) on `SightRay.MASK` (twin world + vehicles): a wall, a door, a vehicle or a piece of furniture on the line stops it, so a ducked body behind a couch is shielded, a standing one far enough behind it is in its shadow, and one close behind it is hit over the back. `_walk` is the one walk past what does not stop the line (a twin with no body, or a character, is looked through); a line that has cleared `MAX_CLEARED` pieces counts as stopped. The flash passes a finite `cover_reach` (furniture counts only when the body is within `flash_cover_reach` of the face of it nearest the body, `_against`); the bang passes `WALLS_ONLY` (furniture muffles nothing).
- **AI reads the same rule** through two read-only statics (interface 3): `Explosion.shields(space, burst: Vector3, p, cover: CoverRule)` and `Explosion.first_stop(space, burst: Vector3, to, posture)`. A change to the rule moves the AI's grenade dodging with it.
- **Doors.** A house `Door` (interface 24) is a full-height wall of the twin space with its material's `penetration`, so a round penetrates it by the usual rule (a hollow door slows a pistol round a little, a steel one past `min_speed`, not a rifle round) and `take_hit`s it. `_bodies_near` skips a `StaticBody2D` that cannot take a shove (a wall) but not one with `apply_impulse` (a door, an `AnimatableBody2D`); a door between a burst and another body shields it like a wall (`_walk`).
- **Frag blast** (`_blast`): damage with distance, `take_hit` with `speed_factor` 0, `&"hit"` outcome `&"blast"` (Audio ignores it; the burst has its own sound), then a shove capped at `mass * blast_max_speed`: `blast_push` on a character (dead: its ragdoll is thrown and woken), `apply_impulse` on furniture. The thrower is `attacker`, so the AI's "attacked me" hostility sees a victim's own teammate as an attacker when it throws.
- **Fragments** (`_fragments`) are real bullets from one shared `Shot` with `strikes_shooter` on, 3D rays over the upper hemisphere from the burst point at its real altitude (`shot.height`, `shot.rise`: azimuth jittered round the circle, elevation `sin = q^fragment_flatness`, `MAX_ELEVATION_SINE` capping a vertical one; a fragment is spent past `FRAGMENT_CEILING`, 100 px up, where nothing is left to strike), so cover, penetration, ricochet, blood and impact sounds all apply. The row's `fragment_damage` is set as the `Shot`'s `damage` outright (not added to a base). The damage and flatness (12, 6) are tuned so an exposed standing body loses (HP, after the hit zone's share) what it lost when they flew level, per distance band within 15%, and 9% of the hits reach the torso and head so a vest has fragments to stop (`projectile/frag_fragments_exposed_by_distance`, `frag_fragments_stopped_by_vest`, `docs/grenades.md` G8: the two pull against each other).
- **Stun**: flash by sight and bang by range, both through `Character.take_stun(blind, deaf)`; within `point_blank` also `take_damage`.

**Interfaces:** 12 and 27 (meshes: Art's mesh kit, the `WorldMirror`), 3 (hittable, a door too), 4 (`Physics.spawn_explosion`, `Debris.toss`), 5 (pushable), 6 (guns → `ProjectileSpawner` / `CasingSpawner`; `ThrownGrenade` → `Explosion`), 7 (what `Explosion` calls on a character), 10 (`&"hit"`, `&"explosion"`), 11 (`PhysicsLayers`), 15 (`GameLog`: the shot lines).
