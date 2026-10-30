---
name: domain-ui-hud
description: Deep implementation detail for the UI hud sub-domain (scenes/ui/hud/) — the player debug panel (DebugUI), the spectator match HUD (MatchHUD: timer, winner banner, match_ended), the spectator inspector (click-to-select NPC, pause, tactical-point details, the selected NPC's outfit) and its world-space contact markers, the stack markers, the stun screen, and the shared outfit lines (outfit_lines.gd). The human leader's command menu and order markers are `domain-ui-command`. Use when editing scenes/ui/hud/ or working on the in-game HUDs, match verdict, or click-to-inspect. Decoupled observers of the Character API and the EventBus. Complements the `domain-ui` overview and the `architecture` skill.
---

# UI · HUD sub-domain (`scenes/ui/hud/`)

The in-game observers: each reads only the Character public API / signals (incl. `wardrobe.outfit.view()`), the AI controller's `debug_zones()` / `known_contacts_for_display()` and `debug_focus`, `PlayerStack.view()` and a squad's `view()` callable (the stack markers' `watch` and `watch_squad`), Items' `LoadoutConfig.grenade_options()` (the debug panel), General's `MatchVerdict.decide` (the match HUD), `DrawLayers.ABOVE` (the stack markers) and `Keybinds.PAUSE` (the inspector) and, for the stun screen, the EventBus `&"stun"` topic. The human leader's command menu and order markers are `scenes/ui/command/` (`domain-ui-command`). See `domain-ui` for what all UI scripts share.

- `debug_ui.gd` — the **player debug panel** (`DebugUI` node). Bottom-right stats block: current
  item slot, an ammo line (`Ammo: 7/12  (+2 mags)`, "reloading…" mid-swap, "—" for an item without ammo, read through
  `ammo.rounds()` / `ammo.capacity()` / `ammo.spare_magazines()` / `ammo.is_reloading()`), a grenades line (`Grenades: 1 stun, 2 frag`, "—" with none, read through `inventory.item_count(slot)` for the slots of `LoadoutConfig.grenade_options()`), punch active flag, active interaction, reach, stamina (and whether running), posture (`Standing` / `Crouching`, read through `movement.posture()`). Top-left hit banner: last body hit, method
  (punch left/right, kick or gunshot) and damage; the bottom-right "Last Hit" block adds the time since. Attaches to its character by the
  exported `character_path`; listens to `hit_landed` on the character; freed in spectator mode. Font sizes: stats 34pt, hit banner 32pt.
  Bottom left (26pt, growing up from the bottom edge: free), an `=== OUTFIT ===` block of
  `OutfitLines.of(wardrobe.outfit.view())`, refreshed every frame (`docs/outfits.md` O13). Tested by `tests/ui/debug_panel_outfit_test.gd`.

- `match_hud.gd` — the **spectator match HUD** (`MatchHUD` node). `begin(combatants, time_limit := 0.0)` wires it to
  any number of characters (a human included); it is **re-entrant** (an endless run calls it for each new match),
  emits `match_ended(verdict)` once when a faction is eliminated or `time_limit` seconds pass undecided
  ("TIME UP - DRAW"), `set_countdown(text)` shows a line under the verdict (Main's next-match countdown), and
  nothing else is shown but a top-centre running timer (34pt) and a centre winner banner (62pt gold): no goal readout or combat feed. Declares the winner once an entire faction is eliminated, decided by General's `MatchVerdict.decide` (interface 11, the rule the dev command server's `match` verb decides by too), worded its own way (a lone survivor named in a match of any size). `main.gd` calls `begin` / `set_countdown` and listens to
  `match_ended`. Tested by `tests/ui/match_hud_verdict_test.gd`.

- `spectator_inspector.gd` — the **spectator inspector** (`SpectatorInspector` node), built by `main.gd`
  only in spectator mode via `setup(combatants, flags, right_clear)` (`flags` = the current overlay toggles; `right_clear` = the screen width from the right edge its outfit
  panel keeps clear, which Main hands it as the overlay toggle bar's `RESERVED_WIDTH`; `set_flag(flag, on)` updates one live from the toggle bar and re-applies it to the selected NPC).
  **Space** toggles `get_tree().paused`. A **left-click** on an NPC (nearest within `PICK_RADIUS` of the
  click's world point: the event's own position through the framing camera's view, never the viewport's mouse position, which
  in a window is the system cursor) selects it — revealing ONLY that NPC's *enabled* overlays
  (each toggle set from `flags`) and hiding every other NPC's; clicking it again or empty ground clears
  it. No NPC shows any overlay until clicked (the view stays focused on one NPC). With an NPC selected, a
  left-click on one of its tactical points (nearest zone within `ZONE_PICK_RADIUS`, from its
  `debug_zones()`) highlights that point (the controller's `debug_focus`, which its tactics overlay rings; `Vector2.INF` clears it) and fills a detail panel — top-left,
  below the match HUD's timer — with the zone's kind, label and Von's reasoning (`desc`). It runs `PROCESS_MODE_ALWAYS` so Space/clicks work while
  paused (freeze the match, then inspect). Decoupled like the other observers: reads the combatants'
  public `global_position` and `wardrobe.outfit.view()`, the camera, and each NPC's `debug_zones()`, and flips the debug-overlay
  toggles (every per-NPC flag of the overlay registry) through `OverlayRegistry.apply` (`domain-ui-overlays`), as Main does: a selection
  applies `flags` to the selected NPC and all-off to every other, `set_flag` re-applies `flags` to the selected one. Reads `Keybinds.PAUSE` (Space; shares it with
  `INTERACT`, unused in the player-less match). A mouse-ignoring detail label (with text shadow).
  While an NPC is selected, an outfit panel (22pt, shadowed, mouse-ignoring) lists `<name> — OUTFIT` and `OutfitLines.of(wardrobe.outfit.view())`, at the bottom
  right with its right edge `right_clear + OUTFIT_GAP` (10 px) from the screen edge, clear of the
  toggle bar's column, growing up and to the left; refreshed on select and every frame (`_refresh_outfit`), so plate wear shows live;
  hidden with no selection. Tested by `tests/ui/inspector_outfit_test.gd`.

- `outfit_lines.gd` — the **outfit lines** (a `RefCounted` with one static, preloaded by the debug panel and the inspector). `OutfitLines.of(view)` turns a
  character's `wardrobe.outfit.view()` into one line per slot in the view's order: a garment `Head: Helmet`, a plate `Front plate: Ceramic IV plate 68%`
  (`"%d%%" % roundi(condition * 100)`), `—` for nothing worn. It reads nothing but the view.

- `hud_probe.gd` — the **controller probe** (a `RefCounted` with one static, preloaded by the inspector).
  `controller_of(character)` returns the character's child in the group `npc_controllers` (the AI controller, which `npc.tscn` puts in it),
  or null for the player, a null or a freed character: the node `debug_zones()` and `known_contacts_for_display()` are read off.

- `contact_markers.gd` — the **contact markers** (`ContactMarkers` Node2D, world space, built by the inspector). When an NPC is
  selected it draws a coloured ring + name label at each character that NPC has in memory (visible ones bright, remembered ones
  faded), showing the NPC's own knowledge rather than the contacts' true state. The inspector pushes fresh contacts every frame
  (`set_contacts`, from the controller's `known_contacts_for_display()`), so the rings stay live and hold steady while Space-paused.

- `stack_markers.gd` — the **stack markers** (`StackMarkers` Node2D, world space, built by `main.gd` under `World` for a human match). Draws the
  slots of the doorway the human's `PlayerStack` has reserved a place at (`docs/tactical-entry.md` E16): a numbered ring on the floor for each
  slot where it stands (both sides of the door on a split stack, E19; numbered in the order they were claimed), the human's own bright and filled, the ones an AI holds dimmer, a free one faint. And every
  stack of the human's side, ordered or its own (`docs/leadership.md` LD18), from the squad's view: `watch_squad(view: Callable)` (Main hands
  it `squad.view`), whose `stacks` (`[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]`, interface 21) it
  draws ring by ring: dim while its holder is on the way (`held`, not `there`), filled once there (`ALPHA_THERE_FILL` 0.3), the human's own
  bright, a free one faint, second files and both sides alike, until the stack leaves the view (everyone through). A slot both views give is
  drawn once (`_rings`: the squad's ring, flagged `mine` when it is the human's reserved slot at that doorway); the `PlayerStack`'s own slots are
  drawn only where the squad's view has no stack. Nothing with neither. A decoupled observer:
  `watch(stack)` / `watch_squad(view)`, then it polls both each frame and redraws on change; it draws at `DrawLayers.ABOVE` (interface 11), over the standing world, so a
  character on a slot never hides its ring; `drawn()` is what is shown, rows `{ n, point, mine, held, there, side, row, opening }` (what the test reads,
  `tests/ui/stack_markers_draw_test.gd`).

- `stun_screen.gd` — the **stun screen** (`StunScreen` CanvasLayer, layer 90, built by `main.gd` under `World` for a human match; G14 of
  `docs/grenades.md`). `watch(character)`, then it reads the character's `stun.view()` each frame (`blind`, `blind_total`): the screen is
  **white** by `blind / blind_total` (1 at the burst, falling steadily to 0 as the blindness ends), over a **frozen afterimage** of the frame on screen
  when the flash landed (`get_viewport().get_texture().get_image()`, taken on the character's `&"stun"` event with `blind` > 0 and held solid until the
  white is half gone, then faded out to the live view; none on a headless display, where `afterimage` is still true). A new flash while still white
  (≥ 0.2) keeps the old frame. A deaf-only stun, another character's flash and a dead/freed character draw nothing. `drawn()` is `{ white, afterimage,
  remaining }` (what the test reads, `tests/ui/stun_screen_whiteout_test.gd`). A decoupled observer; the white is drawn on an inner full-rect `Control` (mouse-ignoring).

**Interfaces:** 6 (`LoadoutConfig.grenade_options`, the debug panel's grenades line), 7 (observers of the Character API, the debug panel's hits from its `hit_landed` signal, and of the AI controller), 10 (EventBus `&"stun"`), 11 (`DrawLayers.ABOVE` for the stack markers, `MatchVerdict` for the match HUD), 17 (stack markers), 18 (stun screen), 21 (the stack markers' `watch_squad`), 22 (the match HUD and the spectator inspector Main wires) — signatures in `architecture`.
