---
name: domain-ui-command
description: Deep implementation detail for the UI command sub-domain (scenes/ui/command/) — how the human leader orders its teammates and sees those orders (docs/leadership.md LD11, LD12, D5): the command menu (CommandMenu, command_menu.gd: right-click orders on Keybinds.COMMAND, pausing the tree, hit-testing a teammate, a doorway or a room, the stack items quiet / with stun / with frag greyed when nobody carries the grenade, "Go into the <room>", the held stack's go, a held rally's go quiet / with stun / with frag (D31), the ambush and defend items, "Cancel order", the selection, the docked panel kept clear of the overlay bar), its widget panel (CommandPanel, command_panel.gd: the "Hold for my go" checkbox, the teammate boxes, the dock) and the order markers (OrderMarkers, order_markers.gd: a dashed line and label per member's order target, the selection rings). Use when editing scenes/ui/command/ or working on the command menu, right-click orders, held stack go, "Hold for my go" or the order markers. Plain requests out, the squad's view() / resolve() callables in. Complements the `domain-ui` overview and the `architecture` skill.
---

# UI · command sub-domain (`scenes/ui/command/`)

The human leader's orders (`docs/leadership.md` LD11, LD12, D5), built by `main.gd` (`_build_command_menu`) only when the human leads
("Lead the team"). Each file reads only the Character public API (`global_position`, `name`, `is_dead`, `inventory.item_count` with Items'
`ItemRegistry.STUN_SLOT` / `FRAG_SLOT`), the squad's `view()` callable and, for the menu, its `resolve()`, and `Keybinds.COMMAND` /
`MENU`; it emits plain requests, holds no AI reference and computes no AI id. See `domain-ui` for what all UI scripts share.

- `command_menu.gd` — the **command menu** (`CommandMenu` CanvasLayer, layer 40, `PROCESS_MODE_ALWAYS`; `docs/leadership.md` LD11, interface 21),
  built by `main.gd` under `World` only when the human leads ("Lead the team"). `setup({ rooms, teammates, view, resolve, leader, right_clear })` (the house's
  rooms as plain dicts, the characters it may order, the squad's `view()` and `resolve(request)` callables, the human: it opens only while the
  view names it the leader; `right_clear` the screen width from the right edge a panel docked on the right keeps clear, default 0: Main hands it
  the overlay toggle bar's `RESERVED_WIDTH` with Debug on, as the inspector's, kept as the panel's `right_clear`; the panel and the teammates' boxes are built here, hidden: the panel is `command_panel.gd`, a `PanelContainer` child named `Panel`, reached by the preload const `CommandPanel`, which holds the widgets, the hold box's value and the dock, and holds no reference back to the menu). `Keybinds.COMMAND` (right mouse, read in `_unhandled_input`, so a
  click the toggle bar or the panel takes never opens it) or `open_at(world)` pauses the whole tree (unpaused on close only if it paused it, and
  in `_exit_tree` if freed open) and fills the panel for what is under the point, hit-tested in this order: a living teammate within `PICK_RADIUS`
  (28 px) — "Select <name>" / "Deselect <name>", the menu staying open, then "Go into the <room>" while that teammate holds a held stack in the
  view that has had no go (`_held_order_of`: its view row's `held`, LD13), its go at that order's doorway (`_go_items`, below); a doorway, the one the
  squad resolves a stack at the click to (`resolve({ kind: "stack", pos })`: the nearest within its width; no `resolve`, no doorway) — first
  "Go into the <room>" while any member of the view holds a held stack there that has had no go, whoever is selected (`_held_at`: the held row's
  order, D13; for a held join of the human's rally, mode `join` (its `JOIN`), `_go_items` offers one item per mode of its `MODES` (interface 21's request modes, written in the menu: it holds no AI script), "Go into the <room> (quiet)", "Go into the <room> with stun" and
  "Go into the <room> with frag", in its place, D31: stun / frag greyed while none of the living teammates the view shows holding that join, `_holders`,
  carries the grenade the mode names (`GRENADE_SLOTS`: its `ItemRegistry` slot), tooltip "Nobody holding it carries a stun grenade." / "... a frag grenade."; the menu reads the view's member rows through one `_rows()`), then
  "Stack into the <room> (quiet)", "Stack into the <room> with stun" and "Stack into the <room> with frag", `<room>` the type of the room it
  resolves the stack into (`into`), so the label names the room of the order (`tests/ui/command_menu_label_matches_order_test.gd`), the stun item
  disabled while no recipient's `inventory.item_count(ItemRegistry.STUN_SLOT)` is above 0 (D1) and the frag item while none's `FRAG_SLOT` is (D15)
  (`_recipients_carry(slot)`; a disabled button's tooltip says why: "Nobody it would go to carries a stun grenade." / "... a frag grenade."),
  then "Ambush the doorway from the <room>", `<room>` the one the squad resolves the ambush to (`resolve({ kind: "ambush", pos })`'s `room`, the
  click's side of the wall, `_ambush_from`; LD15, D17); a room whose rect holds it — "Defend the <room>"; then "Cancel order" while a recipient
  holds an order in the view. Below the items a "Hold for my go" `CheckBox` (off at first, kept across closes while the match runs, D19:
  `CommandPanel.hold_go`) makes a stack chosen wait for the leader's go. Recipients: the selection, else every living teammate (never the human); the
  selection is the ticked boxes (`CheckBox` per teammate, text its name, `toggled`) plus a left-click on a body while open, lasts across
  closes, and drops a dead teammate (its box disabled) on the next open. Choosing an item (a `Button`, `pressed`, `FOCUS_NONE` so Space stays
  INTERACT; each item is `_item(label, disabled, act, why)`) emits `order_requested` — `{ kind: "stack", to, pos, bang, mode, wait_go }` (`pos`
  the raw click: the squad resolves the doorway's side and room; `mode` quiet / stun / frag, `bang` mode != quiet, `wait_go` the checkbox),
  `{ kind: "go", pos, mode? }` (`_go(at, mode)`; no `to`: the squad sends it to whoever holds the held stack there, LD13; `mode` quiet / stun / frag
  for a held rally's go, D31), `{ kind: "ambush", to, pos }`,
  `{ kind: "defend_room", to, room }`, `{ kind: "cancel", to }` (the recipients holding an order) — and closes it. Escape (`Keybinds.MENU`)
  closes it in `_input` and is set handled, so Main's "back to setup" never sees it. `selection_changed(nodes)` carries the selection while open
  and [] on close (Main connects it to the order markers). Layout: a panel docked on the side away from the click (the panel's `dock`, handed the click's and the selected bodies' screen points at the end of every `_refresh`, so on each `open_at` and each selection
  change while open: the left, or the right when the click's screen point lies in the left half; anchored `PANEL_EDGE` 24 in from that edge
  (the right one `right_clear` further in, clear of the overlay bar's fixed column) and growing away from it, `PANEL_TOP` 120, at least
  `PANEL_WIDTH` 440). Docked on the right it weighs three vertical docks, rects worked out from the panel's combined minimum size: hanging from
  `PANEL_TOP`, then the side away from the centre of the click and the selected living bodies (screen points, through the canvas transform),
  then the other — hanging from `PANEL_EDGE` below the top (over the paused match timer) or standing `PANEL_EDGE` above the bottom (growing
  up). It takes the first that keeps `POINT_CLEAR` (24 px) from all those points, else the first that keeps clear of the click, else the side
  away: a body is covered only in that crowded case (LD11; the panel is about 520 x 524 on the 1152 x 648 window, so a vertical dock leaves a
  band of about 100 px at the top or bottom free); title 28pt naming the target, a "Orders go to:" line 22pt, the items 26pt, the "Hold for my go" box 22pt, a "Teammates" list 22pt, a hint 18pt), so it
  never covers the bodies and doorway it is about, and a ring on the clicked point (a full-rect, mouse-ignoring `Control`). `items()` is
  `[{ label, disabled, why }]` (`why` the tooltip a greyed item shows, "" for one never greyed; empty while closed), `is_open()`, `close()`. It holds no AI reference and computes no AI id. Tested by
  `tests/ui/command_menu_items_test.gd` (plain dicts, a fake view and a real squad's `resolve`: the items, the frag item greyed, Go on a held
  doorway and teammate, a held rally's three go items and their `mode`, the ambush item, the checkbox; on the project's window size, `OrderMenu.player_screen`),
  `tests/ui/command_menu_docks_right_test.gd` / `_left_test.gd` (a click in the left half docks it right, one in the right half
  left: its rect covers neither the click nor a selected teammate, `OrderMenu.check_dock`), `tests/ui/command_menu_clear_of_overlay_bar_test.gd`
  / `_centre_test.gd` / `_crowded_test.gd` (Debug on, a real `OverlayToggles`: docked right `right_clear` + 24 in, beside the click and bodies,
  above or below them, or away from them when crowded; never over the bar or the click, `OrderMenu.check_clear_of_bar`), `tests/ui/command_menu_label_matches_order_test.gd`
  (a real squad: the stack item names the room of the order posted) and, wired by Main, `tests/general/command_menu_wiring_test.gd`.

- `order_markers.gd` — the **order markers** (`OrderMarkers` Node2D, world space, z at `DrawLayers.ABOVE`, `PROCESS_MODE_ALWAYS` so the
  selection shows while the menu holds the tree paused; LD12, D5), built by `main.gd`
  under `World` with the command menu, only when the human leads. `watch(view)` takes the squad's `view()` callable, polled each frame;
  `set_selection(nodes)` is the menu's selection. It draws, for each living
  member with an order a dashed line to the order's target (`order.pos`: the doorway's centre for a stack, the room's for a defend), ringed
  and labelled once per target (`_label_of`: "Stack (<mode>)" with the order's mode, quiet / stun / frag, and ", hold" while it waits for the
  leader's go (the view row's `held`), LD13: "Stack (frag, hold) · in position"; a join, the leader's own stack rallying the member (mode
  `join`, LD24): "Join stack · moving"; "Ambush · moving" (LD15); "Defend · in position"; red when the member `refused`; a
  `done` order is not drawn), and a green ring round each selected teammate. `drawn()` (what the test reads) is `[{ kind, point, node, from?, label?, refused? }]`
  (`kind` `order` (`point` the target, `node` the member, `from` where it stands, `label` the words at the target) / `selected`), redrawn
  only when it changes. Who leads is not drawn here: the crown over each squad's leader is the
  overlays sub-domain's `leader_overlay.gd` (`domain-ui-overlays`), a debug overlay. Tested by `tests/ui/order_markers_draw_test.gd`.

**Interfaces:** 6 (`ItemRegistry.STUN_SLOT` / `FRAG_SLOT`, the grenade counts the menu greys its items by), 7 (observers of the Character API; `Keybinds.COMMAND` and `MENU`), 11 (`DrawLayers.ABOVE` for the order markers), 21 (the command menu and the order markers, over the squad's `view()` and `resolve()`), 22 (the overlay bar's `OverlayToggles.RESERVED_WIDTH` Main hands the menu as `right_clear`) — signatures in `architecture`.
