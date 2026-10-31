# AI combat module

How an NPC fights with its hands: `scenes/ai/behavior/combat.gd` (`Combat`, shots, punches, kicks, bursts, the peek-and-cover cycle, the reload reflex) and its throw part `combat_throw.gd`. Read `behavior.md` for the executor that calls it.

## Shape

- `Combat` is a `RefCounted` that `Behavior` builds in `setup(loco, perception, tuning)` and binds to the body once (`bind(character)`). It reads its tunables live from `tuning.combat` (holder `scenes/ai/tuning/npc_combat_tuning.gd`); a `Combat` built without a controller gets `NpcTuning.defaults()`.
- `Behavior` decides WHICH fight is on and passes the engaged contact into every call; `Combat` never picks a target. It reads the world only through the perception (`has_line_to`, `combat_spots`, `note_engaged`, `confinement`) and `Locomotion` (`move_to`, `give_way`).
- It owns the fire cooldown and the peek-and-cover state (`phase`, `cover_timer`, `dest`, `dest_timer`, the burst and back-off counters).
- The watch stage (`watch.md`) is the one place a threat is shot at: it calls `fire_at_will` for every primitive. `has_line_of_fire_to(node, pos)` is the single line-of-fire rule; `has_line_of_fire`, `can_fire_at`, `ambush`, the peek and the combat overlay's `fire_clear` all read it, and the entry reads `has_line_of_fire` for E14.

## Rules

- **No per-weapon code.** Fight with `inventory.gun_slot()` and react only to what the character reports: empty, reloading, running, `weapon.blocked()`, `weapon.is_automatic()`.
- **Peek-and-cover** (`engage`, style `peek_cover`): PEEK to the nearest clear-shot spot and fire, then duck; COVER holds a shielding spot for `cover_time`, reloading an empty gun. Spots are committed for `reposition_interval`, so steering stays smooth. A peek shoots only once facing settled (`AIM_TOLERANCE`) and ducks only after a round left the barrel (or on the dry click, where the cover phase reloads), not after a refused shot.
- **`Combat.ambush` is the engage spot's stance** (hold the covered spot, fire when a line opens). The ordered `ambush` primitive (LD15) is not this module's: it is `Behavior.orders` (`behavior.md`).
- **Melee** closes to `punch_range` and strikes on the cooldown. `_strike` kicks (`anatomy.leg_kick()`) while standing with a gun in hand, so the gun stays in hand; crouched or unarmed it equips the fists and punches.
- **Confinement.** `confinement.allows(p)` decides where it may fight (territory, defend room LD8, leash LD23, a held stack's room LD13/D38). `_choose_dest` keeps peek and cover spots to allowed ones, whatever the contact. With no fire spot left the peek closes on the contact if the confinement allows its spot, else holds; with no cover spot the cover phase holds. `melee` closes in only while `allows(pos)`, else swings at a contact already in reach. `Behavior.fight.hold_ground` reads the same answer. The planner's COMBAT filter works on the snapshot's frozen copy (`decision.md`). Pinned by `tests/ai/perception/confinement_suite.gd`.
- **Firing** (`shoot() -> bool`, true = a round left the barrel). Holds fire while running or reloading (cooldown kept) and while `holds_fire()` (blind with `blind_fire` false, the orchestrator's one roll at blinding, G15: no trigger pull at all, no dry click). A dry gun clicks, spends `fire_cooldown` and emits `dry` (Behavior resolves the task, so the NPC re-decides at most once per cooldown). A `weapon.blocked()` barrel (against a wall or object) sets the back-off timer, keeps the cooldown and returns false; `apply_back_off`, last in `Behavior.apply`, then steps the NPC back along `-facing` (less any part heading into a known body, `give_way.keep_off`) until the barrel is clear. Callers that advance state on a shot wait for it. An automatic gun's pull is a burst of `fire_burst` rounds, continued from `Behavior.apply` (`continue_burst`) and cut by a run, reload, wall or empty gun.
- **Reflex reload.** `auto_reload` makes `reload_if_dry` reload an EMPTY gun with a spare in `hold`, in the cover phase and from the watch stage while a threat is in view outside a crossing (W3). Reloading runs only standing (running cancels it). `top_off()` is the tactical reload of a part-spent gun at the stack (E11); `magazine_low(fraction)` lets a resting follower top up (LD22).
- **Not modelled:** a rifleman cornered against a wall can stall (bounded by the back-off timer and re-decisions); cover treats walls as bulletproof though a rifle shoots through them.

## Throw part (`combat_throw.gd`, `combat.throw`)

The hands of the `throw` primitive (G17, `docs/grenades.md`) and of the bang entry's thrower (E17, LD14): `begin`, `step`, `released`, `end`, with `stage` `""` / `"walk"` / `"aim"` / `"windup"` / `"away"`.

- Given a throw spot `from` it first walks there, gun in hand (the lob was judged from there; `SPOT_REACH`), then stands, selects the grenade slot, aims at the spot and clicks `weapon.shoot()` once `Combat.faces` holds. `weapon.shoot()` answers true when the throw STARTS.
- It never reads the contact: it throws onto the spot it was handed. `Behavior` keeps the order when the contact ages out and ends it when that hostile dies before the wind-up.
- `step` returns `&"failed"` after `START_CAP` without a start or `RELEASE_CAP` without the grenade leaving the hand.
- `released()` is true once, the tick the carried count drops; the gun comes back to hand. `Behavior.grenades.poll_throw` polls it before the evade reflex gets its plan, since the grenade just thrown is live under the thrower.

## Tests

`tests/ai/combat/` (blocked barrel, dry gun, scripted reload, leash, confinement spots), `tests/ai/grenade/` (throw and bang fallbacks). Spec: `docs/grenades.md`, `docs/cover-and-stance.md`, `docs/gaze-and-fire.md`.
