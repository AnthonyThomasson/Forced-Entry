3. **Objects/Character/Vehicles ↔ strikers: the "hittable" contract**
   Every world object (furniture **and** walls), `character.gd` and `vehicle.gd` implement:
   - `get_surface() -> Dictionary` → `{ coverage, penetration, material, color }`. `coverage` is a height on a 0–100 scale: a bullet
     flies at one height and strikes what stands above it (a character's is its posture's; `docs/cover-and-stance.md`).
   - `take_hit(hit: HitInfo) -> void`.
   - optionally `get_surface_at(height, direction) -> Dictionary` (the character, where its armour lies, `docs/outfits.md`): the surface
     a round at that height along that direction meets: `get_surface()`, or over armour that surface with the armour's `penetration`,
     `material`, `color` plus `stop_power` (a round whose power × speed factor is below it is stopped) and `inner_material` (what a
     round that beats it strikes: flesh). The projectile asks it before `get_surface()` when it exists.
   - an object also carries `object_name` (display name), which the AI's wording reads.

   `HitInfo` (`physics/hit_info.gd`): `position, normal, direction, damage, speed_factor, penetrated, source`, `has_exit` /
   `exit_position` / `exit_normal` (where a penetrating bullet left the body), `blood` (0..1, blood a bullet carries onto the next
   surface), `height` (0..100, picks a character's hit zone; −1 = none: a blast strikes the whole body) and `spray_direction()`.

   The projectile decides the ballistic outcome, then hands the struck body a `HitInfo`; the body decides what a hit *does to it*: an
   object spawns debris (interface 4); a character is dented, throws debris (blood, or its armour's chips when armour stops the round)
   and bleeds (`BloodWound`); a vehicle is dented (`Deformable`), throws debris, is shoved at the hit (`Physics.impact_impulse`) and is
   never destroyed. A round that meets a `stop_power` and does not beat it is blocked; one that beats it always penetrates, so on an
   armoured body `penetrated == false` reads "stopped by the armour" (only the armour's blunt share lands, no wound).

   Strikers that call `take_hit`: the projectile, and the grenade's `Explosion` (Projectile System, `Explosion.frag`: a blast hit carries
   `speed_factor` 0 and `height` −1; its shove is the grenade's `blast_impulse` through the pushable contract, interface 5, and for a
   character `blast_push`). A melee punch or kick shoves through the pushable contract, deals damage through `take_damage(amount)` (the
   character's plain damage entry, no `HitInfo`; tests wound with it too), or through the optional `take_blow(kind, amount, impulse)`
   (`kind` `&"punch"` or `&"kick"`, `MeleeBlow.kind`) on a body that has it (a `Door`), does **not** deform, and reads `get_surface()` only for the
   struck `material` it posts.

   A world `Door` (interface 24) implements it too: `get_surface()` is coverage 100 with its material's `penetration` and, for the
   glass-panel door only, `transparent: true` (sight looks through a `transparent` surface: `SightRay.coverage_of`, which the AI's `AgentVision.sight_hit` and Vision's cone both use). A piece's `coverage` and a door's `transparent` are fixed at spawn: Vision caches them for the piece's life. It takes
   `take_hit` for a round or a blast (`speed_factor` 0, no height) and `take_blow` for a punch or a kick (`take_damage`: a punch).

   `Explosion` finds characters by the group `characters` (interface 7), reads `is_dead`, `facing`, `get_surface()`, calls `take_stun` /
   `take_damage` / `blast_push` / `take_hit` on them and `apply_impulse` on a pushable (capped by `get_mass()`): the sanctioned surface.
   Its cover rule (G7, `docs/grenades.md`) is two read-only line queries the AI's perception asks of a grenade (a live one, its own
   throw, or the frag or stun an entry may throw in, `docs/leadership.md` LD15), so the AI keeps no copy:
   `Explosion.shields(space, burst, p, cover: CoverRule) -> bool` (`CoverRule`, `projectile/cover_rule.gd`: `height`, `exclude`,
   `cover_reach` := INF; whether a wall, or furniture whose `coverage` is above `height`, stands between a burst and a body `height`
   tall at `p`; a finite `cover_reach` = a stun's flash counts a piece only when `p` is within that many px of it) and
   `Explosion.first_stop(space, a, b, height, exclude) -> Dictionary` (the first wall or piece on the line that stops it at that height,
   as its ray hit, or `{}`).
