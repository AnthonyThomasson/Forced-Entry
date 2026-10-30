extends CanvasLayer
## UI domain: the command menu (`docs/leadership.md` LD11), how the human leader orders its
## teammates. Main builds it only when the human leads its side ("Lead the team" in the setup
## window). A right-click (`Keybinds.COMMAND`) pauses the whole tree and opens the menu on what is
## under the cursor:
## - a teammate within `PICK_RADIUS`: "Select <name>" / "Deselect <name>" (the menu stays open), and
##   "Go into the <room>" while it holds a held stack that has had no go (LD13: the stack's point
##   stands right by its doorway); for a held join of the human's rally (D31) the three go items
##   below in its place;
## - else a doorway the squad resolves a stack at the click to (its `resolve` callable: the doorway
##   nearest the click within its width): "Stack into the <room> (quiet)", "Stack into the <room>
##   with stun" and "Stack into the <room> with frag", `<room>` the room that stack goes into (the
##   squad's `into`, named from the plain room dicts it was set up with), so the label names the
##   room of the order; the stun item is greyed while no recipient carries a stun
## (`Character.inventory.item_count(ItemRegistry.STUN_SLOT)`, D1), the frag item while none carries
## a frag
##   (`FRAG_SLOT`, D15); the panel's "Hold for my go" checkbox (off at first, kept while the match
##   runs, D19) makes the stack chosen wait for the leader's go (LD13); "Go into the <room>" while a
##   member of the squad's view holds a held stack there that has had no go, whoever is selected
##   (D13), or, for a held join of the human's rally there (D31), "Go into the <room> (quiet)",
##   "... with stun" and "... with frag", stun and frag greyed while no member holding the join
##   carries one; and "Ambush the doorway from the <room>", `<room>` the one on the click's side
##   of its wall, as the squad resolves the ambush (LD15, D17);
## - else a room: "Defend the <room>";
## - and "Cancel order" while a recipient holds an order (the squad's `view()`).
## The panel also lists the teammates to tick. The recipients are the selection (ticked, or picked
## by a left-click on a teammate's body while the menu is open), or every living teammate when
## nothing is selected; never the human. The selection lasts until it is changed, and a dead
## teammate leaves it. Choosing an order emits `order_requested` and closes the menu; Escape closes
## it too (consumed in `_input`, so Main's MENU never sees it); closing unpauses the tree. Space
## stays the player's INTERACT.
##
## The panel (`command_panel.gd`, a child named `Panel`) docks on the side of the screen away from
## the click it is open on: on the left, or on the right when the click lies in the left half, so it
## never covers the teammate or doorway it is about; a ring marks the clicked point. Docked on the
## right it keeps clear of `right_clear` (the overlay toggle bar's column when Debug is on), and
## where it would cover the click or a selected teammate there it docks at the top or the bottom of
## the screen instead, away from them; it is docked again whenever the selection changes while it is
## open. A decoupled observer: it reads its teammates through the Character API only
## (`global_position`, `name`, `is_dead`, `item_count`) and the squad through its `view()` and
## `resolve()` callables, emits plain requests and works out no AI id: the squad (interface 21)
## resolves the click into its doorway, side and room. `PROCESS_MODE_ALWAYS`, so it works while the
## tree is paused.

## Emitted when an order is chosen: `{ kind: "stack", to, pos, bang, mode, wait_go }` (`pos` the
## click itself, `mode` quiet / stun / frag, `bang` mode != quiet as part 1 had it, `wait_go` the
## "Hold for my go" box), `{ kind: "go", pos, mode? }` (the held stack at that doorway goes, LD13;
## `mode` quiet / stun / frag for a held rally, D31),
## `{ kind: "ambush", to, pos }` (LD15), `{ kind: "defend_room", to, room }` (a room key) or
## `{ kind: "cancel", to }` (the recipients holding an order). `to` is the recipients (characters).
## Main hands it to the squad's `issue`.
signal order_requested(request: Dictionary)
## Emitted when the highlighted selection changes: the selected teammates while the menu is open, []
## once it closes (the order markers' `set_selection`).
signal selection_changed(nodes: Array)

const CommandPanel := preload("res://scenes/ui/command/command_panel.gd")
## The squad (interface 21), for the vocabulary of its requests alone: `MODES`, a stack's or a go's
## mode, and `JOIN`, the mode of its rally.
const Squad := preload("res://scenes/ai/team/squad.gd")
## World-space radius (px) around the cursor within which a click picks a teammate's body.
const PICK_RADIUS := 28.0
## The ring on the clicked point: its radius (screen px) and colour.
const MARK_RADIUS := 14.0
const MARK_COLOR := Color(1.0, 0.85, 0.3, 0.95)

## The house's rooms (`WorldGen.get_rooms`: `{ key, type, rect }`).
var _rooms: Array = []
## The characters the human may order (its squad without itself), in squad order.
var _teammates: Array = []
## The squad's `view()`: `{ leader, members: [{ node, order, step }] }`.
var _view: Callable
## The squad's `resolve(request)`: what a stack at a click names (`{ opening, pos, into, ... }`, or
## {}).
var _resolve: Callable
## The human: the menu opens only while the view names it the leader (null: no such check).
var _leader: Node = null
## The selected teammates.
var _selection: Array = []
## Whether the menu is open.
var _open := false
## Whether opening the menu paused the tree (closing then unpauses it).
var _paused_tree := false
## The world point the menu is open on.
var _click := Vector2.ZERO
## What is offered now: `{ label, disabled, act: Callable, why }`.
var _items: Array = []
## The panel, docked away from the click (its `dock`), with the items, "Hold for my go" and the
## teammates' boxes.
var _panel: CommandPanel
## Full-screen, mouse-ignoring: draws the ring on the clicked point.
var _mark: Control


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40


func _exit_tree() -> void:
	if _open and _paused_tree:
		# A menu freed while open (the match torn down) never leaves the game paused.
		get_tree().paused = false


## Escape closes the open menu; consumed here, before Main's `_unhandled_input` would read it as
## MENU.
func _input(event: InputEvent) -> void:
	if _open and event.is_action_pressed(Keybinds.MENU) and not event.is_echo():
		close()
		get_viewport().set_input_as_handled()


## COMMAND (a right-click by default) opens the menu on the point under the cursor; while it is
## open, a left-click on a teammate's body toggles it in the selection. Clicks on the panel never
## get here (it takes them first).
func _unhandled_input(event: InputEvent) -> void:
	var screen: Vector2 = (event.position
			if event is InputEventMouse
			else get_viewport().get_mouse_position())
	if event.is_action_pressed(Keybinds.COMMAND) and not event.is_echo():
		if _may_open():
			open_at(_world_of(screen))
			get_viewport().set_input_as_handled()
	elif (_open
			and event is InputEventMouseButton
			and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT):
		var mate := _teammate_at(_world_of(screen))
		if mate != null:
			_toggle(mate, not _selection.has(mate))
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open:
		# The camera may still zoom while paused: keep the ring on the clicked point.
		_mark.queue_redraw()


## Set the menu up: `{ rooms, teammates, view, resolve, leader?, right_clear? }`, `rooms` the
## house's (plain dicts), `teammates` the characters it may order, `view` and `resolve` the squad's
## `view()` and `resolve(request)` callables (with no `resolve` no doorway is offered), `leader` the
## human (the menu then opens only while it leads) and `right_clear` the screen width (px) from the
## right edge a panel docked on the right keeps clear (default 0). Called by Main once the squads
## are built.
func setup(config: Dictionary) -> void:
	_rooms = config.get("rooms", [])
	_teammates = (config.get("teammates", []) as Array).filter(func(n): return n is Node)
	var view = config.get("view")
	_view = view if view is Callable else Callable()
	var resolve = config.get("resolve")
	_resolve = resolve if resolve is Callable else Callable()
	_leader = config.get("leader") as Node
	_build()
	_panel.right_clear = maxf(float(config.get("right_clear", 0.0)), 0.0)


## Pause the tree and open the menu on world point `at`: the items for what lies there.
func open_at(at: Vector2) -> void:
	if not _may_open():
		return
	_click = at
	if not _open:
		_open = true
		_paused_tree = not get_tree().paused
		get_tree().paused = true
		_panel.visible = true
	_drop_dead()
	_refresh()
	selection_changed.emit(_selection.duplicate())


## Close the menu (no order) and unpause the tree if opening it paused it.
func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	_set_items([])
	_mark.queue_redraw()
	if _paused_tree and is_inside_tree():
		get_tree().paused = false
	_paused_tree = false
	selection_changed.emit([])


## Whether the menu is open.
func is_open() -> bool:
	return _open


## What the menu offers now, `[{ label, disabled, why }]` in display order (`why` what greys the
## item, its tooltip while it is greyed; "" for one never greyed); [] while it is closed.
func items() -> Array:
	return _items.map(
		func(i): return { "label": i["label"], "disabled": i["disabled"], "why": i["why"] },
	)


# --- What lies under the click --------------------------------------------------------------------


## Rebuild the panel for the point the menu is open on: its title, the recipients line and the
## items.
func _refresh() -> void:
	var mate := _teammate_at(_click)
	var door := {} if mate != null else _stack_at(_click)
	var shown: Dictionary
	if mate != null:
		shown = _teammate_items(mate)
	elif not door.is_empty():
		shown = _doorway_items(door)
	else:
		shown = _room_items()
	var offered: Array = shown["items"]
	if not _ordered_recipients().is_empty():
		offered.append(_item("Cancel order", false, _cancel))
	_panel.set_heading(shown["title"], ("Orders go to: %s"
			% (", ".join(_selection.map(func(n): return String(n.name)))
					if not _selection.is_empty()
					else "the whole squad")))
	_set_items(offered)
	_panel.dock(_dock_points())
	_mark.queue_redraw()


## The title and items (`{ title, items }`) for a click on teammate `mate`: select or deselect it,
## and go into the room of the held stack it holds.
func _teammate_items(mate: Node) -> Dictionary:
	var picked := _selection.has(mate)
	var offered: Array = [
		_item(
			"%s %s" % ["Deselect" if picked else "Select", mate.name],
			false,
			_toggle.bind(mate, not picked),
		),
	]
	var held := _held_order_of(mate)
	if not held.is_empty():
		offered.append_array(_go_items(held, held["pos"]))
	return { "title": String(mate.name), "items": offered }


## The title and items (`{ title, items }`) for a click on the doorway `door` (`_stack_at`): go
## while a held stack waits there, the three stacks (stun and frag greyed while no recipient carries
## one) and the ambush.
func _doorway_items(door: Dictionary) -> Dictionary:
	var into := _room_name(_room_by_key(String(door.get("into", ""))))
	var offered: Array = []
	var held := _held_at(String(door.get("opening", "")))
	if not held.is_empty():
		offered.append_array(_go_items(held, _click))
	offered.append(_item("Stack into the %s (quiet)" % into, false, _stack.bind("quiet")))
	offered.append(_item(
		"Stack into the %s with stun" % into, not _recipients_carry(ItemRegistry.STUN_SLOT),
		_stack.bind("stun"), "Nobody it would go to carries a stun grenade.",
	))
	offered.append(_item(
		"Stack into the %s with frag" % into, not _recipients_carry(ItemRegistry.FRAG_SLOT),
		_stack.bind("frag"), "Nobody it would go to carries a frag grenade.",
	))
	var from := _ambush_from(_click)
	if from != "":
		offered.append(_item(
			"Ambush the doorway from the %s" % _room_name(_room_by_key(from)), false,
			_order.bind({ "kind": "ambush", "pos": _click }),
		))
	return { "title": "Doorway into the %s" % into, "items": offered }


## The title and items (`{ title, items }`) for a click on a room (defend it) or outside every
## room (none).
func _room_items() -> Dictionary:
	var room := _room_at(_click)
	var title := "The %s" % _room_name(room) if not room.is_empty() else "Outside"
	if room.is_empty():
		return { "title": title, "items": [] }
	return {
		"title": title,
		"items": [
			_item(
				"Defend the %s" % _room_name(room),
				false,
				_order.bind({ "kind": "defend_room", "room": String(room["key"]) }),
			),
		],
	}


## The living teammate nearest world point `at` within `PICK_RADIUS`, or null.
func _teammate_at(at: Vector2) -> Node:
	var best: Node = null
	var best_d := PICK_RADIUS
	for mate in _teammates:
		if not _alive(mate):
			continue
		var d: float = (mate.global_position as Vector2).distance_to(at)
		if d <= best_d:
			best_d = d
			best = mate
	return best


## What a stack ordered at world point `at` names, as the squad resolves it
## (`{ opening, pos, into, ... }`), or {} for no doorway there.
func _stack_at(at: Vector2) -> Dictionary:
	var out = _resolve.call({ "kind": "stack", "pos": at }) if _resolve.is_valid() else {}
	return out if out is Dictionary else {}


## The room an ambush ordered at world point `at` is laid from (the squad's `resolve`: the click's
## side of the doorway's wall), or "".
func _ambush_from(at: Vector2) -> String:
	var out = _resolve.call({ "kind": "ambush", "pos": at }) if _resolve.is_valid() else {}
	return String((out as Dictionary).get("room", "")) if out is Dictionary else ""


## The stack order a member of the squad's view holds at doorway `opening` that waits for the
## leader's go and has not had it (its row's `held`, LD13), or {}.
func _held_at(opening: String) -> Dictionary:
	for row: Dictionary in _rows():
		if bool(row.get("held", false)) and String(row["order"].get("opening", "")) == opening:
			return row["order"]
	return {}


## The go items for the held stack order `held` (`_held_at`, `_held_order_of`), each going to the
## doorway at `at`: "Go into the <room>" for a stack the leader ordered (LD13); for its rally (a
## join, mode `join`, D31) one per mode, "Go into the <room> (quiet)", "... with stun" and "... with
## frag", stun and frag greyed while no member holding that join carries one (D1, D15).
func _go_items(held: Dictionary, at: Vector2) -> Array:
	var into := _room_name(_room_by_key(String(held.get("into", ""))))
	if String(held.get("mode", "")) != Squad.JOIN:
		return [_item("Go into the %s" % into, false, _go.bind(at))]
	var holders := _holders(String(held.get("id", "")))
	var out: Array = []
	for mode: String in Squad.MODES:
		var slot := _grenade_slot(mode)
		if slot == -1:
			out.append(_item("Go into the %s (%s)" % [into, mode], false, _go.bind(at, mode)))
			continue
		out.append(_item(
			"Go into the %s with %s" % [into, mode], not _any_carries(holders, slot),
			_go.bind(at, mode), "Nobody holding it carries a %s grenade." % mode,
		))
	return out


## The slot of the grenade mode `mode` (one of `Squad.MODES`) throws in first: the grenade slot
## whose kind it names (`GrenadeConfig.kind_in_slot`), -1 for quiet.
static func _grenade_slot(mode: String) -> int:
	for slot: int in [ItemRegistry.STUN_SLOT, ItemRegistry.FRAG_SLOT]:
		if GrenadeConfig.kind_in_slot(slot) == StringName(mode):
			return slot
	return -1


## The living teammates the squad's view shows holding order `id`.
func _holders(id: String) -> Array:
	var out: Array = []
	for row: Dictionary in _rows():
		if String(row.get("order", {}).get("id", "")) == id and _alive(row.get("node")):
			out.append(row["node"])
	return out


## The held stack order `mate` holds in the squad's view (its row's `held`) with its doorway's
## centre (`pos`), or {}.
func _held_order_of(mate: Node) -> Dictionary:
	for row: Dictionary in _rows():
		if (row.get("node") == mate
				and bool(row.get("held", false))
				and row["order"].get("pos") is Vector2):
			return row["order"]
	return {}


## The room whose rect holds world point `at`, or {}.
func _room_at(at: Vector2) -> Dictionary:
	for r: Dictionary in _rooms:
		if (r["rect"] as Rect2).has_point(at):
			return r
	return {}


## Room `key`'s dict, or {}.
func _room_by_key(key: String) -> Dictionary:
	for r: Dictionary in _rooms:
		if String(r["key"]) == key:
			return r
	return {}


## A room as the menu names it: its type, words apart ("living_room" -> "living room").
func _room_name(room: Dictionary) -> String:
	return (String(room.get("type", room.get("key", "room"))).replace("_", " ")
			if not room.is_empty()
			else "room")


# --- Recipients and orders ------------------------------------------------------------------------


## Who an order goes to: the selection, or every living teammate when nothing is selected.
func _recipients_now() -> Array:
	return _selection.duplicate() if not _selection.is_empty() else _teammates.filter(_alive)


## Whether any recipient carries a grenade of inventory slot `slot` (D1, D15: a stun or frag stack
## is offered only then).
func _recipients_carry(slot: int) -> bool:
	return _any_carries(_recipients_now(), slot)


## Whether any of `nodes` carries a grenade of inventory slot `slot`.
static func _any_carries(nodes: Array, slot: int) -> bool:
	return nodes.any(func(n): return "inventory" in n and int(n.inventory.item_count(slot)) > 0)


## The member rows of the squad's `view()` (`{ node, order, held, ... }`), [] with no view.
func _rows() -> Array:
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	return view.get("members", [])


## The recipients that hold an order now (the squad's `view()`).
func _ordered_recipients() -> Array:
	var held: Array = []
	for row: Dictionary in _rows():
		if not (row.get("order", {}) as Dictionary).is_empty():
			held.append(row.get("node"))
	return _recipients_now().filter(func(n): return held.has(n))


## Emit `request` for the recipients now and close the menu.
func _order(request: Dictionary) -> void:
	var out := request.duplicate()
	out["to"] = _recipients_now()
	close()
	order_requested.emit(out)


## Order a stack at the click in `mode` (quiet / stun / frag), held for the leader's go while "Hold
## for my go" is ticked.
func _stack(mode: String) -> void:
	_order({
		"kind": "stack",
		"pos": _click,
		"bang": mode != "quiet",
		"mode": mode,
		"wait_go": _panel.hold_go,
	})


## The leader's go for the held stack at the doorway at `at` (the squad sends it to whoever holds it
## there), in `mode` for a rally's (D31; "" for an ordered stack's), and close the menu.
func _go(at: Vector2, mode := "") -> void:
	var request := { "kind": "go", "pos": at }
	if mode != "":
		request["mode"] = mode
	close()
	order_requested.emit(request)


## Cancel the recipients' orders and close the menu.
func _cancel() -> void:
	var to := _ordered_recipients()
	close()
	order_requested.emit({ "kind": "cancel", "to": to })


## Put `mate` in the selection (`on`) or take it out, tick its box to match, and redraw an open
## menu.
func _toggle(mate: Node, on: bool) -> void:
	if on and _alive(mate) and not _selection.has(mate):
		_selection.append(mate)
	elif not on:
		_selection.erase(mate)
	_panel.tick(mate, _selection.has(mate))
	if _open:
		_refresh()
		selection_changed.emit(_selection.duplicate())


## A dead teammate leaves the selection and its box is disabled.
func _drop_dead() -> void:
	for mate in _teammates:
		if not _alive(mate):
			_selection.erase(mate)
			if is_instance_valid(mate):
				_panel.disable(mate)


## Whether `n` is a living character (any value: a teammate may have been freed).
func _alive(n: Variant) -> bool:
	return n is Node and is_instance_valid(n) and n.get("is_dead") != true


## Whether the menu may open: it was set up and, when it was given the human, the squad's view still
## names the human its leader.
func _may_open() -> bool:
	if _panel == null:
		return false
	if _leader == null:
		return true
	var view: Dictionary = _view.call() if _view.is_valid() else {}
	return is_instance_valid(_leader) and view.get("leader") == _leader


## The screen points the panel keeps clear of: the click it is open on first, then each selected
## living teammate's body.
func _dock_points() -> Array:
	var points: Array = [_screen_of(_click)]
	points.append_array(_selection.filter(_alive).map(
		func(n: Node) -> Vector2: return _screen_of(n.global_position),
	))
	return points


## Screen point of world point `world` (the world's canvas transform).
func _screen_of(world: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world


## World point under screen point `screen` (the world's canvas transform).
func _world_of(screen: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen


# --- The panel ------------------------------------------------------------------------------------


## One offered item: its label, whether it is greyed out, what choosing it does, and why it is
## greyed (its tooltip then).
func _item(label: String, disabled: bool, act: Callable, why := "") -> Dictionary:
	return { "label": label, "disabled": disabled, "act": act, "why": why }


## Show `offered` as the panel's buttons, replacing the ones shown.
func _set_items(offered: Array) -> void:
	_items = offered
	_panel.set_items(offered)


## Build the ring layer and the hidden panel (title, recipients, items, "Hold for my go", the
## teammate list, the hint).
func _build() -> void:
	if _panel != null:
		return
	_mark = Control.new()
	_mark.name = "ClickMark"
	_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.draw.connect(_draw_mark)
	add_child(_mark)
	_panel = CommandPanel.new()
	_panel.name = "Panel"
	_panel.build(_teammates, _toggle)
	add_child(_panel)


## The ring on the clicked point, while the menu is open.
func _draw_mark() -> void:
	if not _open:
		return
	var at := _screen_of(_click)
	_mark.draw_arc(at, MARK_RADIUS, 0.0, TAU, 24, MARK_COLOR, 3.0)
	_mark.draw_circle(at, 3.0, MARK_COLOR)
