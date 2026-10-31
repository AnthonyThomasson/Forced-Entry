# Grenades

Spec: `docs/grenades.md` G1 to G6 and G10 (carrying, throwing, flight, fuse). The burst itself is `Explosion` (`domain-projectile`). Tests: `tests/items/grenade_*`.

## Files

- `grenade.gd` (`GrenadeItem`) + `stun_grenade.gd` / `frag_grenade.gd` (each only names its row: `super(KIND)`).
- `thrown_grenade.gd` (`ThrownGrenade`): the live world node, group `live_grenades`. `grenade_throw.gd` (`GrenadeThrow`: `kind`, `from`, `to`, `thrower`, `style`) is what `ThrownGrenade.spawn(throw, parent)` takes; `grenade_course.gd` (`GrenadeCourse`) carries the `passed` bodies of one throw's sweep.
- `grenade_spoon.gd` (`GrenadeSpoon`, a tracked `DroppedItem` popped at release); art in `weapon-looks.md`.
- `grenade_config.gd` (`GrenadeConfig`): one row per kind (fuse, windup, `max_range`, `throw_speed`, `arc_height`, `restitution`, `friction`, the effect numbers `Explosion` reads) beside the flight numbers every kind shares. The stun's effect on a body is `CharacterStunConfig`.

## Contract

- A grenade is a **count** (`uses_left()`; every other item answers −1 and `is_throwable()` is false). `Character` empties a slot whose count reached 0 and takes up the gun, else the fists. Loadout counts `stuns` / `frags` are 0..3.
- **`throw_stats()` is the one read the AI throws by** (interfaces 6 and 7): `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`, made by `GrenadeConfig.stats_of(kind, row)` (`flash_cover_reach` is INF for a frag). `Character.inventory.throw_stats(slot)` forwards it and a live `ThrownGrenade.throw_stats()` answers from the row it was thrown with. Tests: `items/grenade_throw_stats_test`, `ai/grenade/grenade_range_follows_the_item`.
- `secondary` starts the throw: the `throw` stance for `windup`, counted in `tick`; a death or a slot switch during it throws nothing. `_release` spends one, builds the `GrenadeThrow` from the hand's position, `user.weapon.aim_target()` and the item's weapon style, pops the spoon and posts `&"throw"`.

## Flight

`ThrownGrenade` flies a lob **planned** at the throw, then **fitted to the floor**:

- `_plan` solves flight time and gravity so the grenade comes to *rest* at the aim, simulated with the same `Motion` integrator the node then runs; the first touchdown is capped at `max_range`.
- `_fit` flies that lob over the world as it is (`_rest_in`, through the node's own `_sweep` / `_first_strike`: the same walls, furniture and bodies). If it rests more than `FIT_NEAR` from the aim (a sofa on the skid's way kicked it back), longer lobs are tried (`FIT_STEP` further out each, up to `max_range`) and the one resting nearest the aim is thrown. So a grenade aimed behind low cover is lobbed over it: about one simulated flight per throw in the open, up to ~30 behind cover. Test: `items/grenade_lobbed_over_cover`.
- In flight it skips furniture whose `coverage` is below its height and bounces off the rest (and the living) with `restitution`.
- **The thrower's own body is passed for the first `THROWER_CLEAR` px**, in the sweep and in the plan alike (`GrenadeCourse.passed`, in the query's `exclude`): it leaves the hand about 16 px from the body centre, so a pixel used to decide whether a throw struck its thrower. Test: `items/grenade_passes_its_thrower`.
- It posts `&"grenade"` (`bounce` / `rest`) and, when the fuse ends, calls `Explosion.frag` / `Explosion.stun` (`(at, world, source, row)`). Draw layer: `DrawLayers.ABOVE` while high, `LYING` low (interface 11).
