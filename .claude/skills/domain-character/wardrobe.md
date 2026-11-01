# Character wardrobe: style, outfit, armour in `take_hit`

Spec: `docs/outfits.md` (O1 to O10 hit zones, armour and weight; O12 to O15 art, display, style). The worn set is Items' `Outfit` (`domain-items`); how it is drawn is `body.md`.

## Style (O15)

How the character is drawn, looks only, on `wardrobe` (`CharacterWardrobe`): `style` (a `CharacterStyleConfig.styles` key: `zenitex` / `trauma` the police units, `merc` / `borg` the defenders' crew; default `zenitex`, the defender NPC scene's `Wardrobe` is `merc`), `look_seed` (its own variety within the style) and `rank` (a police unit's: 0 trooper, 1 sergeant, 2 lead). All three are exported, so a scene can author them. `wardrobe.set_style(style, seed, rank := 0)` sets them (a match through `LoadoutConfig.apply`'s `style`; tests through it or `set_props(id, "Wardrobe", { rank = … })`). Each setter bumps `wardrobe.revision`, which the visuals compare once a frame. The style rows and `default_style` are this domain's tuning (`CharacterStyleConfig`). Tests: `tests/character/style_look_test.gd`, `tests/general/match_styles_test.gd`.

## Outfit

`wardrobe.outfit` starts wearing nothing; Main dresses every spawn through `LoadoutConfig.apply` (`wardrobe.outfit.set_ids`). A character never dressed has no armour, no weight and its style's bare clothes. The art reads `Outfit.look(style)` and `revision`, the UI its `view()`.

- **Where a round strikes** (private to the body). `_hit_zone(height)`: the bullet's `HitInfo.height` over `movement.posture_coverage(movement.posture())` against `CharacterHitConfig.zones`; `&""` for a height below 0 (a blast). `_hit_side(direction)`: the angle between `-direction` and `anatomy.pose.torso_angle` (the shoulders), by `side_front_deg` and `side_back_deg`.
- **`get_surface_at(height, direction)`** (interface 3; the projectile asks it first) is `get_surface()` where `Outfit.layer(zone, side)` is empty or the height is below 0; over armour, that surface with the layer's `penetration`, `material`, `color`, `stop_power` and `inner_material` (the body's own material, flesh).
- **`take_hit`.** The shove is always applied. A height below 0 (a frag's blast) is not zoned: its damage less the torso layer's `blast` share wounds (`_wound_by`). Otherwise the damage is scaled by `CharacterHitConfig.zone_damage`. No layer there: it wounds for the zoned damage. Over a layer it first wears the plate (`Outfit.wear(zone, side, hit.damage)`, the **unscaled** damage); then a hit that got through (`hit.penetrated`) wounds for `(1 − reduction)` of the zoned damage, and one that did not (the projectile guarantees a round that beats `stop_power` penetrates) deals only the `blunt` share through `_apply_damage`, with debris of the armour's material and colour and no `Deformable` record (so `damage_taken()` does not rise) and no `BloodWound`. `_wound_by` is the wounding path: the dent, the blood debris, the bleeding, the damage. Melee (`take_damage`) is not zoned and meets no armour.
- **Weight.** `movement._speed_in` multiplies every pace by `_weight_speed()` from the kg worn above `outfit_free_weight` (`outfit_speed_per_kg`, floor `outfit_speed_min`), so `_move_speed()` and `run_speed()` slow with it; `_update_stamina` spends the run's stamina faster by `outfit_stamina_per_kg` (`CharacterPaceConfig`).

Tests: `tests/character/hit_zone_by_bullet_height_test.gd`, `outfit_weight_slows_test.gd`, `outfit_art_test.gd`, and the armour tests in `tests/projectile/`. **A test that counts gun damage pins `BallisticsFlightConfig.bullet_height`** (a random height picks a zone).
