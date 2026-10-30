14. **Main → General settings, UI settings page** (the composition root wires them; they never meet)
    - `Settings` (`general/settings.gd`, a `class_name` static holder): `load_file()` (Main calls it once in
      `_ready`, after seeding `Settings.debug` from its `run.debug_overlays` — not `Keybinds._ready`, so tests never
      read a developer's file), the saving mutators `set_debug(on)`, `set_setup(config)`, `set_overlay(flag, on)`, `rebind(action, event) -> bool`,
      `reset(action)`, `reset_all()`, and `binding_rows() -> Array` (plain dicts for the page). It persists
      the Debug switch, the setup window's last choices (`setup`), the overlay toggles (`overlays`) and the `Keybinds`
      bindings that differ from the defaults (`Keybinds.bindings.overrides()` / `apply_overrides`, the rebinding store the
      autoload holds as its `bindings` part) to `user://settings.json`.
    - Main ↔ the dev command server (General, `general/command_server.gd`): it finds the match's nodes through the
      `match_world` group, restarts through `Main.return_to_setup()`, hands a seed over through the Engine metas
      `skip_setup` / `match_seed`, and drives the node named `Player`; those names are the whole contract.
    - `SettingsMenu` (`ui/menus/settings_menu.gd`): `open({ debug, rows })`, `set_rows(rows)`; signals
      `debug_changed`, `rebind_requested(action, event)`, `reset_requested`, `reset_all_requested`,
      `back_requested`. It takes plain dicts and knows nothing of `Keybinds`/`Settings`; Main opens it from the
      setup window's `settings_requested`, applies each signal to `Settings` and redraws with `set_rows`.
