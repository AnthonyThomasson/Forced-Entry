# UI command (`scenes/ui/command/`)

The human leader's orders and their markers (`docs/leadership.md` LD11, LD12, D5), built by Main (`_build_command_menu`) under `World` only
when the human leads ("Lead the team", `menus.md`). Each file reads the Character API (`global_position`, `name`, `is_dead`,
`inventory.item_count` with `ItemRegistry.STUN_SLOT` / `FRAG_SLOT`), the squad's `view()` and, for the menu, `resolve()` (interface 21), and
`Keybinds.COMMAND` / `MENU`. It emits plain requests and holds no AI reference or AI id. Interfaces: 6, 7, 11, 21, 22.

Tests: `tests/ui/command_menu_items_test.gd`, `command_menu_docks_right_test.gd` / `_left_test.gd`, `command_menu_clear_of_overlay_bar_test.gd` /
`_centre_test.gd` / `_crowded_test.gd`, `command_menu_label_matches_order_test.gd`, `order_markers_draw_test.gd`; the Main wiring is
`tests/general/command_menu_wiring_test.gd`. They share `tests/_ai/order_menu_probe.gd` (`OrderMenu`: a menu on a player's screen,
`check_dock`, `check_clear_of_bar`).

## `command_menu.gd` — `CommandMenu` (CanvasLayer 40, `PROCESS_MODE_ALWAYS`)

- `setup({ rooms, teammates, view, resolve, leader, right_clear })`: it opens only while the view names `leader` the leader. Main passes the overlay bar's
  `RESERVED_WIDTH` as `right_clear` when Debug is on. The widgets live in `command_panel.gd` (`CommandPanel`, a `PanelContainer` child named `Panel`, preloaded;
  it holds the "Hold for my go" value and the dock and holds no reference back to the menu).
- **Opening.** `Keybinds.COMMAND` (read in `_unhandled_input`, so a click the toggle bar or the panel takes never opens it) or `open_at(world)` pauses
  the whole tree (it unpauses on close only if it paused it, and in `_exit_tree` if freed open). Escape (`Keybinds.MENU`) closes it in `_input` and marks
  the event handled, so Main's "back to setup" never sees it. `selection_changed(nodes)` carries the selection while open and `[]` on close (Main wires it to
  the order markers).
- **What a click means**, hit-tested in this order (`PICK_RADIUS` for a body):
  1. a living teammate: "Select / Deselect <name>" (the menu stays open); "Go into the <room>" while that teammate holds a held stack with no go yet (LD13);
  2. a doorway (the one `resolve({ kind: "stack", pos })` picks; no `resolve`, no doorway): "Go into the <room>" for a held stack there, whoever is selected; for a
     held join of the human's rally (mode `join`, D38) one go item per mode (quiet / stun / frag); then "Stack into the <room> (quiet | with stun | with frag)", where
     `<room>` is the room the squad resolves the stack *into*, so the label names the room of the order (`command_menu_label_matches_order_test.gd`); then
     "Ambush the doorway from the <room>", `<room>` from `resolve({ kind: "ambush", pos })`'s `room`, the click's side of the wall (LD15, D17);
  3. a room whose rect holds the click: "Defend the <room>";
  4. "Cancel order" while any recipient holds an order in the view.
- **Greying.** A stun item is disabled while no recipient's `inventory.item_count(STUN_SLOT)` is above 0 (D1), a frag item likewise on `FRAG_SLOT` (D15). For a
  held rally the recipients are the living teammates holding that join. The tooltip says why ("Nobody it would go to carries a stun grenade.").
- **Recipients:** the selection, else every living teammate (never the human). The selection is the ticked boxes plus a left-click on a body while open; it
  lasts across closes and drops a dead teammate on the next open. "Hold for my go" (off at first, kept across closes while the match runs, D19) makes a chosen
  stack wait for the leader's go.
- **Requests** (`order_requested`): `{ kind: "stack", to, pos, bang, mode, wait_go }` (`pos` is the raw click; the squad resolves side and room; `bang` is
  mode != quiet), `{ kind: "go", pos, mode? }` (no `to`: the squad sends it to whoever holds the held stack, LD13; `mode` only for a held rally, D38),
  `{ kind: "ambush", to, pos }`, `{ kind: "defend_room", to, room }`, `{ kind: "cancel", to }`. Choosing an item emits and closes. Item buttons use `FOCUS_NONE`, so
  Space stays INTERACT. `items()` reads out `[{ label, disabled, why }]` (empty while closed).
- **Docking.** The panel docks on the side away from the click (left, or right when the click is in the left half; the right dock sits `right_clear` further
  in, clear of the overlay bar) and re-docks on every `open_at` and selection change. Its job: never cover the clicked point or a selected body. The right dock
  tries three vertical docks in order and takes the first that keeps `POINT_CLEAR` from the click and the selected bodies, else the first that clears the
  click; a body is covered only in that crowded case (LD11). Constants live in `command_panel.gd`.

## `order_markers.gd` — `OrderMarkers` (Node2D, an overlay: `ViewLayers.overlay`, `DrawLayers.OVERLAY` absolute over the player's view, `PROCESS_MODE_ALWAYS` so the selection shows while the menu pauses the tree)

`watch(view)` polls the squad's `view()` each frame; `set_selection(nodes)` is the menu's selection. For each living member with an order it draws a dashed line to
`order.pos` (the doorway's centre for a stack, the room's for a defend), ringed and labelled once per target (`_label_of`: "Stack (<mode>)", ", hold" while it waits
for the go, LD13; "Join stack" for a join, LD24; "Ambush"; "Defend"; plus the member's progress word; red when the member `refused`; a `done` order is not drawn),
and a green ring round each selected teammate. `drawn()` (the test's read-out) is `[{ kind: "order"|"selected", point, node, from?, label?, refused? }]`, redrawn only on change.
Who leads is not drawn here: the crown is the squad-leaders overlay (`overlays.md`).
