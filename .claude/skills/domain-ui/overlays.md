# UI overlays (`scenes/ui/overlays/`)

The tooling that switches the AI and nav debug overlays on and off and shows engine stats. The overlay draw scripts live in `scenes/ai/debug/`
(`domain-ai` (`debug.md`)); this folder holds each flag's registry row, the scope that says which NPCs show them and the bars that flip them. Interfaces: 7, 11, 13, 14, 21, 22, 23.
Tests: `tests/ui/overlay_toggles_test.gd` (the "Show on" row, `scope_changed`, the scope saved through `Settings`), `overlay_scope_sides_test.gd` (a test world's scope), `overlay_scope_saved_per_mode_test.gd` (Main run whole, `domain-main`), `leader_overlay_draw_test.gd`.

## `overlay_registry.gd` — `OverlayRegistry`, the one table of overlays

- `ENTRIES` rows are `{ flag, label, group, default }`; `flag` is the overlay node's `show_<x>` property name. The toggle bar, Main, `MatchBuilder.set_overlay`,
  the test runner and the Testing world all read the table. **A new overlay is one row here, its draw script in `scenes/ai/debug/` and a node in `scenes/ai/npc.tscn`.**
- Three flags are global, not per NPC (`GLOBAL`, `is_global(flag)`): `NAV_HOLES` (`show_nav_holes`, the match's single `NavDebug`), `LEADERS` (`show_leaders`,
  the single `LeaderOverlay`) and `PERF` (`show_perf`, the performance overlay).
- `apply(npc, flags)` is the one loop that sets each `show_<x>` (or any other property by name: `text_in_world`, `brain_labels`) on the NPC's children that have it and
  redraws them. The spectator inspector applies a selection through it; `MatchBuilder` reaches it only through its scope gate (`domain-main`).
- **The overlay scope** says which NPCs show the per-NPC overlays (`GLOBAL` flags ignore it). Names `SCOPE_SELECTED`, `SCOPE_DEFENDERS`, `SCOPE_INVADERS`, `SCOPE_ALL`, listed in
  `SCOPES` in the order the bar offers them; `SIDE_FACTIONS` maps a side scope to its faction (`defenders` → `household`, `invaders` → `invader`).
  - `in_scope(npc, scope) -> bool`: `all` takes every NPC, a side scope the NPCs of that faction, `selected` none (the spectator inspector adds its selection).
  - Modes: `MODE_PLAY` and `MODE_WATCH`, the keys of `Settings.overlay_scopes`. `DEFAULT_SCOPES` is the one table of what each starts on (`play` → `all`, `watch` → `selected`), read by
    `default_scope(mode)`. `scopes_of(mode)` is what the bar offers (`selected` in `watch` only); Main and the test runner both ask it.
  - `side_of(faction)` is the word for a side (`defender` / `invader`) the detail card titles an NPC with.
  - No scope or overlay mode is spelled outside this file (the setup window's `play` / `watch` / `endless` are another vocabulary).
  - The rule every router applies: an NPC shows the on-toggles' overlays iff it is in scope (or, in a spectator match, selected); every other NPC's per-NPC overlays are all-off. A character with no AI controller (the human) never gets overlays.

## `overlay_toggles.gd` — `OverlayToggles` (CanvasLayer)

- Built by Main after the world spawns, only when Debug is on; the Testing runner builds the same bar. A collapsible top-right panel with a **Show on** row of radio buttons (one per scope it was given; none: no row) above the toggle buttons grouped from the
  registry. `setup(flags, scope, scopes)` seeds the toggles and starts the row on `scope`: a spectator match offers `selected`, `defenders`, `invaders`, `all` (default `selected`); a played match and the test runner offer `defenders`, `invaders`, `all` (default `all`).
  `scope_changed(scope)` announces the scope chosen, not the old button un-pressing. An **All (n/N)** button and each group header flip a whole set (all on unless already all on, then all off); every changed flag emits its own
  `overlay_toggled(flag, on)`, so no bulk path exists downstream. `RESERVED_WIDTH` is the screen width it occupies from the right edge; other widgets keep clear of it.
- Routing of `overlay_toggled` in Main's `set_overlay` (which also saves the flip): `show_perf` goes to the `PerformanceOverlay`; in spectator mode an NPC flag goes to
  `SpectatorInspector.set_flag`, so the selected NPC follows; the rest goes to `MatchBuilder.set_overlay` (interface 23: `show_nav_holes` → the `NavDebug`, `show_leaders`
  → the `LeaderOverlay`, any other → the NPCs of the handle's `overlay_scope` through `OverlayRegistry.apply`). The Testing world's `set_overlay` routes the runner bar through the same function.
- `scope_changed` reaches Main's `set_overlay_scope(scope)`, which saves it per mode in `Settings.overlay_scopes` and applies it at once, also paused: a spectator match through
  `SpectatorInspector.set_scope`, a played one through `MatchBuilder.set_overlay_scope(handle, flags, scope)`. The runner bar's reaches `TestWorld.set_overlay_scope` the same way.
- `PROCESS_MODE_ALWAYS`; the panel swallows clicks, so pressing a button never selects an NPC; buttons take no focus (Space stays pause / interact).

## `performance_overlay.gd` — `PerformanceOverlay` (CanvasLayer 9)

Built by Main next to the bar when Debug is on; `set_shown(on)` from the "Performance" toggle (off by default). Docked left of the bar (`OverlayToggles.RESERVED_WIDTH`) at y `PANEL_TOP` (76, the line `MatchHUD.PANEL_TOP` gives the detail card; a literal here so this folder reads nothing of the hud),
below the match HUD's timer, so it overlaps no other HUD. Shows Godot `Performance` monitors and a frame-time graph. It swallows clicks, so it blocks the inspector's right-click select
beneath it. `PROCESS_MODE_ALWAYS`; hidden, it stops processing.

## `leader_overlay.gd` — `LeaderOverlay` (Node2D, an overlay: `ViewLayers.overlay`, `DrawLayers.OVERLAY` absolute over the player's view, `PROCESS_MODE_ALWAYS`; `docs/leadership.md` LD12, LD28)

- Built hidden by `MatchBuilder.build_leader_overlay` with the squads (under `World` in every match, and in a test world that declares squads or a match); it is the match handle's
  `leader_overlay`. A test world without squads has none, so the bar's row does nothing there.
- `watch(views)` takes every squad's `view()` callable. While `show_leaders` is on it draws a crown over each squad's living leader (the next in line when one falls), the
  leash ring (the view's `leash`), each follower's follow spot with a line to it (a member row's `follow_spot`, `Vector2.INF` for none) and the leader's trail (the view's
  `trail`). A view without those keys gives crowns alone.
- `drawn()` (the test's read-out): `{ kind: "crown"|"leash"|"spot"|"line"|"trail", … }` rows, `[]` while off. It reads the squads through `view()` and the members through
  the Character API only.

## `drag_handle.gd` — `DragHandle`

A child `Node` of a handle `Control`; `setup(handle, target)` makes a left-drag on the handle move `target` by shifting its offsets (anchors kept), clamped inside the
viewport. Used by the toggle bar (its title) and the performance overlay (the whole panel).
