---
name: domain-ui
description: Overview of the UI domain (scenes/ui/) — all HUDs and menus, split into five sub-domains by folder: menus (setup window, settings page), hud (debug panel, match HUD, spectator inspector, stack markers, stun screen), command (the human leader's command menu and order markers), overlays (overlay registry, toggle bar, performance overlay, squad-leaders overlay) and testing (test browser window, result banner). Start here for what they share (decoupled observers of the Character API, the AI controller's debug getters and the EventBus), then load the matching `domain-ui-<name>` skill. Complements the `architecture` skill.
---

# UI domain (`scenes/ui/`) — overview

`CanvasLayer` / `Node` widgets, all built entirely in code (no scene-side layout), all decoupled observers
that read only these contracts — Character public API/signals (the debug panel's hits come from `hit_landed`, interface 7), the AI controller's
`debug_zones()`, `known_contacts_for_display()` and `debug_focus` (a var: the point, `Vector2.INF` for none; the spectator
inspector, which rings the clicked point on the NPC's tactics overlay), `PlayerStack.view()` (the stack markers, interface 17), a squad's `view()` callable (the command menu, the order markers, the stack markers'
`watch_squad` and the squad-leaders overlay) and `resolve()` callable (the command menu, interface 21), and the EventBus `&"stun"` topic (the
stun screen); and these shared reads: Items' `ItemRegistry.STUN_SLOT` / `FRAG_SLOT` (the command menu, through `inventory.item_count`) and
`LoadoutConfig.grenade_options()` (the debug panel), interface 6; General's `MatchVerdict.decide` (the match HUD) and `DrawLayers.ABOVE` (the
stack markers, the order markers and the squad-leaders overlay), interface 11; and `Keybinds` actions (the inspector `PAUSE`, the command
menu `COMMAND` and `MENU`), interface 7. They know nothing else of the domains.

## Sub-domains (one folder, one skill each)

| Folder | Skill | Owns |
|---|---|---|
| `menus/` | `domain-ui-menus` | `setup_menu.gd` (pre-game window), `settings_menu.gd` (Debug + key rebinding) |
| `hud/` | `domain-ui-hud` | `debug_ui.gd`, `match_hud.gd`, `spectator_inspector.gd`, `contact_markers.gd`, `stack_markers.gd`, `stun_screen.gd`, `outfit_lines.gd`, `hud_probe.gd` |
| `command/` | `domain-ui-command` | `command_menu.gd`, `command_panel.gd`, `order_markers.gd` |
| `overlays/` | `domain-ui-overlays` | `overlay_registry.gd`, `overlay_toggles.gd`, `performance_overlay.gd`, `leader_overlay.gd`, `drag_handle.gd` |
| `testing/` | `domain-ui-testing` | `test_browser_window.gd`, `test_browser_list.gd`, `test_browser_state.gd` (`TestBrowserState`), `test_result_hud.gd` |

Load the matching sub-skill before editing a folder. What they share: every widget is built in code (no scene-side layout), takes plain
data or reads published contracts only, never reaches into another domain's internals, and runs `PROCESS_MODE_ALWAYS` when it must keep
working while the match is paused. No widget has a `class_name` (callers `preload` the script by path); the one `class_name` is `TestBrowserState`, the browser window's plain
value object. The composition root (`main.gd`, its `_overlays` part `main_overlays.gd`, `match_builder.gd`) and the Testing domain (runner,
world, browser) are the only outward callers (`MatchHUD.begin`, `SetupMenu.open`,
`OverlayToggles.setup`, …); `main.gd` finds its HUD nodes by name (`get_node_or_null("MatchHUD")`, `"DebugUI"`)
and calls them duck-typed. Each sub-skill lists the calls its folder receives.

**Interfaces:** 6 (the command menu's `ItemRegistry` slot ids, the debug panel's `LoadoutConfig.grenade_options`), 7 (observers of the Character API and the AI controller), 10 (EventBus), 11 (`DrawLayers`, `MatchVerdict`), 13 (Testing), 14 (settings page), 17 (stack markers), 18 (stun screen), 21 (the command menu, the order markers, the stack markers' `watch_squad` and the squad-leaders overlay), 22 (the setup window, match HUD, spectator inspector and overlay bar Main wires), 23 (`MatchBuilder.build_leader_overlay` builds the `LeaderOverlay`; `set_overlay` routes through `OverlayRegistry.apply`) — signatures in `architecture`.
