6. **Items ↔ Character**
   `Item` (`items/item.gd`): `display_name`, `reach`, `hand_stance(hand) -> StringName` (how that
   hand is held — the name of a `CharacterStanceConfig.stances` entry: `relaxed`, `guard`, `aim`, `support`;
   the character's pose eases each hand to it and the rig bends the arm to reach it; the character itself overrides it with `run` while running
   and, while blind, puts the free hand in `eyes` and a gun's weapon hand in `one_hand`, `docs/grenades.md` G13), `primary(user)` (F),
   `secondary(user) -> bool` (LMB; true = a round left the barrel), `tick(delta)` (the item's own clocks; the character ticks
   every item it carries each physics frame), `is_automatic()` (holding the trigger keeps firing), `weapon_hand()`,
   `muzzle_ahead()` (px past the weapon hand where bullets leave; negative = the character's `CharacterStanceConfig.muzzle_ahead`),
   `raises_at_contact()` / `raised_stance(hand)` (a long gun's barrel against a wall or object: held pointing up, cannot fire),
   `drop(user, velocity) -> Node2D` (let go
   as its user dies: a gun leaves a skidding `DroppedItem` in the world, the default leaves
   nothing; the dropped node's `DroppedItem.item` is that very item). It holds typed parts, each built once with it, a base the kind may subclass and hands up
   through `super(...)` (`docs/adr/0005-items-and-vehicle-split-into-typed-parts.md`):
   - **`strike`** (`ItemStrike`, `items/item_strike.gd`): the melee geometry the character's hands read. Its numbers are `ahead`, `turn`,
     `short`, `support_gap`, `tempo` and `hand`; `swing(amount)` / `direction(aim, amount)` / `end(aim, amount)` / `forward()` follow
     from them. A fist's are the defaults. A long gun's (a `GunConfig` row with `raises_at_contact`) make its punch swing it nearly across
     the body, butt leading.
   - **`art`** (`ItemArt`, `items/item_art.gd`; `GunArt`, `GrenadeArt`, `SpoonArt`): how it is drawn: `style` (the weapon style, below),
     `draw_weapon(canvas, user)`, `draw_dropped(canvas, at, angle, modulate, opts)` (how it looks lying loose; `opts.flip` is which side
     landed up), `drawn_art() -> Array` (test read: the textures its last draw, `draw_weapon` or `draw_dropped`, painted: every call in the frame it
     was last drawn, e.g. a lying item's shadow and art; pixel art is cached by what it depicts, so a test compares drawings by them, like
     `CharacterVisuals.drawn_art()`, also a test read) and `prepaint()`.
   - **`ammo`** (`ItemAmmo`, `items/item_ammo.gd`; `GunAmmo`, `items/gun_ammo.gd`): inert hooks the gun's overrides fill:
     `rounds_loaded()` / `capacity()` (-1 = no ammo), `reload_time()`, `can_reload(user)`, `finish_reload(user)`; the `reloading` flag
     the character sets; a gun's loaded `magazine`.

   The character
   calls `drop` on death and removes the item from its inventory if a node came back. `ItemRegistry.create(id, rounds, magazine)` / the slot ids `UNARMED_SLOT`, `FISTS_SLOT` and `KEY_SLOT` (the AI selects its fists with `ItemRegistry.FISTS_SLOT`, and names its grenades by `STUN_SLOT` / `FRAG_SLOT` (`AgentThrow.SLOTS`, the bang entry's stun, or the frag of an entry its leader ordered in with one); the debug panel lists the grenade rows through `LoadoutConfig.grenade_options()`; the UI's command menu reads a teammate's stuns and frags as `inventory.item_count(ItemRegistry.STUN_SLOT)` / `inventory.item_count(ItemRegistry.FRAG_SLOT)`; an interaction's `requires_item` is a slot id, the key's) /
   `default_inventory()` / `inventory_for(slots, rounds, magazine, grenades, style := &"police")` (an optional `magazine` type the gun starts loaded with; `grenades` = slot -> count; `style` the weapon style stamped on every item made) /
   `create_magazines(type_ids)` (full `Magazine`s for those `MagazineConfig` types: the character's spare-magazine store) /
   `random_gun_slot(rng)` / `loadout_for(gun_slot, stuns, frags)` / `spares_for(gun_slot)`. The grenades (`docs/grenades.md`) are `Item`s too: slots `ItemRegistry.STUN_SLOT` 7 / `FRAG_SLOT` 8, a *count*
   carried (`Item.uses_left()`, -1 = unlimited for every other item; `Item.is_throwable()`; `Item.throw_stats() -> Dictionary` (`{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }` for a grenade, from its `GrenadeConfig` row via `GrenadeConfig.stats_of`; `{}` default; `ThrownGrenade.throw_stats()` answers the same for a live one); `ItemRegistry.create(slot, count)`), thrown by `secondary` after a `windup` in the `throw` stance (the `GrenadeItem` posts `&"throw"` as it leaves the hand) as a `ThrownGrenade`
   (a world node in the group `live_grenades`: `kind`, `fuse_left()`, `throw_stats()`, `thrower`, and `item`, the grenade item that draws it, in
   the thrown item's weapon style) that posts `&"grenade"` events and, when its fuse ends, calls the Projectile System's `Explosion.frag` / `Explosion.stun` (`(at, world, source, row)`, `row` = its `GrenadeConfig` row). `LoadoutConfig` (static holder) is what the match
   builder (`MatchBuilder.arm`, interface 23) hands a character: `options()` (plain dicts for the setup window: `RANDOM`, then every `GunConfig` gun with its magazines),
   `grenade_options()` (the Stun and Frag rows: `{ id, label, slot, max }`; a loadout names their counts `stuns` / `frags`, 0..3), `grenade_counts(loadout)`,
   `outfit_options()` (the outfit rows: `[{ slot, label, choices: [{ id, label }] }]`, one per slot, a "None" choice `id` `&""` first where the slot may be empty; the
   vest choice that holds plates marked `plates: true`, each plate row `plate: true`),
   `normalize(loadout)` (a `{ weapon, magazine, spares, stuns, frags, outfit }` dict made valid; `outfit_of(loadout)` fills every outfit slot, a missing or unfitting
   id taking `default_outfit`'s: plain clothes, and clears both plates unless the vest holds plates), `apply(character, loadout, rng, style := {}) -> gun id` (arms it through `Character.inventory.set_loadout` and dresses it in the whole
   outfit through `Character.wardrobe.outfit.set_ids`; `style` = how it is all drawn, looks only: `look` / `seed` /
   `rank` passed to `Character.wardrobe.set_style`, absent = the character's style left as it is, and `weapon`, the weapon style passed to
   `Character.inventory.set_loadout`, absent = `police`) and `random(rng)` (with `random_outfit(rng)`, drawn after the gun). **Weapon style:** every `Item`'s `art.style`
   (`&"police"` for the invaders, `&"scrap"` / `&"pipe"` for a defender; default `police`), the look it is drawn in, never what it does: a gun
   or grenade draws its `GunConfig` / `GrenadeConfig` row's `looks` row for it (the painter and its colours; `GunConfig.look(gun, style)` /
   `GrenadeConfig.look(kind, style)`, `default_style` `police` for a style it has no row for), held, dropped (either side up) and, for a
   grenade, in flight and at rest; a dropped gun is the item it was, and a thrown grenade's `item` takes its thrower's item's `art.style`. **Outfits** (`docs/outfits.md`): `OutfitConfig`
   (static holder: the garment and plate rows, a garment's `looks` per character style (`zenitex`, `trauma`, `merc`, `borg`: its `kind` and a `color`
   or a `palette` name, `default_style` for a style it has no row for), `GARMENT_SLOTS` / `PLATE_SLOTS` (String keys `head body vest pants feet
   front_plate back_plate`), `choices(slot)`, `fits(slot, id)`, `name_of(slot, id)`) and `Outfit` (`RefCounted`, one character's worn set: `set_ids(ids)`, `ids()` (test read), `worn(slot)`, `condition(slot)`,
   `layer(zone, side)` (the armour a round meets there: `{}` or `{ stop_power, penetration, material, color, blunt, reduction, blast, plate }`), `wear(zone, side, damage)`,
   `weight()`, `look(style)` (what the art draws, in that character style), `view()` (what the UI shows) and `revision` (bumped by every change, which the art watches)). The
   character API an item may call: `facing`, `is_dead` and `inventory.current_item()` (a grenade gives up its windup when its user dies or switches away), the hands of its `anatomy` (`body/character_anatomy.gd`, `CharacterAnatomy`; the `Hands` child, `character_hands.gd`)
   `anatomy.hands.punch(hand)`, `anatomy.hands.punch_amount(hand)` (0..1, how far that hand is thrown: a long gun swings round by it),
   `anatomy.hands.hand_position(hand)` (local) and `anatomy.hands.world(hand)` (world), `weapon.muzzle_origin(hand)` (the held item's `muzzle_ahead()` past the hand),
   `world_root()` (also read by the AI: the characters it perceives are the group `characters` under it), `report_shot(body, dmg)`, `weapon.kick(hand, strength := 1.0)` (recoil: throws that hand back; `strength` scales it),
   `weapon.facing()` (the drawn weapon direction, trailing the aim; shots still use `facing`), `weapon.aim_target()` (the aim point a grenade is thrown to) / `weapon.aim_sway()` (rad, the stun's wandering turn of every shot and throw; 0 unstunned), `weapon.one_handed()`
   (a held gun is in the weapon hand alone, the free hand over the eyes while blind: a gun's round then adds its row's `one_hand_spread_deg`) and `weapon.raise()` (0..1, how far
   a long gun is raised off a wall, for its art). **Guns:** every firearm is a `GunItem` (`items/gun.gd`), built by its gun id and tuned by its row in
   `GunConfig` (damage, `fire_interval`, `automatic`, `penetration`, `muzzle_speed`, `spread_deg`, `one_hand_spread_deg`, `recoil`, its default magazine,
   `raises_at_contact`; its sizes, `art_size`, `flat_size`, `grip_back`, and its hold, `grip_stance`, `fore_stance`, `raised_grip_stance`,
   `raised_fore_stance`); `PistolItem` / `SmgItem` / `RifleItem` only name their row (`super(GUN)`; the look is the row's `looks`, above). **Ammo:** the `ammo` part (above). **Gun identity:** `gun_id()` (the `GunConfig` id, `&""` for a non-gun) and `round_power()`
   (the penetration power of its rounds, 1 for a non-gun), which the character reads for its `reload` event. A `Magazine` (an `Item` subclass, types in `MagazineConfig`, each tied to one `gun` id,
   with its own capacity and optional `reload_time`) is carried
   by the character, never held or selectable; a gun loads one and each shot spends a round. For a reload
   its `ammo` part calls the character's `ammo.best_magazine(gun)` / `ammo.take_magazine(gun)` / `ammo.stow_magazine(m)`. Items reach into the
   Projectile System in two places. A gun fires through `ProjectileSpawner.spawn(position, direction, parent, shot: Shot = null) -> Node` (`Shot`,
   `projectile/shot.gd`: `shooter` (the body the round ignores), `item_damage` = 0.0, `damage` = -1.0 (the round's damage outright; negative = base + `item_damage`), `muzzle_speed` = -1.0, `penetration` = 1.0,
   `max_range` = -1.0, `strikes_shooter` = false; null, all defaults) (the round; the gun connects its
   `hit(body, damage)` signal to its user's `report_shot`) and ejects a case through `CasingSpawner.spawn(position, direction, parent) -> Node`;
   a `ThrownGrenade` calls `Explosion.frag` / `Explosion.stun` (above).
