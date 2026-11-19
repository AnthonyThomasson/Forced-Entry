3. **Objects/Character/Vehicles ↔ strikers: the "hittable" contract**
   Every world object (furniture **and** walls), `character.gd` and `vehicle.gd` implement:
   - `get_surface() -> Dictionary` → `{ penetration, material, color }`. A bullet reads `penetration`, `material`
     and `color`: what it strikes is decided by where its 3D line meets the body's twin (`TwinSpace.owner_of` maps the twin it hits
     to the body that answers here: `docs/cover-and-stance.md`). What a body covers is its real shape in the twin
     space (`PieceHeights`, interface 28; a character's posture heights, `BodyHeights`, interface 11): there is no coverage number.
   - `take_hit(hit: HitInfo) -> void`.
   - optionally `get_surface_at(height, direction) -> Dictionary` (the character, where its armour lies, `docs/outfits.md`): the surface
     a round at that height along that direction meets: `get_surface()`, or over armour that surface with the armour's `penetration`,
     `material`, `color` plus `stop_power` (a round whose power × speed factor is below it is stopped) and `inner_material` (what a
     round that beats it strikes: flesh). The projectile asks it before `get_surface()` when it exists.
   - an object also carries `object_name` (display name), which the AI's wording reads.

   `HitInfo` (`physics/hit_info.gd`): `position, normal, direction, damage, speed_factor, penetrated, source`, `has_exit` /
   `exit_position` / `exit_normal` (where a penetrating bullet left the body), `blood` (0..1, blood a bullet carries onto the next
   surface), `height` (px above the floor the striker met the body at, real: it picks a character's hit zone by the posture's `BodyHeights` bands; −1 = none: a blast strikes the whole body) and `spray_direction()`.

   The projectile decides the ballistic outcome, then hands the struck body a `HitInfo`; the body decides what a hit *does to it*: an
   object spawns debris (interface 4); a character is dented, throws debris (blood, or its armour's chips when armour stops the round)
   and bleeds (`BloodWound`); a vehicle is dented (`Deformable`), throws debris, is shoved at the hit (`Physics.impact_impulse`) and is
   never destroyed. A round that meets a `stop_power` and does not beat it is blocked; one that beats it always penetrates, so on an
   armoured body `penetrated == false` reads "stopped by the armour" (only the armour's blunt share lands, no wound).

   Strikers that call `take_hit`: the projectile, and the grenade's `Explosion` (Projectile System, `Explosion.frag`: a blast hit carries
   `speed_factor` 0 and `height` −1; its shove is the grenade's `blast_impulse` through the pushable contract, interface 5, and for a
   character `blast_push`). A melee punch or kick shoves through the pushable contract, deals damage through `take_damage(amount)` (the
   character's plain damage entry, no `HitInfo`; tests wound with it too), or through the optional `take_blow(kind, amount, impulse, height := -1.0)`
   (`kind` `&"punch"` or `&"kick"`, `MeleeBlow.kind`; `height` the strike's real height in px, -1 unknown, #194 doors3d) on a body that has it (a `Door`), does **not** deform, and reads `get_surface()` only for the
   struck `material` it posts.

   A world `Door` (interface 24) implements it too: `get_surface()` is its material's `penetration` (the door is a full-height wall in the twin space) and, for the
   glass-panel door only, `transparent: true` (sight looks through a `transparent` surface: `SightRay`, which the AI's
   `AgentVision` and Vision's cone both use). A door's `transparent` is fixed at spawn: Vision
   caches it for the piece's life (a piece's sight height is its twin's top, 28, 29). It takes `take_hit` for a round or a blast (`speed_factor` 0, no height) and `take_blow` for
   a punch or a kick (`take_damage`: a punch).

   `Explosion` finds characters by the group `characters` (interface 7), reads `is_dead`, `facing`, `get_surface()`, calls `take_stun` /
   `take_damage` / `blast_push` / `take_hit` on them and `apply_impulse` on a pushable (capped by `get_mass()`): the sanctioned surface.
   Its cover rule (G7, `docs/grenades.md`) is two read-only line queries the AI's perception asks of a grenade (a live one, its own
   throw, or the frag or stun an entry may throw in, `docs/leadership.md` LD15), so the AI keeps no copy:
   `Explosion.shields(space, burst: Vector3, p, cover: CoverRule) -> bool` (`CoverRule`, `projectile/cover_rule.gd`: `posture` := `BodyHeights.STAND`,
   `cover_reach` := INF; whether the real 3D line from `burst` (`PlanSpace.lift(landing, altitude + Explosion.BURST_CENTRE)`) to every sight point of a body of that posture at `p`
   meets a wall, a door, a vehicle or a piece of furniture; a finite `cover_reach` = a stun's flash, the line to the eye only, counts a piece only when `p` is within that many px of the face of it
   nearest `p`) and `Explosion.first_stop(space, burst: Vector3, to: Vector2, posture) -> Dictionary` (the first thing on the line to that posture's chest that stops it, as its ray hit with
   a plan `position`, or `{}`). `space` is the twin space (`PhysicsDirectSpaceState3D`, `TwinSpace.space_of(node)`); null (no twin space) shields nothing and stops nothing.
