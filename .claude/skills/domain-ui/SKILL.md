---
name: domain-ui
description: Use when editing scenes/ui/ or working on a HUD, menu, the command menu, a debug overlay or the test browser UI. Maps each folder to its side file.
---

# UI domain (`scenes/ui/`)

Every HUD and menu: `CanvasLayer` / `Node` widgets built entirely in code (no scene-side layout), decoupled observers that take plain
data or read published contracts and know nothing else of the domains.

## Folders and side files

Read the side file before editing its folder.

| Folder | Side file | Read for |
|---|---|---|
| `menus/` | `menus.md` | the setup window (`setup_menu.gd`) and the settings page / key rebinding (`settings_menu.gd`) |
| `hud/` | `hud.md` | debug panel, match HUD, spectator inspector and contact markers, stack markers, stun screen, outfit lines |
| `command/` | `command.md` | the human leader's command menu, its panel and the order markers |
| `overlays/` | `overlays.md` | the debug-overlay registry, toggle bar, performance overlay, squad-leaders overlay, `DragHandle` |
| `testing/` | `testing.md` | the test browser window and the test result banner |

## What every widget shares

- The composition root (`main.gd`, its `_overlays` part `main_overlays.gd`, `match_builder.gd`) and the Testing domain (runner, world,
  browser) are the only callers. Main finds `MatchHUD` and `DebugUI` by node name (`get_node_or_null`) and calls them duck-typed.
- A widget that must work while the match is paused runs `PROCESS_MODE_ALWAYS`.
- No widget has a `class_name` (callers `preload` the script by path); the one exception is `TestBrowserState`, the browser's plain value object.
- Widgets read only: the Character public API and signals (`hit_landed`), the AI controller's `debug_zones()`,
  `known_contacts_for_display()` and `debug_focus`, `PlayerStack.view()`, a squad's `view()` and `resolve()` callables, the EventBus
  `&"stun"` topic, `ItemRegistry.STUN_SLOT` / `FRAG_SLOT`, `LoadoutConfig.grenade_options()`, `MatchVerdict.decide`, `DrawLayers.ABOVE`
  and `Keybinds` actions. A new read of anything else crosses a domain boundary: add it to `architecture` first.
- Tests: `tests/ui/` (wrapper `ui_suite.gd`). Widgets expose `drawn()` / `items()` read-outs for them.

**Interfaces** (API in `architecture`): 6 (slot ids, `grenade_options`), 7 (Character API, AI controller), 10 (EventBus), 11 (`DrawLayers`,
`MatchVerdict`), 13 (Testing), 14 (settings page), 17 (stack markers), 18 (stun screen), 21 (command menu, order markers, `watch_squad`,
squad-leaders overlay), 22 (what Main wires), 23 (`build_leader_overlay`, `set_overlay`).
