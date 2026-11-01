# UI hud (`scenes/ui/hud/`)

The in-game observers. Each reads only published contracts (list in `SKILL.md`); none writes to a domain except the inspector's overlay
flags, which go through `OverlayRegistry.apply` (`overlays.md`). The command menu and order markers are `command.md`. A played match
shows no per-character readout (no ammo, grenade or outfit readout): the detail card is the only one, in a spectator match.

| File | Class / node | Built by |
|---|---|---|
| `match_hud.gd` | `MatchHUD`: timer, winner banner, `match_ended(verdict)`; `TIMER_TOP`, `TIMER_HEIGHT`, `PANEL_TOP` (the top edge the panels under the timer share) | the scene; Main calls `begin` / `set_countdown` |
| `spectator_inspector.gd` | `SpectatorInspector`: right-click select, pause, overlay scope, left-click tactical points | Main, spectator mode only: `setup(combatants, flags, right_clear)`, then `set_scope` |
| `detail_card.gd` | `DetailCard` (`PanelContainer`): the selected NPC's sections | the inspector: `setup(right_clear)`, `show_for(npc)`, `close()`, `set_point(zone)`, `refresh()` |
| `contact_markers.gd` | `ContactMarkers`: world-space rings of what the selected NPC remembers | the inspector |
| `stack_markers.gd` | `StackMarkers`: doorway-stack slot rings | Main under `World`, human match |
| `stun_screen.gd` | `StunScreen` (CanvasLayer 90): white-out over an afterimage | Main under `World`, human match |
| `outfit_lines.gd` | `OutfitLines.of(view)`: one line per outfit slot | preloaded by the detail card and the gun range sandbox |
| `hud_probe.gd` | `controller_of(character)`: the character's child in group `npc_controllers`, or null | preloaded by the inspector |

Tests: `tests/ui/` — `match_hud_verdict_test.gd`, `inspector_right_click_card_test.gd`, `inspector_point_in_card_test.gd`, `inspector_scope_test.gd`,
`detail_card_fits_window_test.gd`, `detail_card_width_and_dead_test.gd`, `detail_card_empty_hand_test.gd`, `stack_markers_draw_test.gd`,
`stun_screen_whiteout_test.gd`; the inspector and card tests share `tests/_ui/inspector_probe.gd` (`domain-testing`).

## Gotchas

- **Match HUD.** Re-entrant: an endless run calls `begin` for every match. `match_ended` fires once, when a faction is eliminated
  (decided by `MatchVerdict.decide`, the rule the dev command server's `match` verb uses too) or `time_limit` passes ("TIME UP - DRAW").
  Nothing else shows but the timer and the banner.
- **Spectator inspector.**
  - Clicks are placed by the event's own position through the canvas transform, never the viewport mouse position (in a window that is the system cursor).
  - A right-click on an NPC (nearest within `PICK_RADIUS`) selects it and opens its card; right-clicking it again or empty ground clears the selection and closes the card. A left-click never selects.
  - With an NPC selected, a left-click near one of its tactical points (`ZONE_PICK_RADIUS`, from `debug_zones()`) sets the controller's `debug_focus` (`Vector2.INF` clears) and
    fills the card's Point section with the zone's kind, label and Von's reasoning; a left-click elsewhere does nothing. A new selection clears the previous NPC's highlight.
  - **Scope rule:** an NPC shows the on-toggles' overlays iff it is in scope (`OverlayRegistry.in_scope(npc, scope)`) or selected; every other NPC gets all-off, both through
    `OverlayRegistry.apply`. The scope starts `selected` until Main hands it the bar's with `set_scope` (right after `setup`), which re-applies at once, also paused. `set_flag` applies one toggle to the NPCs that show.
  - **Words leave the world:** `setup` sets `text_in_world` false on every combatant, so the agent, brain, search and entry overlays draw geometry only and their words are on the card (`domain-ai` (`debug.md`)).
    The inspector sets `brain_labels` on the selected NPC alone, whatever the scope, so under a side scope only the right-clicked NPC draws its brain.
  - `PROCESS_MODE_ALWAYS`: Space (`Keybinds.PAUSE`, shared with `INTERACT`, unused in the player-less match) pauses the tree, and clicks still work paused.
  - The contact markers show the NPC's own knowledge (`known_contacts_for_display()`, pushed each frame via `set_contacts`), not the contacts' true state, and hold steady while paused.
- **Detail card.**
  - Docked left at `LEFT` 24, `TOP` = `MatchHud.PANEL_TOP` (the performance overlay docks under the same line), `WIDTH` 560 shortened to clear `right_clear`. Refreshes every `REFRESH` (0.1 s), also paused.
    A dead NPC's card stays, its title ending `DEAD`, until `close()`; a freed NPC closes it.
  - **Bounded to the window:** the sections sit in a `ScrollContainer`; the card is as tall as its text up to the window's bottom edge less `BOTTOM` (`_fit`, on each refresh and viewport resize).
    The panel is `MOUSE_FILTER_PASS`: `_gui_input` scrolls `WHEEL_STEP` per wheel notch and accepts the wheel (the camera zooms by the wheel in `_unhandled_input`, so it never sees it); every other click passes through to the inspector.
  - Fixed sections, always shown, an empty one saying "—": the title `name · side · rank` (side from `OverlayRegistry.side_of`; rank `trooper` / `sergeant` / `lead` from `wardrobe.rank`, invaders only);
    **Health**; **Item** (the held item and its ammo through `ammo.rounds()` / `capacity()` / `spare_magazines()` / `is_reloading()`, "—" for an item without ammo, "—" alone for an empty hand; a grenades line through
    `inventory.item_count(slot)` for the slots of `LoadoutConfig.grenade_options()`); **Outfit** (`OutfitLines.of(wardrobe.outfit.view())`, `docs/outfits.md` O13); **Decision**, **Von brain**, **Search**, **Entry**
    (the `card_lines()` of the NPC's `AgentDebug`, `BrainDebug`, `SearchDebug`, `EntryDebug` children, duck-typed through `OVERLAY_SECTIONS`: the card never formats a controller getter, so card and world say one thing); **Point**.
- **Stack markers** (`docs/tactical-entry.md` E16, E19; `docs/leadership.md` LD18; interfaces 17, 21). Two sources: `watch(stack)` (the human's
  `PlayerStack`) and `watch_squad(view)` (Main hands it `squad.view`). The squad's stacks draw ring by ring: dim while the holder is on its way
  (`held`, not `there`), filled once there, the human's own bright, a free slot faint. A slot both views give is drawn once (`_rings`, flagged
  `mine`); the `PlayerStack`'s own slots draw only where the squad's view has no stack. Drawn at `DrawLayers.ABOVE`, so a character on a slot never hides
  its ring. `drawn()` is what the test reads.
- **Stun screen** (`docs/grenades.md` G14; interface 18). `watch(character)`, then reads `stun.view()` each frame: white by `blind / blind_total`
  over a frozen afterimage of the frame on screen when the flash landed (taken on the character's `&"stun"` event with `blind` > 0; none on a
  headless display, where `afterimage` still reports true). A new flash keeps the old frame while the white is above `RETAKE_BELOW`. A deaf-only stun,
  another character's flash and a dead or freed character draw nothing. The white is drawn on an inner mouse-ignoring `Control`.
