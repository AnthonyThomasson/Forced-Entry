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
   (a blast hit carries `speed_factor` 0 and `height` −1: its shove is the grenade's own `blast_impulse`, applied through the pushable contract (interface 5), a
   character's through `blast_push`); a melee punch shoves through the "pushable"
   contract (interface 5), deals its damage through `take_damage(amount)` (the character's plain damage entry, no HitInfo;
   tests wound a character with it too) and does **not** deform, and reads `get_surface()` only for the struck
   `material` it posts. `Explosion` finds the characters under the world by the group `characters` (interface 7), reads their `is_dead`, `facing`, `get_surface()`, and calls
   `take_stun` / `take_damage` / `blast_push` / `take_hit` on them, and `apply_impulse` on a pushable (capped by `get_mass()`): the sanctioned surface. Its
   cover rule (G7, `docs/grenades.md`) is published as two read-only line queries the AI's perception asks of a grenade, so the AI keeps no copy:
   `Explosion.shields(space, burst, p, cover: CoverRule) -> bool` (`CoverRule`, `projectile/cover_rule.gd`: `height`, `exclude`,
   `cover_reach` := INF; whether a wall, or a piece of furniture whose `coverage` is above `height`, stands between a burst and a body
   `height` tall at `p`; with a finite `cover_reach`, a stun's flash, a piece only when `p` is within that many px of it) and `Explosion.first_stop(space, a, b, height, exclude) -> Dictionary` (the first wall or piece on the line that
   stops it for that height, as its ray hit, or `{}`). An object also carries `object_name` (its display name), which the AI's wording reads.
