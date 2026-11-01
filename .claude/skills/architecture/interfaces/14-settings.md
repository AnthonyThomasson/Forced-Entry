14. **Main → General settings, UI settings page** (the composition root wires them; they never meet)
    - `Settings` (`general/settings.gd`, static holder) persists to `user://settings.json`: the Debug switch (`debug`), the setup window's last
      choices (`setup`), the overlay toggles (`overlays`), the scope they show on per mode (`overlay_scopes`, `{ play, watch }`, only the modes the player chose a scope for; a mode with none starts on
      `OverlayRegistry.DEFAULT_SCOPES`, which Main reads: `Settings` depends on no UI) and the `Keybinds` bindings that differ from the defaults
      (`Keybinds.bindings.overrides()` / `apply_overrides`, the rebinding store the autoload holds as its `bindings` part; a binding saved under an
      alias, `Keybinds.ALIASES` (`use_vehicle` → `use`), is read as the action's, the action's own name winning). Main calls
      `load_file()` once in `_ready`, after seeding `Settings.debug` from `run.debug_overlays`; `Keybinds._ready` does not, so tests never
      read a developer's file. Mutators save: `set_debug(on)`, `set_setup(config)`, `set_overlay(flag, on)`, `set_overlay_scope(mode, scope)`, `rebind(action, event) -> bool`,
      `reset(action)`, `reset_all()`; `binding_rows() -> Array` gives the page plain dicts.
    - `SettingsMenu` (`ui/menus/settings_menu.gd`): `open({ debug, rows })`, `set_rows(rows)`; signals `debug_changed(on)`,
      `rebind_requested(action, event)`, `reset_requested(action)`, `reset_all_requested`, `back_requested`. It knows nothing of `Keybinds`
      or `Settings`: Main opens it from the setup window's `settings_requested`, applies each signal to `Settings` and redraws with `set_rows`.
    - Main ↔ the dev command server (`general/command_server.gd`): it finds the match's nodes through the group `match_world`, restarts
      through `Main.return_to_setup()`, hands a seed over through the Engine metas `skip_setup` / `match_seed`, and drives the node named
      `Player`. Those names are the whole contract.
