# UI overlays (`scenes/ui/overlays/`)

The tooling that switches the AI and nav debug overlays on and off and shows engine stats. The overlay draw scripts live in `scenes/ai/debug/`
(`domain-ai` (`debug.md`)); this folder holds each flag's registry row and the bars that flip it. Interfaces: 7, 11, 13, 21, 22, 23.
Tests: `tests/ui/overlay_toggles_test.gd`, `leader_overlay_draw_test.gd`.

## `overlay_registry.gd` — `OverlayRegistry`, the one table of overlays

- `ENTRIES` rows are `{ flag, label, group, default }`; `flag` is the overlay node's `show_<x>` property name. The toggle bar, Main, `MatchBuilder.set_overlay`,
  the test runner and the Testing world all read the table. **A new overlay is one row here, its draw script in `scenes/ai/debug/` and a node in `scenes/ai/npc.tscn`.**
- Three flags are global, not per NPC (`GLOBAL`, `is_global(flag)`): `NAV_HOLES` (`show_nav_holes`, the match's single `NavDebug`), `LEADERS` (`show_leaders`,
  the single `LeaderOverlay`) and `PERF` (`show_perf`, the performance overlay).
- `apply(npc, flags)` is the one loop that sets each `show_<x>` on the NPC's children that have it and redraws them. The spectator inspector applies a
  selection through it, and the Testing world applies each actor's flags at spawn.

## `overlay_toggles.gd` — `OverlayToggles` (CanvasLayer)

- Built by Main after the world spawns, only when Debug is on; the Testing runner builds the same bar. A collapsible top-right panel of toggle buttons grouped from the
  registry. An **All (n/N)** button and each group header flip a whole set (all on unless already all on, then all off); every changed flag emits its own
  `overlay_toggled(flag, on)`, so no bulk path exists downstream. `RESERVED_WIDTH` is the screen width it occupies from the right edge; other widgets keep clear of it.
- Routing of `overlay_toggled` in Main's `set_overlay` (which also saves the flip): `show_perf` goes to the `PerformanceOverlay`; in spectator mode an NPC flag goes to
  `SpectatorInspector.set_flag`, so the selected NPC follows; the rest goes to `MatchBuilder.set_overlay` (interface 23: `show_nav_holes` → the `NavDebug`, `show_leaders`
  → the `LeaderOverlay`, any other → every NPC through `OverlayRegistry.apply`). The Testing world's `set_overlay` routes the runner bar through the same function.
- `PROCESS_MODE_ALWAYS`; the panel swallows clicks, so pressing a button never selects an NPC; buttons take no focus (Space stays pause / interact).

## `performance_overlay.gd` — `PerformanceOverlay` (CanvasLayer 9)

Built by Main next to the bar when Debug is on; `set_shown(on)` from the "Performance" toggle (off by default). Docked left of the bar (`OverlayToggles.RESERVED_WIDTH`) at y 76,
below the match HUD's timer, so it overlaps no other HUD. Shows Godot `Performance` monitors and a frame-time graph. It swallows clicks, so it blocks click-to-inspect
beneath it. `PROCESS_MODE_ALWAYS`; hidden, it stops processing.

## `leader_overlay.gd` — `LeaderOverlay` (Node2D, `DrawLayers.ABOVE`, `PROCESS_MODE_ALWAYS`; `docs/leadership.md` LD12, LD28)

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
