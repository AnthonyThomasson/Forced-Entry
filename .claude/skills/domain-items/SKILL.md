---
name: domain-items
description: Use when editing scenes/items/ or working on held items: guns, magazines, loadouts, outfits and armour plates, dropped items, grenades, weapon looks.
---

# Items domain

Owns what a character holds and does with it, and what it wears. Fire-rate and alternation state live in the item; the reload clock and the aim are the character's (`domain-character`). Item API and every cross-domain call: interface 6. Tests: `tests/items/` (probe: `tests/_items/weapon_style_probe.gd`).

**Side files:** grenades (`ThrownGrenade`, throw planning, `GrenadeConfig`) → `grenades.md`. Weapon styles, painters, prepainting, gun art → `weapon-looks.md`.

## Files

- `item.gd` (`Item`): the contract. Typed parts built once with it and handed up through `super(...)`: `strike` (`ItemStrike`), `art` (`ItemArt`, `GunArt`, `GrenadeArt`, `SpoonArt`), `ammo` (`ItemAmmo`, `GunAmmo`). **No part holds its item** (a cycle never frees, so a dropped item would leak): the user is passed on each call. Test: `tests/items/item_parts_free_suite.gd`.
- `item_registry.gd` (`ItemRegistry`): slot ids and item construction. Slots are the number keys: 1 unarmed, 2 fists, 3 pistol, 4 key (inert: it exists so a `requires_item: 4` interaction has something to gate on), 5 SMG, 6 rifle, 7 stun, 8 frag. A gun's slot is its `GunConfig` row's `slot`.
- `gun.gd` (`GunItem`) + `pistol.gd` / `smg.gd` / `rifle.gd` (each only names its row: `const GUN`, `super(GUN)`); `gun_config.gd` (`GunConfig`); `magazine.gd` + `magazine_config.gd`; `gun_ammo.gd`; `item_strike.gd`.
- `fists.gd`, `unarmed.gd`, `key.gd`; `dropped_item.gd` + `dropped_item_config.gd`.
- `outfit.gd` + `outfit_config.gd`; `loadout_config.gd` + `character_kit.gd`.
- Grenades and art: see the side files.

## Guns

Every number a gun has comes live from its `GunConfig.guns` row, a static-var holder tests retune with `set_static`; the row's own comments name each key. Gotchas:

- **Fire rate is a cooldown**, ticked by the character for every item it carries before its controller runs (deterministic, independent of the wall clock). Firing adds `fire_interval` to the cooldown so an overshoot carries (0.07 s is not rounded to 5 frames); idle credit is capped at one frame so a gun never bursts to catch up.
- **Zeroing.** `secondary` aims the round at the point `GunConfig.zero_range` ahead on the aim line, not parallel to `facing`, so a shouldered gun with its muzzle off the line still hits where the character points. The spread is applied around that direction.
- **One-handed** is the character's doing (blind: weapon hand in `one_hand`, free hand over the eyes, `docs/grenades.md` G13). The gun only reads `weapon.one_handed()` to add `one_hand_spread_deg`. Test: `tests/items/one_handed_fire_test.gd`.
- **A long gun's `primary` strikes with its butt** in both hands (`strike`: `STRIKE_TURN`, `SUPPORT_GAP`, `LONG_TEMPO`, `STRIKE_SHORT`); the hands layer shortens the hand's extension by `strike.forward()` so the blow lands about as far out as before. A pistol just jabs. Test: `tests/items/long_gun_butt_strike_test.gd`.
- **Raised against a wall** (`raises_at_contact`, SMG and rifle): the character tests the barrel each frame (`domain-character`). While it touches, `raised_stance(hand)` is held, `weapon.shoot()` does nothing and `GunArt` foreshortens the barrel by rendering the painter at `RAISE_STEPS` lengths down to `RAISED_LENGTH` (crisp and cached, not a stretched texture). The pistol does not raise.
- `muzzle_ahead()` is the row's `art_size.y − grip_back`, so a long gun's muzzle is further out (`Character.weapon.muzzle_origin` uses it).
- A shot posts `&"shot"` on `EventBus` (`attacker` is read only by tests) and the round's `hit` signal goes to `user.report_shot`.

**Adding a gun:** a `GunConfig.guns` row (free `slot`; `looks` from `_looks()` or rows of its own; sizes, `grip_back` and stances, any new stance row in `CharacterStanceConfig.stances`), a `GunItem` subclass naming it, a case in `ItemRegistry._new_gun`, and `MagazineConfig.types` rows for its gun id. **Another item:** an `Item` subclass (plus an `ItemArt` subclass if drawn) and a case in `ItemRegistry.create`. `LoadoutConfig.options()` lists every `GunConfig` gun, so a new gun appears in the setup window by itself.

## Magazines and reloading

`Magazine` (an `Item` subclass; `Magazine.create(type, loaded := -1)`) fits only its own `gun`. Magazines are **carried, never held**: in no slot, nothing can switch to them, several can be carried (`ItemRegistry.create_magazines`). A gun spends one round of `ammo.magazine` per shot (empty or reloading: no casing, no recoil). `ammo.finish_reload(user)` seats the fullest compatible spare (`user.ammo.take_magazine`) and stows the old one with its rounds (`stow_magazine`), dropping it only when empty. The reload timer and R binding are the character's. Tests: `tests/items/reload_swaps_magazine_test.gd`, `gun_magazines_test.gd`.

## Loadouts (`LoadoutConfig`)

What the match builder hands a character (`MatchBuilder.arm`, interface 23). `normalize` makes a `{ weapon, magazine, spares, stuns, frags, outfit }` dict valid; `apply(character, loadout, rng, style := {})` arms through `Character.inventory.set_loadout` with a `CharacterKit` (Items' vocabulary, kept here so the static edge runs only Character → Items), dresses through `Character.wardrobe.outfit.set_ids`, and with `style.look` calls `Character.wardrobe.set_style` (looks only, `docs/outfits.md` O15). `random` draws the outfit after the gun, so a seed's gun does not depend on it.

## Outfits (spec `docs/outfits.md` O1 to O15)

`OutfitConfig` holds the garment and plate rows (slots `GARMENT_SLOTS`, `PLATE_SLOTS`; per-style `looks`); `Outfit` is one character's worn set (`Character.wardrobe.outfit`). The rules (zones, sides, stopped or through, plate wear, weight, choosing) are the spec's. Kept here:

- `layer(zone, side)` is what a round meets; what a layer does to a hit is `Character.take_hit` (`domain-character`), and the stop itself is the projectile's (`domain-projectile`).
- A plate is kept only while the vest `holds_plates()`; a plate left in its slot keeps its condition, a new one starts at 1. `LoadoutConfig.outfit_of(loadout)` makes any outfit valid (a missing or misplaced id takes `LoadoutConfig.default_outfit`'s).
- `revision` is bumped by `set_ids` and by a `wear` that lowered a condition; the art checks it once a frame. `weight()` caches its
  garment/plate total until `set_ids`; plate wear changes condition, not mass (`outfit_weight_follows_loadout_test.gd`).
- `LoadoutConfig.outfit_options()` marks the plate-carrier choice `plates: true` and each plate row `plate: true`, so the setup window offers plates only with a vest that holds them (O11b).

## Dropping on death

The character calls `item.drop(user, velocity)`; the base `Item` leaves nothing, a gun spawns a `DroppedItem` where its art was drawn (pulled back toward the hand, `held_from`, if that spot is inside a wall). It falls on a pseudo-height, bounces, skids and glances off walls and solid furniture, draws through `item.art.draw_dropped` at `DrawLayers.LYING` and stops processing at rest. Visual only: nothing picks it up and the `Despawner` never frees it. A grenade is never dropped. Tuning: `DroppedItemConfig`.

**Interfaces:** 6 (Items ↔ Character, with `Outfit` / `OutfitConfig`), 10 (`&"shot"`, `&"throw"`, `&"grenade"`), 11 (`DrawLayers`), 12 (Art). Into the Projectile System in two places only: a gun's `ProjectileSpawner.spawn` / `CasingSpawner.spawn`, and a `ThrownGrenade`'s `Explosion.frag` / `Explosion.stun` (`domain-projectile`).
