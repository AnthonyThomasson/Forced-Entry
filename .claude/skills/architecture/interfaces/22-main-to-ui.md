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
      next-match line; "" clears it), signal `match_ended(verdict)` (Main starts the endless countdown on it); `PANEL_TOP` is the top edge the panels under its timer share. A played match has no per-character readout.
    - `SpectatorInspector` (`ui/hud/spectator_inspector.gd`, built by Main under `World` in a spectator match): `setup(combatants, flags,
      right_clear)` (`flags` the overlay toggles without the global ones; `right_clear` the bar's column its detail card keeps clear of,
      `OverlayToggles.RESERVED_WIDTH`), `set_flag(flag, on)` (a toggle applied live to the NPCs that show overlays) and `set_scope(scope)` (which NPCs show them besides the selected one: `selected`,
      `defenders`, `invaders` or `all`, applied at once, also paused). A right-click on an NPC selects it and opens its `DetailCard` (`ui/hud/detail_card.gd`: name · side · rank, health, item and ammo, grenades, outfit lines,
      and the `card_lines()` of its decision, brain, search and entry overlays, 7); a right-click on it again or on empty ground closes it; a left-click on one of its `debug_zones()` points sets its `debug_focus` and
      shows it in the card's Point section. What it reads of the characters and their controllers is 7.
    - **The overlays' words** (what the card and the inspector read of the NPC's overlays, `ai/debug/debug_overlay.gd`, `domain-ai` (`debug-words.md`)): every overlay has `text_in_world: bool` (default true; off, the agent, brain, search
      and entry overlays draw no text; the inspector's `setup` turns it off on every combatant) and `drawn_texts() -> PackedStringArray` (the strings its last paint drew, for tests); those four give `card_lines() -> PackedStringArray`
      (the lines they draw as text, read duck-typed off the children `AgentDebug`, `BrainDebug`, `SearchDebug` and `EntryDebug`). The brain overlay has `brain_labels: bool` (default false: with `text_in_world` off it draws nothing
      at all unless it is on, then its bars, ring and short labels; the inspector sets it on the selected NPC alone) and `drawn() -> Array` (what its last paint drew, `{ kind: &"bar" | &"ring" | &"label", … }`, cleared at
      each redraw: a read-out for tests, like `VisionDebug.drawn()`).
    - **The overlay bar** (`ui/overlays/`, built by Main the first time a match starts with Debug on): `OverlayToggles` `setup(flags, scope, scopes)` (`{ flag:
      bool }`, a missing flag taking its default; `scopes` the "Show on" choices from `OverlayRegistry.scopes_of(mode)`, none: no row; `scope` the one chosen), signals `overlay_toggled(flag, on)` and `scope_changed(scope)`
      (Main's `set_overlay_scope` saves it per mode with `Settings.set_overlay_scope`, 14, and applies it: a spectator match through the inspector's `set_scope`, a played one through `MatchBuilder.set_overlay_scope`, 23), `RESERVED_WIDTH`. Main's `set_overlay` saves a
      toggle with `Settings.set_overlay` and applies it: `PERF` to `PerformanceOverlay.set_shown(on)`; in a spectator match any NPC flag
      to the inspector's `set_flag`; the rest to the match by `MatchBuilder.set_overlay` (23): `NAV_HOLES` to the `nav_debug.gd`
      overlay's `show_holes`, `LEADERS` to the `LeaderOverlay`'s `show_leaders` (21), any other to the NPCs in the scope.
      `OverlayRegistry` (static): `defaults() -> Dictionary` (`{ flag: bool }`), `is_global(flag)`, `apply(npc, flags)` (sets each `show_<x>`
      on every child of the NPC that has it, 7), `GLOBAL` and the global flags `NAV_HOLES`, `LEADERS`, `PERF`; the scope: `SCOPES` (`SCOPE_SELECTED`, `SCOPE_DEFENDERS`, `SCOPE_INVADERS`, `SCOPE_ALL`), the modes
      `MODE_PLAY` and `MODE_WATCH`, `DEFAULT_SCOPES`, `default_scope(mode)`, `scopes_of(mode) -> Array` (`selected` in `watch` only), `side_of(faction) -> String` (`defender` / `invader`) and `in_scope(npc, scope) -> bool` (`all`, or the
      NPC's `faction` is the side's: `defenders` `household`, `invaders` `invader`; `selected` none, the inspector adds its selection).
    - **Testing uses the same bar** (13): its runner builds an `OverlayToggles` and its own `PerformanceOverlay` (`PERF`); its world seeds
      its flags from `defaults()`, hands them to each actor at its spawn through `MatchBuilder.set_overlay_scope` (so the scope's gate applies) and routes a toggle through
      `MatchBuilder.set_overlay` and a scope through `MatchBuilder.set_overlay_scope`, as Main's match does (so `LEADERS` shows the crowns of its declared squads).
