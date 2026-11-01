# Main: overlays and their scope

The overlay bar (`domain-ui` (`overlays.md`)) and Main's code behind it: `scenes/main_overlays.gd` (`_overlays`, holding Main) and `MatchBuilder.set_overlay` / `set_overlay_scope`
(interface 23). Interfaces: 7, 14, 22, 23.

## Main's flags and scope

- `_overlays.flags` has one entry per `OverlayRegistry` row, seeded by `initial(debug)`: the registry defaults, then the saved toggles (`Settings.overlays`) over them; Debug off starts every flag off.
  `start_match` hands them to the match as its spec's `overlays`. `npc_flags()` is `flags` without the global ones.
- The bar's `overlay_toggled` reaches Main's public `set_overlay(flag, on)`, which saves the flip (`Settings.set_overlay`) and routes it (`_overlays.route`): `PERF` to Main's own performance
  overlay; in a spectator match an NPC's flag to `SpectatorInspector.set_flag` (it applies to the NPCs that show: the scope's and the selected one); the rest to `MatchBuilder.set_overlay(_match, flag, on)`
  (the navigation holes, the squad leaders, and in a played match every NPC's own overlay, on the NPCs of the scope).
- **The scope** (the bar's "Show on" row) is per mode, `_overlays.mode` (`play` / `watch`). `_overlays.begin(spectator, handle)` takes `Settings.overlay_scopes` for the mode, else
  `OverlayRegistry.default_scope(mode)` (`play` → `all`, `watch` → `selected`); a saved scope the mode does not offer (`selected` in a played match) falls back to that default. A played match applies it at once with
  `MatchBuilder.set_overlay_scope`; a spectator match gets it from `set_scope` right after the inspector's `setup`. The bar is built with `bar.setup(flags, scope, OverlayRegistry.scopes_of(mode))`.
- The bar's `scope_changed` reaches Main's public `set_overlay_scope(scope)` (`_overlays.change_scope`): it saves the scope with `Settings.set_overlay_scope(mode, scope)` (player choices only) and applies it live,
  through `SpectatorInspector.set_scope` in a spectator match, else `MatchBuilder.set_overlay_scope`. An endless run keeps the scope across matches, as the bar is built once.

## Routing in `MatchBuilder`

- `set_overlay(handle, flag, on)`: `NAV_HOLES` to the handle's `nav_debug` (`show_holes`, redrawn), `LEADERS` to its `leader_overlay` (`show_leaders`; a world with no squads has none), any other non-global flag to the
  combatants through the one shared gate; `PERF` is not the match's.
- `set_overlay_scope(handle, flags, scope)` records `scope` (`all`, `defenders` or `invaders`) on the handle as `overlay_scope` and applies `flags` at once through the same gate and the same loop.
- **One gate:** `_apply_in_scope` (looped over the combatants by `_apply_to_combatants`) gives an NPC in the handle's `overlay_scope` (`all` with none) `OverlayRegistry.apply` as given, every other NPC all-off,
  and a character with no AI controller (the human) nothing.
- The Testing world calls `set_overlay_scope` for the one actor it spawns (a handle of that actor alone), so an actor spawned after a scope is set follows it; its runner bar offers `defenders`, `invaders`, `all`
  (no `selected`: the runner has no detail card).

## Tests

`tests/ui/main_no_demo_panel_test.gd` (Main's scene holds no player debug node and no demo label, and neither does the live tree of Main run whole with a played match), `overlay_scope_sides_test.gd` (a test
world's scope through `set_overlay_scope`; a stand-in overlay on the human records every write, and none comes), `inspector_scope_test.gd` (the spectator scope), `overlay_scope_saved_per_mode_test.gd` (Main run whole from the
setup window's Start against a scratch settings file: the watch and play scopes saved apart, restored on a fresh launch, an endless run keeping its scope).
