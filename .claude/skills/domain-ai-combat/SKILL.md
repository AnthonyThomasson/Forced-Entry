---
name: domain-ai-combat
description: Deep implementation detail for the AI COMBAT module (scenes/ai/behavior/combat.gd, and its throw part combat_throw.gd) — how an NPC fights with its hands: taking a shot (fire cooldown, dry-gun click, automatic bursts, backing off a gun whose barrel is against a wall), throwing a punch, throwing a grenade, the peek-and-cover cycle (peek to a clear-shot spot, fire, duck to cover) and its committed destination, the ambush, melee, fire-at-will on the move, the reload reflex, the leash a squad follower fights within, and the no-per-weapon-code rule. Use when editing scenes/ai/behavior/combat.gd or combat_throw.gd or working on how NPCs shoot, reload, take cover or step back. Complements the `domain-ai-behavior` overview and the `architecture` skill.
---

# AI · Combat module (`scenes/ai/behavior/combat.gd`, its throw `combat_throw.gd`)

A `RefCounted` that `Behavior` owns (built in `setup()`, handed the NPC's `NpcTuning` there: `setup(loco, perception, tuning)`, its tunables read live from `tuning.combat`). It owns the fire cooldown and the
peek-and-cover cycle (`phase` `"peek"`/`"cover"`, `cover_timer`, `fire_timer`, the committed `dest` and `dest_timer`, the burst and
back-off counters) and executes every combat action on the character. `Behavior` decides WHICH fight is on — it holds the engaged
contact (node, last-known position) and the `hold_ground` flag — and passes them in each call, so combat never picks a target. It reads
the world only through the perception (`has_line_to`, `combat_spots`, `note_engaged`) and `Locomotion` (`move_to`, `inside_house`).

`bind(character)` (from `Behavior.bind`) hands it the NPC's body once; no other function takes the character. API: `tick(delta)`
(cooldown), `begin_fight()` (reset to the peek phase), `can_fire_at(target)` (a
loaded gun, the known contact in range on a clear line: a shot is on), `fire_at_will(target)`
(shoot it when `can_fire_at`, once facing settles; aims at it; the watch stage calls it for the threat in every primitive, `domain-ai-watch`), `reload_due()`, `has_line_of_fire(target) -> bool` (in range on a clear line, whatever the gun's state; what `can_fire_at` adds a loaded gun to, and the entry reads for E14), `top_off() -> bool` (a tactical reload of a part-spent gun, called by the entry at the stack: starts it, true while it runs or is wanted; `docs/tactical-entry.md` E11), `ambush(node, pos)`,
`peek_cover(delta, node, pos, hold_ground, room := "")`, `melee(pos, hold_ground)` (its blow is the private `_strike` / `_punch` / `_kick`), `shoot() -> bool`,
`continue_burst()`, `apply_back_off(delta)`, `reload_if_dry()`; `signal dry`
(an empty gun was pulled on — `Behavior` flags the task resolved so the controller re-decides). Tunables, read live from the NPC's
`tuning.combat` (no copy kept, so a tunable retuned at runtime holds from the next read): `shoot_range`, `punch_range`, `ring_radius` (the radius of the ring of candidate spots; the perception's `combat_spots` lays `tuning.combat.ring_count` points on it), `cover_time`,
`fire_cooldown`, `fire_burst`, `back_off_time`, `reposition_interval`, `auto_reload`; a `Combat` built without the controller is handed
`NpcTuning.defaults()` (`tests/ai/combat/combat_waits_for_facing_test.gd`).

**Peek-and-cover** (the `engage` primitive, style `peek_cover`): in the PEEK phase move to the nearest spot with a clear shot and
fire on `fire_cooldown`, then duck; in the COVER phase hold behind a shielding spot for `cover_time` (reloading an empty gun
meanwhile) before peeking again. Positions are committed for `reposition_interval`, not re-picked every frame, so the NPC steers
smoothly. A peek shoots only once the facing has settled on the contact (`AIM_TOLERANCE`) and ducks only after a shot left the barrel (or on the click
of an empty gun, where the cover phase reloads it), not after a refused one. **Ambush** holds the covered spot and fires the moment a line opens (facing settled). (`Combat.ambush` is the ENGAGE spot's stance;
the ordered `ambush` primitive, `docs/leadership.md` LD15, is not this module's: it is `Behavior._apply_defend`'s walk and hold at a post,
and its shots are the watch stage's, `domain-ai-behavior`.) **Melee** closes to `punch_range` and strikes on the
cooldown (no cover cycle): its blow (`_strike`) kicks (`_kick`, the character's `anatomy.leg_kick()`) while standing with a gun in hand, so the gun stays in hand,
and otherwise (crouched, or no gun held) equips the fists and punches (`_punch`). With `hold_ground` (a territorial NPC fighting a contact outside), spots are restricted to inside
the house, the peek fallback holds instead of advancing, and melee won't chase out of the house. With a `room` (a member ordered to defend
it, `docs/leadership.md` LD8) the peek and cover spots are restricted to inside that room whatever the contact, and `hold_ground` is set
against a contact outside the room. **The leash** (a squad member following its leader and holding no order, `docs/leadership.md` LD23): `leash_center` (the
leader's live position, `Vector2.INF` for none: no squad, the leader itself, or a member carrying an order, which fights where the order
takes it) and `leash` (px), set every tick through `Behavior.set_leash` (the controller's reflexes, `npc_reflexes.gd` `leash_lead`); with one, `_choose_dest` keeps
the peek and cover spots within it (`_on_leash`) and, with no fire spot left, the peek fallback holds where it stands instead of closing on
the contact, and `melee` holds its ground rather than walk to a target off the leash. Which COMBAT options are offered at all is the
planner's leash filter (`domain-ai-decision`). Tests: `tests/ai/combat/leash_*` (a follower held to its leash) and
`ordered_melee_off_leash` (real Von: a member ordered to defend a hall closes on and strikes a gunman beyond its leader's leash, which a
leash on it would hold short; with `defend_room_stays_inside`, the planner's half). `magazine_low(fraction) -> bool`: whether the gun it fights with is at or below that share
of its magazine, which a follower at rest tops up (`Behavior._apply_follow` with `low_ammo_fraction`, `top_off`; LD22).

**No per-weapon code.** The behaviour never knows which gun it has. It fights with `Character.inventory.gun_slot()` (the held item if it takes ammo, else the
lowest slot that does) and reacts only to generic conditions the character reports: out of rounds, mid-reload, running, **blocked**, automatic.

**Firing** (`Combat.shoot() -> bool`, true = a round left the barrel; the fists are `_punch`). It holds fire at a run or mid-reload (cooldown kept), and while `holds_fire()`: blind with `blind_fire` false, the orchestrator's one roll
as the NPC went blind (`Behavior.set_blind_fire`, `docs/grenades.md` G15), no trigger pulled at all, so no dry click, and `continue_burst` cuts a burst;
a dry gun is a click (below); otherwise it equips the gun and, **if `weapon.blocked()` (the barrel is against a wall or object), sets
`_back_off_timer = back_off_time`, keeps the cooldown and returns false**, else calls `weapon.shoot()` and, only on success, notes engagement and starts
the cooldown. `Behavior.apply()` ends each tick with `Combat.apply_back_off`: while the timer runs it overrides `movement.move_input = -facing` (away from where the gun
points, less any part that heads into a body it knows of: `Locomotion`'s `give_way.keep_off`) and clears `movement.run_input`, so the NPC steps back until the
barrel is clear, then shoots. Callers that advance state on a shot (peek-and-cover
switching to its cover phase) wait for the back-off to finish. A pistol never reports blocked, so a chair against it changes nothing. An
`weapon.is_automatic()` gun's trigger pull is a **burst**: `_burst_left = fire_burst − 1` more rounds, fired from `Behavior.apply()` (`Combat.continue_burst`) as the gun's own
fire rate allows, ending early on a run, reload, wall or empty gun. Tunables (`tuning.combat`): `fire_burst` (3), `back_off_time` (0.45 s).
Tests: `tests/ai/combat/blocked_gun_steps_back_test.gd` (a rifle with a chair against its barrel), `pistol_fires_against_object_test.gd`.
Not modelled: a rifleman cornered with a wall behind it can still stall (bounded by the back-off timer and re-decisions); cover logic treats walls as
bulletproof though a rifle shoots through them.

**Throwing a grenade** (its part `throw`, `combat_throw.gd`, built once with the `Combat` and handed its locomotion by `setup` and the body by `bind`; it holds no `Combat`: `throw.begin(slot, spot, reach, from := Vector2.INF)`, `throw.step(delta)`, `throw.released()`, `throw.end()`; `throw.stage` `""` / `"walk"` / `"aim"` / `"windup"` / `"away"`, beside the grenade's `slot`, the `spot`, `from`, `reach`, the count carried `before` and the stage's `clock`): the `throw` primitive's hands (`docs/grenades.md` G17), also used by the
bang entry's thrower (`ItemRegistry.STUN_SLOT`, or `FRAG_SLOT` for a stack its leader ordered in with a frag, `docs/leadership.md` LD14). `reach` is how far from the spot it lets go (`AgentPerception.grenade_reach`: the range less `AgentThrow.REACH_SLACK` 15 px). With a throw spot `from` (issue #51 R13) it first walks all the way to it (`"walk"`, the throw's `SPOT_REACH` 6 px: the lob was judged from there), the gun still in hand (the watch stage keeps its eyes and gun on a threat; the caller's commit timer and the locomotion's held walk bound the walk). Then standing still (but for the last few px: a thrower farther than `reach` from the spot, because it moved on since the spot was offered, walks toward it first, within the same `START_CAP`; the bang's thrower plans a spot already within the reach), it selects the grenade's slot (`inventory.select_slot`), aims at the spot (`movement.aim_point`; the item throws to `Character.weapon.aim_target()`) and clicks `weapon.shoot()` once the facing has settled (the throw's own `_faces`, within its `AIM_TOLERANCE`, a shot's 0.15); `weapon.shoot()` answers true when the
throw STARTS (`GrenadeItem.secondary`), not for a round leaving a barrel. It never reads the contact: it throws onto the spot it was handed, and `Behavior` keeps the order (and so that spot) when the contact ages out on the way, and ends it (the NPC re-decides) when that hostile dies before the wind-up (G17). It gives up after `START_CAP` (2 s) without a start or `RELEASE_CAP` (1.5 s) without the grenade leaving the hand (`throw.step` returns `&"failed"`).
`throw.released()` is true once, on the tick the carried count has dropped (the wind-up is over); it takes the gun back in hand (`inventory.select_slot(inventory.gun_slot())`, a last grenade empties its slot by itself). It is polled by `Behavior.poll_throw`
before the evade reflex gets its plan, since the grenade just thrown is a live one the thrower may be inside the zone of.

**Ammo.** An empty gun cannot fire, so the behaviour never "fights" with one: `Combat.fire_at_will` returns early when the gun
is empty or reloading, and `Combat.shoot()` on an empty gun is a dry click that does not note engagement or call `weapon.shoot()`; it spends
`fire_cooldown` and emits `dry` (the behaviour flags the task resolved), so the NPC re-decides (the snapshot now says the gun is empty) at most once per
cooldown. `auto_reload` (`tuning.combat.auto_reload`, default on) is `Combat.reload_if_dry`, a reflex in `hold` (the server-down fallback, and after a
reload), in the cover phase of peek-and-cover and from the watch stage whenever a threat is in view outside a crossing (W3): an EMPTY gun with a spare magazine is reloaded without a decision. A reload
runs only while standing (running cancels it, so the `reload` primitive never sets `movement.run_input`). `debug_state()` / `debug_combat()`
carry `reloading`; the combat overlay shows a RELOADING badge. Tests: `tests/ai/combat/scripted_reload_decision_test.gd`,
`dry_pistol_fallback_test.gd`, `empty_pistol_no_spares_test.gd`.
