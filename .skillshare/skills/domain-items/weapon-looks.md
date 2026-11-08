# Weapon looks and item art

An item is drawn by its `art` part (`ItemArt`, `item_art.gd`; built once with the item, holding the gun or grenade id it draws and what else it needs, never the item). The base draws nothing (fists, unarmed, key, magazine); `GunArt`, `GrenadeArt` and `SpoonArt` draw the rest. Painters live in `scenes/items/art/`, Items-private; the Art domain's engine is `domain-art`.

## Weapon style

- `ItemArt.style` is the **weapon style** the item is drawn in, its wielder's: `police` (both police units, the default), or `scrap` / `pipe` per defender (`CharacterStyleConfig.styles`' `weapons`). `ItemRegistry.inventory_for(..., style := &"police")` stamps it on every item it makes; `LoadoutConfig.apply` passes `style.weapon` through `Character.inventory.set_loadout`.
- **A style never changes what an item does.** `GunConfig`, `GrenadeConfig`, holds, muzzle points, raised-barrel lengths and sounds are the kind's, so every style sits where every other does. Tests: `tests/items/weapon_style_function_test.gd` (the guard), `weapon_style_look_test.gd`, `weapon_style_kept_test.gd`, `tests/general/match_styles_test.gd`.
- A gun or grenade draws its config row's `looks` row for the style: `GunConfig.look(gun, style)` / `GrenadeConfig.look(kind, style)` (`default_style` `police` for a style the row has none for). A look row is the `painter`, its colours, per-style marks and the `finish`. Every gun shares the three gun looks (`GunConfig._looks()`); each grenade kind has its own.
- One painter per style and kind: `police_*`, `scrap_*`, `pipe_*` as `*_gun_painter.gd` and `*_grenade_painter.gd`, sharing `weapon_art.gd` (`paint_gun`, `paint_grenade`, the two gun silhouettes, the marks' helpers), so a style painter keeps only its flags (`crude`, `wood_stock`, `wood_grip`) and marks. The popped spoon is the same in every style (`spoon_painter.gd`).

## Look handle

A painter's options carry the look as an int (`opts.look`, `PixelArt.handle`, read back with `PixelArt.look_of`), never the row, because `PixelArt` hashes the options on every call. An item registers its row once (`ItemArt._look_handle`, again only when the row drawn changes). Every draw records its texture (`ItemArt._note_drawn`) for `art.drawn_art()`, which the weapon-style tests compare.

## Gun art

`GunArt.draw_weapon` renders the painter through `PixelArt.render_turned`, rotated to the exact angle of `weapon.facing()` (which trails the aim as it turns), the butt `grip_back` px behind the weapon hand. Painters draw in the canonical frame (muzzle toward +y, butt at y = 0) and scale from `c.w` / `c.h`, so the same painter renders the shortened raised barrel. The character visuals draw the weapon under the torso and before the fists, so the butt tucks behind the shoulder and the fists grip it. Hand 0 is the weapon hand. Firing calls `user.weapon.kick(weapon_hand(), recoil)`; the supporting hand follows by its stance's `recoil_share`.

## Prepainting

`ItemRegistry.inventory_for` asks each item it makes for `art.prepaint()` (a no-op on the base): a gun paints held at every raise step and lying either side up, a grenade with its lever held and gone, each at every lighting step, once per gun or kind and style (`_prepainted`), with the very calls its draws make. It only fills `PixelArt`'s cache, so a first paint (0.3 to 0.5 ms) lands before a fight, not in its busiest frames. It costs about 230 ms per weapon style, once per process. Test: `tests/items/prepaint_covers_the_draws_test.gd` (no draw of any style paints a new texture).
