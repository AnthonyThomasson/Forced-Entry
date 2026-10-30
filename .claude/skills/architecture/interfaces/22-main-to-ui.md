22. **Main → UI: setup window, match HUD, spectator inspector, overlay bar** (the composition root wires them, in the shape of
    interface 14: plain dicts in, signals out; the flow is `domain-main`'s)
    - `SetupMenu` (`ui/menus/setup_menu.gd`, the `SetupMenu` node of `main.tscn`): `open(defaults)` (Main's `run` with the saved
      `Settings.setup` over it, plus the choice rows as plain data: `weapons` (`LoadoutConfig.options()`), `grenades`
      (`grenade_options()`), `outfits` (`outfit_options()`) and the run's `ticket`), `current_config() -> Dictionary` (`{ side, seed, lead,
      defenders, invaders }` as they stand, {} before `open`: Main saves it with `Settings.set_setup` when the window is left without
      starting) and `set_status(text)` (a status line while Main holds the start; "" hides it); signals `start_requested(config)` (`{ mode`
      (`play` / `watch` / `endless`)`, side, seed, lead, defenders, invaders }`, each side `{ count, weapon, magazine, spares, stuns, frags,
      outfit }`), `tests_requested` (Main changes scene to the test browser, interface 13) and `settings_requested` (Main opens the settings
      page, interface 14). It knows nothing of `LoadoutConfig`, `Settings` or Main.
    - **The Von-server wait** (AI decision: `ai/decision/decision_server_launcher.gd`, the `DecisionServerLauncher` node of `main.tscn`):
      before it builds a match Main asks `is_resolved()` and, while not, shows `set_status` and awaits `resolved(live)` (emitted exactly once;
      `live` false = no server coming: the match starts with NPCs holding steady). Read duck-typed (`has_method("is_resolved")`), so a scene
      without the launcher starts at once.
    - `MatchHUD` (`ui/hud/match_hud.gd`, the `MatchHUD` node of `main.tscn`): `begin(combatants, time_limit := 0.0)` (every character in
      the match, a human included; an endless run's `endless_time_limit` calls a match still undecided then a draw), `set_countdown(text)`
      (the endless run's next-match line, "" clears it) and the signal `match_ended(verdict)` (Main starts the endless countdown on it).
      Main also hides the player debug panel (the `DebugUI` node) behind the setup window and frees it in a spectator match; the panel
      itself watches the player by exported path (interface 7).
    - `SpectatorInspector` (`ui/hud/spectator_inspector.gd`, built by Main under `World` in a spectator match): `setup(combatants, flags,
      right_clear)` (`flags` the overlay toggles without the global ones; `right_clear` the bar's column its outfit panel keeps clear of,
      `OverlayToggles.RESERVED_WIDTH`) and `set_flag(flag, on)` (a toggle applied live to the selected NPC). What it reads of the characters
      and their controllers is interface 7.
    - **The overlay bar** (`ui/overlays/`, built by Main the first time a match starts with Debug on): `OverlayToggles` — `setup(flags)`
      (`{ flag: bool }`, a missing flag taking its default), the signal `overlay_toggled(flag, on)` (Main's `set_overlay` saves it with
      `Settings.set_overlay` and applies it: `PERF` to its own performance overlay, in a spectator match any NPC flag to the inspector's
      `set_flag`, and the rest to the match by the one rule, `MatchBuilder.set_overlay` (interface 23): `NAV_HOLES` to the `nav_debug.gd`
      overlay's `show_holes`, `LEADERS` to the `LeaderOverlay` (interface 21), any other to every NPC) and `RESERVED_WIDTH`;
      `PerformanceOverlay.set_shown(on)`; and `OverlayRegistry` (static: `defaults() -> Dictionary` (`{ flag: bool }`), `is_global(flag)`,
      `apply(npc, flags)` (sets each `show_<x>` on every child of the NPC that has it, interface 7), `GLOBAL` and the global flags
      `NAV_HOLES`, `LEADERS` and `PERF`). The Testing domain uses the same bar (interface 13): its runner builds an `OverlayToggles` and its
      own `PerformanceOverlay` (`PERF`), and its world seeds its flags from `defaults()`, applies them to each actor with `apply` at its spawn
      and routes a toggle through `MatchBuilder.set_overlay`, as Main's match does (so `LEADERS` shows the crowns of its declared squads).
