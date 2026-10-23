---
name: domain-ui-overlays
description: Deep implementation detail for the UI overlays sub-domain (scenes/ui/overlays/) — the single table of debug overlays (OverlayRegistry), the in-game overlay toggle bar (OverlayToggles with group buttons and All), the performance overlay (FPS, frame time, draw calls, graph), the squad-leaders overlay (a crown over each side's leader, its leash, its trail and the follow spots) and the DragHandle helper. Use when editing scenes/ui/overlays/ or adding/renaming a debug overlay flag, the toggle bar or the performance panel. Complements the `domain-ui` overview, `domain-ai-debug` (the overlay draw scripts) and the `architecture` skill.
---

# UI · Overlays sub-domain (`scenes/ui/overlays/`)

The tooling that switches the AI/nav debug overlays on and off and shows engine stats. The overlay draw scripts themselves live in `scenes/ai/debug/` (`domain-ai-debug`); this folder holds the registry row for each flag and the bars that flip it. See `domain-ui` for what all UI scripts share.

- `overlay_registry.gd` — the ONE table of debug overlays (`ENTRIES`: `flag`, `label`, `group`, `default`;
  `defaults()`; `NAV_HOLES` (labelled "Navigation holes": furniture and characters at rest), `LEADERS` (`show_leaders`, "Squad leaders", group Team) and `PERF`, the global non-per-NPC flags, listed in `GLOBAL` / `is_global(flag)`).
  `flag` is the overlay node's `show_<x>` property name. The toggle bar, Main, the match builder (`MatchBuilder.set_overlay`), the test runner and the Testing world all read it, so a new overlay is one row here
  plus its draw script (`scenes/ai/debug/`) and a node in `ai/npc.tscn`. `show_grenades` ("Grenades", group Combat) is the grenade overlay (`grenade_overlay.gd`, docs/grenades.md G19).

- `overlay_toggles.gd` — the **in-game overlay toggle bar** (`OverlayToggles` CanvasLayer, built by
  `main.gd` after the world spawns, both modes, only when Debug is on; the Testing runner builds the same bar, and the
  performance overlay, for its own overlay toggles). A collapsible top-right panel (1.5× scale: `SCALE` in the script) of toggle buttons grouped
  from the registry (Perception / Combat / Movement / Brain / Team / Entry / Map / Stats). An **All (n/N)** button and each
  group's header button (`Perception (n/N)`) flip a whole set: all on unless already all on, then all off; each
  changed flag emits its own `overlay_toggled`, so Main needs no bulk path. `RESERVED_WIDTH` is the screen width it occupies from the right edge. `setup(flags)` seeds the buttons;
  pressing one emits `overlay_toggled(flag, on)`, which Main applies live (its `set_overlay`, which saves the flip: `show_perf` → its
  PerformanceOverlay; spectator mode, an NPC flag → `SpectatorInspector.set_flag`, so the selected NPC follows; the rest → the match by
  the one routing rule, `MatchBuilder.set_overlay` (architecture interface 23): `show_nav_holes` → the match's single NavDebug,
  `show_leaders` → its LeaderOverlay, any other → every NPC's overlay through `OverlayRegistry.apply(npc, flags)` (the one loop that sets
  each `show_<x>` on the children that have it and redraws them; the spectator inspector applies a selection through it, and the Testing
  world each actor's flags at spawn). The Testing world's `set_overlay` routes the runner bar's toggles through the same
  `MatchBuilder.set_overlay`).
  `PROCESS_MODE_ALWAYS` (works while paused); the panel swallows clicks so pressing a button never selects
  an NPC; buttons take no focus (Space stays pause/interact). The "Overlays" title is a drag handle
  (`DragHandle`) that moves the bar; the `▸/▾` button beside it collapses it. Tested by `tests/ui/overlay_toggles_test.gd`.

- `drag_handle.gd` — the **drag-to-move helper** (`DragHandle` Node, added as a child of the handle Control;
  `setup(handle, target)`). Left-drag the handle to move `target` by shifting its offsets (anchors kept, so it
  stays put relative to its screen edge on resize), clamped inside the viewport. Used by the toggle bar
  (title) and the performance overlay (whole panel).

- `leader_overlay.gd` — the **squad-leaders overlay** (`LeaderOverlay` Node2D, world space, z at `DrawLayers.ABOVE`, `PROCESS_MODE_ALWAYS`;
  `docs/leadership.md` LD12, interface 21), built by the match builder with the squads (`MatchBuilder.build_leader_overlay`, named `LeaderOverlay`, hidden: under `World` in
  every match, under a test world that declares squads or a match), the match handle's `leader_overlay`.
  `watch(views)` takes every squad's `view()` callable; while `show_leaders` is on (the global `LEADERS` row, off by default, set through
  `MatchBuilder.set_overlay`, from Main's bar or the test runner's) it draws a gold crown over each squad's living leader (`LIFT` 30 px above the body), following the next in line
  when one falls, and how the squad follows it (`docs/leadership.md` LD28): the leash ring round the leader (the view's `leash`,
  `LEASH_COLOR`), each follower's follow spot as a small ring (`SPOT_RADIUS` 6 px) with a thin line from the follower to it (each member
  row's `follow_spot`, none at `Vector2.INF`; `SPOT_COLOR`), and the leader's trail dotted (the view's `trail`, `draw_dashed_line` per
  segment, `DOT` 3 px; from two points). `drawn()` is `[{ kind: "crown", point, node }]` per crown, `{ kind: "leash", point, radius, node }`,
  `{ kind: "spot", point, node }`, `{ kind: "line", from, to, node }` and `{ kind: "trail", points }` ([] while off), redrawn only when it
  changes; a view without `leash`, `trail` or `follow_spot` gives crowns alone. Reads the squads through `view()` and the leader and members
  through the Character API only (`global_position`, `is_dead`). A test world that declares no squads has none, so its bar's row does nothing there. Tested by
  `tests/ui/leader_overlay_draw_test.gd` (fake views; a test world's declared squads and Main's match, toggled through `set_overlay`).

- `performance_overlay.gd` — the **performance overlay** (`PerformanceOverlay` CanvasLayer, layer 9, built by
  `main.gd` next to the toggle bar when Debug is on; `set_shown(on)` from the "Performance" toggle, off
  by default). A compact semi-transparent panel docked left of the toggle bar (`OverlayToggles.RESERVED_WIDTH`)
  at y 76 — below the match HUD's top-centre timer, so it overlaps no other
  HUD in either mode. Shows FPS (+ low over the last `SAMPLES` frames), frame / physics ms, draw calls,
  objects, node count, active 2D physics objects, static memory (Godot `Performance` monitors, text refreshed
  every `REFRESH` s) and a per-frame frame-time bar graph with a 16.7 ms reference line. Left-drag the panel to
  move it (it swallows clicks, so it blocks click-to-inspect beneath it). `PROCESS_MODE_ALWAYS` (keeps
  updating while paused); hidden it stops processing.

**Interfaces:** 7 (the overlays' `show_<x>` exports), 13 (the Testing runner's overlay bar), 22 (the overlay bar and `OverlayRegistry` Main wires) — signatures in `architecture`.
