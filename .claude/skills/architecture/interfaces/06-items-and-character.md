6. **Items ↔ Character**
   `Item` (`items/item.gd`): `display_name`, `reach`, `hand_stance(hand) -> StringName` (a `CharacterStanceConfig.stances` entry name; the
   character overrides it with `run` while running, and blind puts the free hand in `eyes` and a gun's weapon hand in `one_hand`,
   `docs/grenades.md` G13), `primary(user)` (F), `secondary(user) -> bool` (LMB; true = a round left the barrel), `tick(delta)` (the
   character ticks every carried item each physics frame), `is_automatic()`, `weapon_hand()`, `muzzle_ahead()` (negative = the
   character's `CharacterStanceConfig.muzzle_ahead`), `raises_at_contact()` / `raised_stance(hand)` (a long gun's barrel against a wall:
   held up, cannot fire), `gun_id()` (`GunConfig` id, `&""` for a non-gun), `round_power()` (1 for a non-gun; the character reads both for
   its `reload` event), `drop(user, velocity) -> Node2D` (called on the user's death: a gun leaves a skidding `DroppedItem` whose
   `DroppedItem.item` is that very item, the default leaves nothing).

   Typed parts, each built once with the item, a base the kind subclasses and hands up through `super(...)`
   (`docs/adr/0005-items-and-vehicle-split-into-typed-parts.md`):
   - **`strike`** (`ItemStrike`): the melee geometry the hands read (`ahead`, `turn`, `short`, `support_gap`, `tempo`, `hand`). A fist's are
     the defaults; a long gun's swing it across the body, butt first.
   - **`art`** (`ItemArt`; `GunArt`, `GrenadeArt`, `SpoonArt`): `style` (the weapon style, below), `draw_weapon(canvas, user)`,
     `draw_dropped(canvas, at, angle, modulate, opts)` (`opts.flip`: which side landed up), `prepaint()`, and the test read
     `drawn_art() -> Array` (the textures of its last draw; pixel art is cached by what it depicts, so tests compare by these, like
     `CharacterVisuals.drawn_art()`).
   - **`ammo`** (`ItemAmmo`; `GunAmmo`): `rounds_loaded()` / `capacity()` (-1 = no ammo), `reload_time()`, `can_reload(user)`,
     `finish_reload(user)`; the `reloading` flag the character sets; a gun's loaded `magazine`.

   **Registry.** `ItemRegistry.create(id, rounds, magazine)` makes the item of a slot id (a grenade: `rounds` of them). Slot ids `UNARMED_SLOT`, `FISTS_SLOT`, `KEY_SLOT`, `STUN_SLOT` 7, `FRAG_SLOT` 8 (plus the gun slots). Readers: the AI selects
   `FISTS_SLOT` and names grenades by `STUN_SLOT` / `FRAG_SLOT`; the command menu reads a teammate's grenades as
   `inventory.item_count(...)`; an interaction's `requires_item` is a slot id; the debug panel lists grenade rows through
   `LoadoutConfig.grenade_options()`. Also `default_inventory()`, `inventory_for(slots, rounds, magazine, grenades, style := &"police")`
   (`grenades` = slot -> count, `style` stamped on every item made), `create_magazines(type_ids)` (full `Magazine`s: the character's spare
   store), `random_gun_slot(rng)`, `loadout_for(gun_slot, stuns, frags)`, `spares_for(gun_slot)`.

   **Grenades** (`docs/grenades.md`) are `Item`s: a *count* carried (`Item.uses_left()`, -1 = unlimited; `Item.is_throwable()`). `Item.throw_stats() -> Dictionary` is `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }`
   for a grenade (from `GrenadeConfig.stats_of(kind, source := {})`: the kind's own row when no `source` row), `{}` otherwise;
   `ThrownGrenade.throw_stats()` answers the same for a live one, and the AI's perception calls `GrenadeConfig.stats_of` directly for a
   grenade nobody holds (the frag and stun an entry may throw in, an ambush post, `docs/leadership.md` LD15). `secondary` throws after a
   `windup` in the `throw` stance (`GrenadeItem` posts `&"throw"` as it leaves the hand) a `ThrownGrenade` (a node in the group
   `live_grenades`: `kind`, `fuse_left()`, `throw_stats()`, `thrower`, `item` = the grenade item that draws it, in the thrown item's
   weapon style); it posts `&"grenade"` and, when the fuse ends, calls `Explosion.frag` / `Explosion.stun` `(at, world, source, row)`.

   **`LoadoutConfig`** (static) is what `MatchBuilder.arm` (interface 23) hands a character: `options()` (setup-window rows: `RANDOM`, then every gun with its magazines), `grenade_options()` (`{ id, label, slot, max }`; a loadout names counts `stuns` /
   `frags`, 0..3), `grenade_counts(loadout)`, `outfit_options()` (`[{ slot, label, choices: [{ id, label }] }]`; a "None" choice `id` `&""`
   first where a slot may be empty; the vest choice holding plates is marked `plates: true`, each plate row `plate: true`),
   `normalize(loadout)` (a `{ weapon, magazine, spares, stuns, frags, outfit }` dict made valid: a missing or unfitting outfit id takes
   `default_outfit`'s, plates clear unless the vest holds them), `apply(character, loadout, rng, style := {}) -> gun id` (arms through
   `Character.inventory.set_loadout`, dresses through `Character.wardrobe.outfit.set_ids`; `style`, looks only: `look` / `seed` / `rank`
   go to `Character.wardrobe.set_style` (absent = style left as is) and `weapon` to `set_loadout` (absent = `police`)), `random(rng)`, `random_outfit(rng)`.

   **Weapon style.** Every item's `art.style` (`&"police"` invaders, `&"scrap"` / `&"pipe"` defenders; default `police`): how it is drawn,
   never what it does. A gun or grenade draws its row's `looks` entry for the style (`GunConfig.look(gun, style)` /
   `GrenadeConfig.look(kind, style)`; a style with no row draws `default_style`'s), held, dropped, and for a grenade in flight and at
   rest. A dropped gun is the item it was; a thrown grenade's `item` takes its thrower's item's style.

   **Outfits** (`docs/outfits.md`). `OutfitConfig` (static): garment and plate rows, a garment's `looks` per character style
   (`zenitex`, `trauma`, `merc`, `borg`; `default_style` for a style it has no row for), `GARMENT_SLOTS` / `PLATE_SLOTS` (String keys
   `head body vest pants feet front_plate back_plate`), `choices(slot)`, `fits(slot, id)`, `name_of(slot, id)`. `Outfit` (`RefCounted`, one character's worn set): `set_ids(ids)`, `ids()` (test read), `worn(slot)`, `condition(slot)`, `layer(zone, side)` (the armour a round
   meets: `{}` or `{ stop_power, penetration, material, color, blunt, reduction, blast, plate }`), `wear(zone, side, damage)`, `weight()`,
   `look(style)`, `view()` (for the UI) and `revision` (bumped by every change; the art watches it).

   **The character API an item may call:** `facing`, `is_dead`, `inventory.current_item()` (a grenade drops its windup when the user dies
   or switches away), `anatomy.hands.punch(hand)` / `punch_amount(hand)` (0..1; a long gun swings round by it) / `hand_position(hand)`
   (local) / `world(hand)`, `weapon.muzzle_origin(hand)`, `world_root()` (the AI reads it too: characters it perceives are the group
   `characters` under it), `report_shot(body, dmg)`, `weapon.kick(hand, strength := 1.0)` (recoil), `weapon.facing()` (the drawn
   direction, trailing the aim), `weapon.aim_target()` (where a grenade is thrown to), `weapon.aim_sway()`
   (rad, the stun's wander of every shot and throw), `weapon.one_handed()` (blind: a gun's round adds its row's `one_hand_spread_deg`),
   `weapon.raise()` (0..1, a long gun raised off a wall, for its art).

   **Guns.** Every firearm is a `GunItem` (`items/gun.gd`) built by gun id and tuned by its `GunConfig` row; `PistolItem` / `SmgItem` /
   `RifleItem` only name their row (`super(GUN)`). A `Magazine` (an `Item`, types in `MagazineConfig`, each tied to one `gun`) is carried,
   never held or selectable; a gun loads one and each shot spends a round. A reload goes through the character's `ammo.best_magazine(gun)`
   / `take_magazine(gun)` / `stow_magazine(m)`. Items reach the Projectile System in two places: a gun fires
   `ProjectileSpawner.spawn(position, direction, parent, shot: Shot = null) -> Node` (`Shot`, `projectile/shot.gd`: `shooter`,
   `item_damage`, `damage` (-1 = base + `item_damage`), `muzzle_speed`, `penetration`, `max_range`, `strikes_shooter`; null = defaults;
   the round's `hit(body, damage)` goes to its user's `report_shot`) and ejects a case through
   `CasingSpawner.spawn(position, direction, parent) -> Node`; a `ThrownGrenade` calls `Explosion.frag` / `Explosion.stun`.
