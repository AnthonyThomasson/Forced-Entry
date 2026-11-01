---
name: domain-projectile
description: Use when editing scenes/projectile/ or working on bullet impacts (fly-over, ricochet, armour, penetration), casings, the Ballistics* holders, or a grenade's burst (`Explosion`).
---

# Projectile System domain

Owns shooting and a grenade's burst. Specs: `docs/cover-and-stance.md` (H1, H2: bullet height and cover), `docs/outfits.md` (O6 to O9: armour), `docs/grenades.md` (G7 to G12: blast, fragments, flash, bang; G9: friendly fire is on, the thrower is struck like anyone). Tests: `tests/projectile/` (also `physics/frag_blast_pushes`, `tests/character/stun_*`).

## Files

- `projectile.gd` (control) + `projectile_visuals.gd` (draw); `casing.gd` + `casing_visuals.gd`; `projectile_spawner.gd` / `casing_spawner.gd` are the entry points the guns call (a bullet is named `Projectile`, `Projectile2`, … and the tests count by that name).
- `shot.gd` (`Shot`): a bullet's ballistics (`damage`, `muzzle_speed`, `penetration`, `max_range`, `strikes_shooter`, …), where a field left alone is the pistol round's. A gun and a grenade's fragments each fill one.
- `explosion.gd` (`Explosion`), `cover_rule.gd` (`CoverRule`).
- Tuning: `BallisticsFlightConfig` (speeds, `bullet_height`, `cover_flyover_scale`, the surfaceless-collider `wall_*`), `BallisticsPenetrationConfig` (penetration, exit probe, blood carry), `BallisticsRicochetConfig`. The burst's numbers are the grenade's row in `GrenadeConfig` (Items), received as a plain dict.

## Impact model

A bullet sweeps a raycast each physics frame and resolves **every collider it crosses** (`_resolve`) against that object's surface (`coverage`, `penetration`; a character gives `get_surface_at(height, travel)` because its armour depends on where the round strikes). It flies until `speed < projectile_min_speed` or `max_distance`. Non-solid decor has no collider. Outcomes, first match wins:

1. **Fly over**: `height` ≥ the collider's cover height; nothing happens and nothing is posted. A bullet draws one `height` at spawn and keeps it through ricochets and penetrations, so cover and the body behind it are judged consistently (H1, H2).
2. **Ricochet**: surface penetration ≥ `penetration_bounce_min` and a glancing angle (`bounce_square_max`).
3. **Armour** (surface has `stop_power`): stopped when `penetration_power × speed_factor < stop_power` (outcome `blocked`); otherwise the surface's material becomes its `inner_material` (flesh) and the round always penetrates. A stopped round reads `HitInfo.penetrated == false`.
4. **Penetrate**, or **blocked** when `speed < BallisticsPenetrationConfig.min_speed / penetration_power`.

Damage scales by squareness and `speed_factor` (speed / the round's own `muzzle_speed`), so a gun's `damage` is what it deals at full speed head-on.

**Two penetrations.** The target's `P` belongs to its surface (flesh 15, wall 100); the bullet's power `penetration_power` comes from the gun's `Shot` (`GunConfig`). A higher power loses less speed to the same surface and needs less speed to get through: a pistol round dies in a wall where a rifle round leaves it fast enough to wound someone behind.

**What a damaging outcome does.** `body.take_hit(info)` (interface 3; `HitInfo.height` is what the character turns into a hit zone), then the `hit` signal, then `&"hit"` on `EventBus` through `Projectile.post_hit`, the one place that payload is built (the blast posts through it too; interface 10). A fly-over posts nothing.

**Exit and blood carry.** A penetrating hit fills `HitInfo.has_exit` / `exit_position` / `exit_normal` (`_find_exit` probes back from `exit_probe_distance`; none found = thicker than the probe). A round that penetrated `blood_material` (flesh) carries that blood to the next non-flesh surface within `blood_carry_distance`.

## Casings

`CasingSpawner` tracks them with the `Despawner`; the toss is `Debris.toss` (Physics, interface 4; `casing.gd` preloads `physics/debris.gd` as `Debris`), then the casing rests at `DrawLayers.LYING`.

## Explosion: a grenade's burst

`ThrownGrenade` (Items) calls `Explosion.frag` / `Explosion.stun` when its fuse is out. Both post `&"explosion"`, call `Physics.spawn_explosion`, then do their work on the group `characters` under `world` (dead ones included).

- **The line is the cover rule.** `_reach` casts burst → body on `PhysicsLayers.SOLID`: a wall always stops it, a piece of furniture only when its coverage is above the **body's height** (a character's is its posture's), so a crouched character behind a couch is shielded and a standing one is not. `_walk` is the one walk past what does not stop the line; a line that has cleared `MAX_CLEARED` pieces counts as stopped. The flash passes a finite `cover_reach` (furniture counts only when the body is within `flash_cover_reach` of it); the bang passes `WALLS_ONLY` (furniture muffles nothing).
- **AI reads the same rule** through two read-only statics (interface 3): `Explosion.shields(space, burst, p, cover: CoverRule)` and `Explosion.first_stop(space, a, b, height, exclude)`. A change to the rule moves the AI's grenade dodging with it.
- **Frag blast** (`_blast`): damage with distance, `take_hit` with `speed_factor` 0, `&"hit"` outcome `&"blast"` (Audio ignores it; the burst has its own sound), then a shove capped at `mass * blast_max_speed`: `blast_push` on a character (dead: its ragdoll is thrown and woken), `apply_impulse` on furniture. The thrower is `attacker`, so the AI's "attacked me" hostility sees a victim's own teammate as an attacker when it throws.
- **Fragments** (`_fragments`) are real bullets from one shared `Shot` with `strikes_shooter` on, so cover, penetration, ricochet, blood and impact sounds all apply. The row's `fragment_damage` is set as the `Shot`'s `damage` outright (not added to a base).
- **Stun**: flash by sight and bang by range, both through `Character.take_stun(blind, deaf)`; within `point_blank` also `take_damage`.

**Interfaces:** 3 (hittable), 4 (`Physics.spawn_explosion`, `Debris.toss`), 5 (pushable), 6 (guns → `ProjectileSpawner` / `CasingSpawner`; `ThrownGrenade` → `Explosion`), 7 (what `Explosion` calls on a character), 10 (`&"hit"`, `&"explosion"`), 11 (`PhysicsLayers`, `DrawLayers.LYING`), 15 (`GameLog`: the shot lines).
