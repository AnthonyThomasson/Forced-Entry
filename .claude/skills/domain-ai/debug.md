# AI · Debug (`scenes/ai/debug/`)

Optional, draw-only overlays that visualize an NPC's brain. Each draws on its own child `Node2D` (the `architecture` skill's layered control / animate / draw convention), reads only the sibling controller's public `debug_*` getters and exports, senses nothing and feeds nothing back, so it can never affect behaviour. They are children of the NPC in `scenes/ai/npc.tscn`.

## Files

- `debug_overlay.gd` — the base every overlay extends: finds the controller (`controller_path`) and the character, runs `PROCESS_MODE_ALWAYS` (so it still draws while the tree is paused), redraws every frame only while `_on()` is true (the subclass's `show_<x>` toggles) and calls `_paint()` only while the NPC is alive.
- `vision_debug.gd` (`show_vision`), `agent_debug.gd` (`show_actions`, `show_path`), `tactics_debug.gd` (`show_tactics`, `show_room_zones`), `search_debug.gd` (`show_search`), and the behaviour overlays `contacts_debug.gd`, `hearing_debug.gd`, `combat_debug.gd`, `territory_debug.gd`, `targets_debug.gd`, `brain_debug.gd`, `routes_debug.gd`, `stuck_debug.gd`, `grenade_overlay.gd`, `entry_debug.gd`, `entry_team_debug.gd`.
- `zone_list.gd` (`ZoneList.from_options`) — flattens a snapshot's option groups into the point zones the tactics overlay draws, and owns the `waypoint` re-tagging; the only file here the orchestrator preloads (`debug_zones()`). `debug_text.gd` — the shared label-with-shadow helper.

## Adding or toggling an overlay

All default off. Add the node under `npc.tscn`, give it a `show_<x>` property and register the flag in `scenes/ui/overlays/overlay_registry.gd` (the toggle bar; Main routes it through `MatchBuilder.set_overlay`, which sets the property on every NPC child that has it). The spectator inspector applies every per-NPC `show_<x>` flag to the clicked NPC only (during a Space-pause: the usual way to study the zones), and sets the controller's `debug_focus` (a clicked zone's point, `Vector2.INF` clears it), which the tactics overlay rings even with both toggles off.

## Per overlay gotchas

- **Vision.** The cone and the awareness bubble show only the parts with a clear line back to the NPC. The overlay casts no ray of its own: it asks the controller where sight ends (`debug_sight_end(to)` → `sight.sight_end` → `AgentVision.sight_hit`: walls and tall furniture block, low furniture is seen over), so the shadows are exactly the sense's. Each area is drawn as a triangle fan (`_fill_fan`: one `canvas_item_add_triangle_array`), never a polygon for the engine to cut: ray ends along one wall are collinear only up to float noise and `draw_polygon` then fails ("triangulation failed") and draws nothing that frame. `drawn()` reports what the last paint drew. Test: `ai/debug/vision_overlay_cone_along_wall` (the two captured failing cones, through a fake controller).
- **Tactics.** Point zones come from `debug_zones()`: `{ point, category, label, desc, tags }` per option with a world location (`grenade` zones also `from`); `ZONE_COLORS` is the legend and each category is labelled once beside its first marker. `waypoint` is the non-room go-to options (post, front entrance), re-tagged out of `room` / `search` so they do not read as misplaced rooms. Options with no location (a punch, the hostile picks) are skipped. The inspector reads `label` / `desc` to explain a clicked point. Room zones come from `debug_room_zones()` (`{ rect, type, status }`, `ROOM_COLORS`: current / searched / unsearched / unknown), per NPC: a familiar defender knows every room from the start.
- **Search.** Draws only while the NPC is actively covering a room (`debug_search_coverage()`: `active`, `points`, `unseen`, `target`, `budget`); nothing once the room is covered. See `coverage.md`.
- **Territory** draws the zones a territorial NPC drops. `tags` on `debug_zones()` entries (`inside`, `held`, `crosses`, `no_shot`, `heading`, `lane`, `hidden`, plus the geometry tags `_geo_tags()` adds) do not affect decisions beyond the booleans a node's `drop_tags` names and the confinement.

## The controller's observer getters

The controller is the single observer surface: the overlays call its getters directly with **no `has_method` guard**, so a renamed getter is an error rather than an overlay that silently draws nothing (the overlays live only under `npc.tscn`, whose controller defines every one). Keep them public and read-only.

| Getter | Source | Used by |
|---|---|---|
| `debug_status()` | behaviour | agent label |
| `debug_zones()`, `debug_room_zones()`, `debug_focus` | last snapshot, `house.room_status()` | tactics, territory, routes |
| `debug_search_coverage()` | `Behavior.errand.debug_coverage()` | search |
| `debug_sight_end(to)` | perception sight | vision |
| `known_contacts_for_display()`, `debug_memory()`, `debug_sent_callout()` | perception, comms | contacts, hearing, targets |
| `debug_combat()` | `fight.debug_combat()` | combat, territory, targets |
| `debug_brain()` | planner pending / last-failed / levels, timers, force reason, facts | brain |
| `debug_progress()` | locomotion's `stall` part `{ stalled_for, trail }` (observation only: nothing reacts to a stall) | stuck |
| `debug_grenades()` | known grenades, the evade spot, the planned throw (`Behavior.grenades.throw_plan`): `{ known, escape, throw }` | grenades |
| `debug_entry_view()` | `Behavior.entries.debug_view`: the running entry under `entry`, the entry guard under `guard` (its doorway `views`, `round_views`; the look-ahead computed only when asked) | entry, entry team |
| `debug_state()` | the deep snapshot (levels, facts, sections, contacts, `loco`, `order`, `confinement`, `decisions`, `decision_reason`) | gcmd `ai` verb, `tools/von_probe.py` |

`entry_debug` shows the doorway views the walk keeps out of (`perception-views.md`) and this NPC's entry; `entry_team_debug` the team's claims off the radio, the crossing order and the entry guard (`entry.md`).
