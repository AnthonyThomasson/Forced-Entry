14. **Main → General settings, UI settings page** (the composition root wires them; they never meet)
    - `Settings` (`general/settings.gd`, static holder) persists to `user://settings.json`: the Debug switch (`debug`), the render mode (`render_mode`: `Settings.RENDER_2D` `"2d"`, the default, or `RENDER_3D` `"3d"`; a saved value that is neither is skipped; Main reads it when a match starts, so it applies at the next match: 27), the setup window's last
      choices (`setup`), the overlay toggles (`overlays`), the scope they show on per mode (`overlay_scopes`, `{ play, watch }`, only the modes the player chose a scope for; a mode with none starts on
      `OverlayRegistry.DEFAULT_SCOPES`, which Main reads: `Settings` depends on no UI) and the `Keybinds` bindings that differ from the defaults
      (`Keybinds.bindings.overrides()` / `apply_overrides`, the rebinding store the autoload holds as its `bindings` part; a saved binding of an action
      that no longer exists, as the old `use` / `use_vehicle`, is dropped, and the camera turn actions `camera_turn_left` / `camera_turn_right`, default Q / E, are rows like the others). Main calls
      `load_file()` once in `_ready`, after seeding `Settings.debug` from `run.debug_overlays`; `Keybinds._ready` does not, so tests never
      read a developer's file. Mutators save: `set_debug(on)`, `set_render_mode(mode)` (anything but 2d or 3d is refused with a warning), `set_setup(config)`, `set_overlay(flag, on)`, `set_overlay_scope(mode, scope)`, `rebind(action, event) -> bool`,
      `reset(action)`, `reset_all()`; `binding_rows() -> Array` gives the page plain dicts.
    - `SettingsMenu` (`ui/menus/settings_menu.gd`): `open({ debug, render_mode, rows })` (`render_mode` `"2d"` when absent), `set_rows(rows)`; signals `debug_changed(on)`, `render_mode_changed(mode)` (a 2D / 3D drop-down beside Debug),
      `rebind_requested(action, event)`, `reset_requested(action)`, `reset_all_requested`, `back_requested`. It knows nothing of `Keybinds`
      or `Settings`: Main opens it from the setup window's `settings_requested`, applies each signal to `Settings` and redraws with `set_rows`.
    - Main ↔ the dev command server (`general/command_server.gd`): it finds the match's nodes through the group `match_world`, restarts
      through `Main.return_to_setup()`, hands a seed over through the Engine metas `skip_setup` / `match_seed`, and drives the node named
      `Player`. Those names are the whole contract.
