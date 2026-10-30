## Outfit tests (tag `outfit`)

The rules are `docs/outfits.md` (O1 to O15, each with its tests named under it); `tools/run_tests.sh outfit` runs them. They are spread by domain
(`tests/character/hit_zone_by_bullet_height`, `outfit_weight_slows`, `outfit_art`, and the styles' `style_look` (tag `style`, with
`tests/general/match_styles`); `tests/projectile/helmet_*`, `soft_vest_*`, `plate_*`, `armour_stop_feedback`,
`frag_blast_cut_by_vest`; `tests/items/loadout_outfit`; `tests/ui/setup_menu_config`, `debug_panel_outfit`, `inspector_outfit`), all through
`tests/_outfit/outfit_probe.gd` (`const OutfitProbe := preload(...)`, not `Outfit`: that is the Items class): `wear` / `view` / `condition` (each false / `{}` / -1 without the outfit API; `require_api` is the named check),
`pin_height` (pins `BallisticsFlightConfig.bullet_height`; `STAND` / `CROUCH` are a height in each zone), the spec's numbers (`ZONE_DAMAGE`, `PLATED_KIT`, `PLAIN_CLOTHES`)
so a test checks the doc and not the code, and shooting lanes (`lay_lanes`, `dress`, `volley`: real rounds with a gun's `GunConfig` numbers, or a frag's fragment, fired
square on at a target with a witness standing behind it to show whether a round came out), plus `art(c)` (the body's `drawn_art()`). `--changed` maps
`tests/_outfit` (an unknown helper folder) to the whole suite. **A test that counts gun damage pins the bullet height** (a random height picks a zone, and a head
shot deals twice a torso's). A test reading a dead body's drawing keeps it near the living actors (the camera drops the dead from its framing, and headless it
sees only about 160 px plus the 120 px cull margin) or follows it alone with `camera_follow`.
