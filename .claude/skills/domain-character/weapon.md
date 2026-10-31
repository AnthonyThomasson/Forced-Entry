# Character weapon use: firing, ammo, raise, grenades, stun

Components: `weapon` (`character_weapon.gd`), `ammo` (`character_ammo.gd`), `inventory` (`character_inventory.gd`), `stun` (`character_stun.gd`). The items themselves are `domain-items`. Tests: `tests/character/long_gun_*`, `reload_blocked_test.gd`, `stunned_*`, `tests/items/`.

## Firing

`weapon.shoot() -> bool` runs the held item's `secondary` and returns false when busy, running, reloading, `weapon.blocked()` or the gun is still cycling. `_physics_step` ticks every carried item before the controller runs, so a gun's cooldown is in step with the frame that pulls the trigger. A controller re-presses `shoot()` every frame while the trigger is held and `weapon.is_automatic()` (`player_controller.gd` reads `Keybinds.is_fire_pressed()`; the test puppet has `hold_fire(on)`).

## A long gun against a wall (the raise)

An item whose `raises_at_contact()` is true (SMG, rifle) is judged every frame by `weapon.update_raise(delta)`, after `facing` is set and before `anatomy.step` (skipped in an interaction).

- The barrel is a ray from beside the body centre along the aim, as far as the gun reaches **held normally**: the item's *un-raised* stance forward plus `muzzle_ahead()`. Using the raised stance would let the pulled-up gun clear the ray and drop again.
- `anatomy.hands.solid_distance(from, dir, max_len)` does the cast (`HAND_MASK`) and **ignores other characters**: a gun against a person is not against a wall, and a dead body is on no layer.
- It blocks at once when something is within reach and stays blocked until `CharacterStanceConfig.weapon_contact_margin` of clearance, so it does not flicker at the edge. `weapon.raise()` (0..1) eases toward it at `weapon_raise_speed` for the art, and `weapon.stances()` asks the item for `raised_stance(hand)`.
- The raise joins `_redraw_key_of` in `character_visuals.gd` (rounded to `REDRAW_RAISE_STEP`), or an idle body would not repaint.
- **`inventory.select_slot`, `inventory.set_loadout` (`weapon.reset_raise()`) and `weapon.shoot()` itself re-judge it at once.** A controller acts before the frame's own check runs, and on a character's first frame none has run, so trusting last frame's `_blocked` let a long gun fired point-blank into a wall leave through it. Tests: `long_gun_wall_raise_test.gd` (incl. a shot on the first frame), `long_gun_hold_test.gd`.
- `blocked()` is judged in every posture. A pistol is never blocked: the wall pushes its hand back.

## Ammo and reloading

`ammo` carries the spare magazines (`Magazine` items) beside the inventory: never in `_items`, so no key or interaction selects them. They come from `ammo.spare_magazine_types` (default: two standard magazines per gun, via `ammo.restock` in `_ready`) and the loaded gun from `inventory.start_rounds` (negative = full); tests and sandboxes set both through `actor(..., props)` (`"ammo:spare_magazine_types"`, `"inventory:start_rounds"`).

`ammo.reload()` (R, or the AI's reload primitive) starts a timer of the held item's `ammo.reload_time()` if `ammo.can_reload(character)` says a carried magazine would add rounds, and sets the item's `ammo.reloading` flag (a gun's support hand eases to the `reload` stance). `ammo.update(delta)` runs right after the controller: it cancels when the character is busy, running or no longer holds that item, else counts down and calls `item.ammo.finish_reload(character)`. Switching slot, a ride's first pose and dying cancel it (`ammo.cancel()`); magazines are lost with the body. `weapon.shoot()` is ignored mid-reload. Test: `tests/character/reload_blocked_test.gd`.

`inventory.gun_slot()` is the gun it fights with (the held item if it takes ammo, else the lowest slot that does, else −1): how the AI finds its weapon without knowing which.

## Loadout

`inventory.set_loadout(kit: CharacterKit)` (Items' vocabulary, `items/character_kit.gd`) rebuilds the inventory from `ItemRegistry.inventory_for(...)`, the carried magazines (`kit.spare_types` → `ammo.restock`) and the held slot, dropping any reload and re-judging the raise. `MatchBuilder.arm` calls it through `LoadoutConfig.apply` (`domain-items`). A test that does not call it keeps `default_inventory()` (`inventory.stock()` at `_ready`, holding the root's `start_slot`).

## Grenades and the stun (spec `docs/grenades.md` G1, G13)

- `inventory.item_count(slot)`, `inventory.throw_stats(slot)` (the AI throws by it, `domain-items` (`grenades.md`)) and `inventory.throw_release_offset(slot)` (where the grenade leaves the hand, standing: the `throw` stance's `forward` and `lateral` for the item's `weapon_hand()`, as `Vector2(ahead, right)` in the character's frame; the AI judges a lob from it; test `tests/ai/grenade/grenade_lob_follows_throw_stance_test.gd`).
- `inventory.tick` erases a grenade slot whose last grenade is thrown and, if it was held, selects `inventory.gun_slot()` (else the fists).
- `take_stun(blind, deaf)` (an explosion's hook) hands it to `stun.take`, which keeps the longer of the old and new timers (blind and deaf each) and posts `&"stun"`. `stun.update` counts it down; `stun.view()` feeds the UI (`StunScreen`). Character reads nothing of `GrenadeConfig`: the stun's numbers are `CharacterStunConfig`'s.
- `weapon.aim_target()` is the aim point swayed by `weapon.aim_sway()` (two out-of-step sines, `stun.wander`); a shot turns by `aim_sway()` (0 unless stunned).
- `blast_push(from, impulse)` is an explosion's hook: a living body is knocked back (`apply_impulse`), a dead one's ragdoll is woken and thrown (`CharacterRagdoll.blast`).

## The eyes and one-handed fire (G13)

`weapon.stances()` puts the free hand (`1 - weapon_hand()`, hand 1 with nothing held) in the `eyes` stance and a held gun's weapon hand in `one_hand` (its raised grip while `_blocked`) while `_covers_eyes(item)`: blind, not riding, not running, not dead, not reloading, no punch swing, and the weapon hand not in a throw's wind-up. `weapon.one_handed()` is that for a held gun (`gun_id() != &""`); the gun reads it for `one_hand_spread_deg`, and `weapon.kick` multiplies a long gun's recoil by `CharacterStanceConfig.one_hand_recoil`. The pose carries the stun level for the hunch and stagger (`body.md`); in a ride's frame it is 0, so the ride's pose wins and the look eases back in once out. Tests: `stunned_hand_over_eyes_test.gd`, `tests/items/one_handed_fire_test.gd`.
