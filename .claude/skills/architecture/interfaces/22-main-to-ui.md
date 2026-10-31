22. **Main → UI: setup window, match HUD, spectator inspector, overlay bar** (the composition root wires them in the shape of 14: plain dicts
    in, signals out; the flow is `domain-main`'s, the widgets `domain-ui`'s)
    - `SetupMenu` (`ui/menus/setup_menu.gd`, node `SetupMenu` of `main.tscn`): `open(defaults)` (Main's `run` with the saved `Settings.setup`
      laid over it, plus the choice rows as plain data: `weapons` from `LoadoutConfig.options()`, `grenades` from `grenade_options()`,
      `outfits` from `outfit_options()`, and the run's `ticket`), `current_config() -> Dictionary` (`{ side, seed, lead, defenders,
      invaders }` as they stand, `{}` before `open`; Main saves it with `Settings.set_setup` when the window is left without starting),
      `set_status(text)` (a line while Main holds the start; "" hides it). Signals: `start_requested(config)` (`{ mode` (`play` / `watch` /
      `endless`)`, side, seed, lead, defenders, invaders }`, each side `{ count, weapon, magazine, spares, stuns, frags, outfit }`),
      `tests_requested` (Main changes scene to the test browser, 13) and `settings_requested` (Main opens the settings page, 14). It knows
      nothing of `LoadoutConfig`, `Settings` or Main.
    - **The Von-server wait** (`DecisionServerLauncher`, `ai/decision/decision_server_launcher.gd`, node of `main.tscn`): before building a
      match Main asks `is_resolved()` and, while not, shows `set_status` and awaits `resolved(live)` (emitted exactly once; `live` false = no
      server coming: NPCs hold steady). Read duck-typed (`has_method("is_resolved")`), so a scene without the launcher starts at once.
    - `MatchHUD` (`ui/hud/match_hud.gd`, node `MatchHUD`): `begin(combatants, time_limit := 0.0)` (every character in the match, a human
      included; an endless run's `endless_time_limit` calls a match still undecided then a draw), `set_countdown(text)` (the endless run's
      next-match line; "" clears it), signal `match_ended(verdict)` (Main starts the endless countdown on it). Main hides the player debug
      panel (`DebugUI` node, which watches the player by exported path, 7) behind the setup window and frees it in a spectator match.
    - `SpectatorInspector` (`ui/hud/spectator_inspector.gd`, built by Main under `World` in a spectator match): `setup(combatants, flags,
      right_clear)` (`flags` the overlay toggles without the global ones; `right_clear` the bar's column its outfit panel keeps clear of,
      `OverlayToggles.RESERVED_WIDTH`), `set_flag(flag, on)` (a toggle applied live to the selected NPC). What it reads of the characters
      and their controllers is 7.
    - **The overlay bar** (`ui/overlays/`, built by Main the first time a match starts with Debug on): `OverlayToggles` `setup(flags)` (`{ flag:
      bool }`, a missing flag taking its default), signal `overlay_toggled(flag, on)`, `RESERVED_WIDTH`. Main's `set_overlay` saves a
      toggle with `Settings.set_overlay` and applies it: `PERF` to `PerformanceOverlay.set_shown(on)`; in a spectator match any NPC flag
      to the inspector's `set_flag`; the rest to the match by `MatchBuilder.set_overlay` (23): `NAV_HOLES` to the `nav_debug.gd`
      overlay's `show_holes`, `LEADERS` to the `LeaderOverlay`'s `show_leaders` (21), any other to every NPC.
      `OverlayRegistry` (static): `defaults() -> Dictionary` (`{ flag: bool }`), `is_global(flag)`, `apply(npc, flags)` (sets each `show_<x>`
      on every child of the NPC that has it, 7), `GLOBAL` and the global flags `NAV_HOLES`, `LEADERS`, `PERF`.
    - **Testing uses the same bar** (13): its runner builds an `OverlayToggles` and its own `PerformanceOverlay` (`PERF`); its world seeds
      its flags from `defaults()`, applies them to each actor with `apply` at its spawn and routes a toggle through
      `MatchBuilder.set_overlay`, as Main's match does (so `LEADERS` shows the crowns of its declared squads).
