# UI menus (`scenes/ui/menus/`)

Two full-screen, code-built windows that take plain data and emit signals. They know nothing of `Items`, `Keybinds` or `Settings`: Main
(interfaces 14, 22) feeds them dicts and applies what they report. Tests: `tests/ui/setup_menu_config_test.gd`,
`setup_menu_ticket_test.gd`, `settings_menu_test.gd`.

## `setup_menu.gd` — the pre-game setup window (`SetupMenu`)

- `open(defaults)` takes `{ side, seed, lead, defenders, invaders, weapons, grenades, outfits, ticket }`. Main builds the choice rows
  (`weapons` with each weapon's `magazines`, `grenades`, `outfits`) from `LoadoutConfig`; the window never sees `Items`. A weapon with no magazines
  hides the Magazine and Spares rows. Without `grenades` the window falls back to its own Stun / Frag rows capped by `_MAX_COUNT`.
  Without `outfits` there are no outfit rows and no `outfit` key. A non-blank `ticket` shows as a label above the title.
- The three start buttons (**Start** play as the chosen side, **Watch** AIs alone, **Endless** AIs alone and a fresh match after each) emit
  `start_requested({ mode: "play"|"watch"|"endless", side, seed, lead, defenders, invaders })`. **Tests** emits `tests_requested` (Main
  changes scene to the test browser), **Settings** emits `settings_requested` (Main opens the settings page over this window).
- **Lead the team** (`LeadCheck`) applies to Start only: the human leads its side and orders it from the command menu
  (`docs/leadership.md` LD10). Main ignores it for Watch and Endless.
- Pressing a start button disables all three: Main may hold the start while it waits for the Von decision server, and a second press would build
  the world twice. `set_status(text)` writes the line above Start (Main: "Waiting for the decision server…"), so the wait is never silent.
- `current_config()` returns `{ side, seed, lead, defenders, invaders }` as the window stands (empty before `open`). Main saves it with
  `Settings.set_setup` on Start, on Tests and on Escape, and feeds `Settings.setup` back as `open`'s defaults, so the window reopens as left.
- Plates follow the vest (`_refresh_plates`, on open and on every outfit pick): a row marked `plate: true` is disabled and reports `""` unless
  another row's selected choice is marked `plates: true` (`docs/outfits.md` O11b).
- A scripted `restart` sets the Engine meta `skip_setup`, so Main bypasses the window.

## `settings_menu.gd` — the settings page (`SettingsMenu`, CanvasLayer layer 20, over the setup window)

- `open({ debug, rows })` and `set_rows(rows)` take `rows` = `{ action, label, group, text, conflicts, changed }` in display order. Signals:
  `debug_changed(on)`, `rebind_requested(action, event)`, `reset_requested(action)`, `reset_all_requested`, `back_requested`. Main applies each change
  and answers with `set_rows`; a redraw keeps the scroll position. It names no action: the rows come from `Settings.binding_rows()`, so Use
  (`Keybinds.USE`, "Use (door, vehicle)", "Interaction" group, default E) is listed from `Keybinds.LABELS`.
- **Capture:** a key button swaps to "Press a key…"; the next key or mouse-button press goes out as `rebind_requested` (the host may refuse it);
  Esc cancels. Escape and every key during a capture are consumed in `_input`, which runs before Main's `_unhandled_input`: Escape never
  triggers Main's "return to setup", a captured key never reaches the game, and Esc itself cannot be bound.
- Key and Reset buttons take no focus, so Space and Enter do not re-press them.
