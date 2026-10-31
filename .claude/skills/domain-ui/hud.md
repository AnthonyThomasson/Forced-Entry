# UI hud (`scenes/ui/hud/`)

The in-game observers. Each reads only published contracts (list in `SKILL.md`); none writes to a domain except the inspector's overlay
flags, which go through `OverlayRegistry.apply` (`overlays.md`). The command menu and order markers are `command.md`.

| File | Class / node | Built by |
|---|---|---|
| `debug_ui.gd` | `DebugUI`: stats block, last-hit banner, `=== OUTFIT ===` block | the scene; attaches to `character_path`, listens to `hit_landed`, freed in spectator mode |
| `match_hud.gd` | `MatchHUD`: timer, winner banner, `match_ended(verdict)` | the scene; Main calls `begin` / `set_countdown` |
| `spectator_inspector.gd` | `SpectatorInspector`: click-to-select NPC, pause, tactical-point details, outfit panel | Main, spectator mode only: `setup(combatants, flags, right_clear)` |
| `contact_markers.gd` | `ContactMarkers`: world-space rings of what the selected NPC remembers | the inspector |
| `stack_markers.gd` | `StackMarkers`: doorway-stack slot rings | Main under `World`, human match |
| `stun_screen.gd` | `StunScreen` (CanvasLayer 90): white-out over an afterimage | Main under `World`, human match |
| `outfit_lines.gd` | `OutfitLines.of(view)`: one line per outfit slot | preloaded by the debug panel and the inspector |
| `hud_probe.gd` | `controller_of(character)`: the character's child in group `npc_controllers`, or null | preloaded by the inspector |

Tests: `tests/ui/` — `debug_panel_outfit_test.gd`, `match_hud_verdict_test.gd`, `inspector_outfit_test.gd`, `stack_markers_draw_test.gd`,
`stun_screen_whiteout_test.gd`.

## Gotchas

- **Debug panel.** Reads ammo through `ammo.rounds()` / `capacity()` / `spare_magazines()` / `is_reloading()`, grenade counts through `inventory.item_count(slot)`
  for the slots of `LoadoutConfig.grenade_options()`, and the outfit block from `OutfitLines.of(wardrobe.outfit.view())` every frame
  (`docs/outfits.md` O13).
- **Match HUD.** Re-entrant: an endless run calls `begin` for every match. `match_ended` fires once, when a faction is eliminated
  (decided by `MatchVerdict.decide`, the rule the dev command server's `match` verb uses too) or `time_limit` passes ("TIME UP - DRAW").
  Nothing else shows but the timer and the banner.
- **Spectator inspector.**
  - The click's world point comes from the event's own position through the canvas transform, never the viewport mouse position (in a window that is the system cursor).
  - No NPC shows an overlay until clicked. Selecting applies the `flags` (the overlay toggles) to the selected NPC and all-off to every other;
    `set_flag` re-applies to the selected one. Clicking it again or empty ground clears.
  - With an NPC selected, a click near one of its tactical points (`ZONE_PICK_RADIUS`, from `debug_zones()`) sets the controller's `debug_focus`
    (`Vector2.INF` clears) and fills the detail panel with the zone's kind, label and Von's reasoning.
  - `PROCESS_MODE_ALWAYS`: Space (`Keybinds.PAUSE`, shared with `INTERACT`, unused in the player-less match) pauses the tree, and clicks still work paused.
  - The outfit panel sits `right_clear + OUTFIT_GAP` from the right edge (Main passes the overlay bar's `RESERVED_WIDTH`) and refreshes every frame, so plate wear shows live.
  - The contact markers show the NPC's own knowledge (`known_contacts_for_display()`, pushed each frame via `set_contacts`), not the contacts' true state, and hold steady while paused.
- **Stack markers** (`docs/tactical-entry.md` E16, E19; `docs/leadership.md` LD18; interfaces 17, 21). Two sources: `watch(stack)` (the human's
  `PlayerStack`) and `watch_squad(view)` (Main hands it `squad.view`). The squad's stacks draw ring by ring: dim while the holder is on its way
  (`held`, not `there`), filled once there, the human's own bright, a free slot faint. A slot both views give is drawn once (`_rings`, flagged
  `mine`); the `PlayerStack`'s own slots draw only where the squad's view has no stack. Drawn at `DrawLayers.ABOVE`, so a character on a slot never hides
  its ring. `drawn()` is what the test reads.
- **Stun screen** (`docs/grenades.md` G14; interface 18). `watch(character)`, then reads `stun.view()` each frame: white by `blind / blind_total`
  over a frozen afterimage of the frame on screen when the flash landed (taken on the character's `&"stun"` event with `blind` > 0; none on a
  headless display, where `afterimage` still reports true). A new flash keeps the old frame while the white is above `RETAKE_BELOW`. A deaf-only stun,
  another character's flash and a dead or freed character draw nothing. The white is drawn on an inner mouse-ignoring `Control`.
