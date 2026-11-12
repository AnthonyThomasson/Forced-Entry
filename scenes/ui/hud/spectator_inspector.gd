extends CanvasLayer
## UI domain, spectator inspector: the debug lens for the spectator match (defenders vs invaders).
## SPACE pauses/resumes. A RIGHT-CLICK on an NPC selects it — revealing its debug overlays (the
## enabled ones) and opening its detail card (`detail_card.gd`: who it is, its health, item, outfit,
## decision path, brain, search, entry and the clicked point); a right-click on it again, or on
## empty ground, clears the selection and closes the card. With an NPC selected, a LEFT-CLICK on one
## of its tactical points (a zone marker) highlights that point and shows its kind, label and the
## reasoning text Von read (cover, route, range) in the card's Point section; a left-click anywhere
## else does nothing. No NPC shows any overlay until it is selected — the debug view is focused on
## one NPC at a time. In a spectator match the agent, brain, search and entry overlays' words are on
## the card, not in the world: `setup` turns `text_in_world` off on every NPC. The brain overlay
## then draws on the selected NPC alone, whatever the scope (`brain_labels`: its bars, ring and
## short labels by its indicators); every other NPC's brain draws nothing.
##
## It runs PROCESS_MODE_ALWAYS so Space and clicks work while the tree is paused (freeze the match,
## then inspect). A decoupled observer like the other spectator UI: it reads only published surfaces
## — the combatants' public `global_position`, the framing camera's view for the click's world
## point, and each NPC's `debug_zones()` (duck-typed) for the point details — and flips the
## debug-overlay toggles (every per-NPC `show_<x>` flag of the overlay registry) through
## `OverlayRegistry.apply`, as Main does. Main builds it in spectator mode. Player-mode input is
## untouched: Space stays the player's INTERACT there (this node exists only in the match).

## World-space pick radius (px) around the cursor within which a right-click selects an NPC.
const PICK_RADIUS := 48.0
## World-space pick radius (px) within which a left-click on the selected NPC's zone picks it.
const ZONE_PICK_RADIUS := 20.0
const ContactMarkers := preload("res://scenes/ui/hud/contact_markers.gd")
const DetailCard := preload("res://scenes/ui/hud/detail_card.gd")
const HudProbe := preload("res://scenes/ui/hud/hud_probe.gd")
const OverlayRegistry := preload("res://scenes/ui/overlays/overlay_registry.gd")

## The NPCs to pick from (public nodes), handed in by Main.
var _combatants: Array = []
## Which overlay toggles to enable on the selected NPC (from Main).
var _flags: Dictionary = {}
## Which NPCs show their overlays besides the selected one (`OverlayRegistry.SCOPES`).
var _scope := OverlayRegistry.SCOPE_SELECTED
## The NPC whose overlays are shown, or null.
var _selected: Node = null
## The selected NPC's controller, cached for live marker refreshes.
var _selected_ctrl: Node = null
## The selected NPC's detail card (hidden while nothing is selected).
var _card: PanelContainer
## World-space overlay that draws the selected NPC's contact knowledge.
var _contact_markers: Node2D


## SPACE toggles pause; a right-click selects or deselects an NPC, and a left-click inspects the
## selected NPC's tactical point under the cursor. Handled here so it works in the player-less match
## and while the tree is paused.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(Keybinds.PAUSE) and not event.is_echo():
		_set_paused(not get_tree().paused)
	elif event is InputEventMouseButton and event.pressed:
		# A click is placed by its event's own position, never the viewport's mouse position, which
		# in a window is the system cursor and not where the event says the click was.
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click(Pointer.world_of(self, event.position))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(Pointer.world_of(self, event.position))


## Refresh the contact markers every frame so the rings track characters as they move (and as the
## selected NPC's knowledge of them updates). Runs while paused too, where the knowledge holds
## steady.
func _process(_delta: float) -> void:
	if _selected != null:
		_refresh_markers()


## Keep running while paused and build the detail card. `flags` is the overlay toggle bar's per-NPC
## toggles (Main's `_overlays.flags` without the global ones; property name -> bool); a selected NPC
## shows exactly those. `right_clear` is the screen width (px) from the right edge the card keeps
## clear: Main hands it the overlay toggle bar's column. Called by Main.
func setup(combatants: Array, flags: Dictionary, right_clear: float) -> void:
	_combatants = combatants
	_flags = flags
	process_mode = Node.PROCESS_MODE_ALWAYS
	# World-space contact-indicator overlay added as a sibling so it draws in world coordinates.
	_contact_markers = ContactMarkers.new()
	_contact_markers.name = "ContactMarkers"
	get_parent().add_child(_contact_markers)
	# Their words are on the detail card, not floating in the world.
	for c in combatants:
		if is_instance_valid(c):
			OverlayRegistry.apply(c, { "text_in_world": false })
	_card = DetailCard.new()
	_card.name = "DetailCard"
	add_child(_card)
	_card.setup(right_clear)
	_select(null)  # start with every NPC's overlays hidden — nothing is shown until clicked


## Update one overlay toggle live (from the in-game toggle bar) and apply it to the NPCs that show
## their overlays (the scope's and the selected one), so the button takes effect at once; later
## selections use the new value too.
func set_flag(flag: String, on: bool) -> void:
	_flags[flag] = on
	for c in _combatants:
		if is_instance_valid(c) and _shows(c):
			OverlayRegistry.apply(c, { flag: on })


## Show overlays on the NPCs of `scope` (`OverlayRegistry.SCOPES`: `selected` for the selected NPC
## alone, `defenders`, `invaders` or `all`) as well as on the selected NPC, at once (also while
## paused). Called by Main when the bar's "Show on" row changes.
func set_scope(scope: String) -> void:
	_scope = scope
	_apply_overlays()


## Pause or resume the whole tree (this node keeps running — PROCESS_MODE_ALWAYS).
func _set_paused(pause: bool) -> void:
	get_tree().paused = pause


## A right-click selects the NPC under the cursor (opening its card), or clears the selection when
## it is the selected one or there is none there.
func _on_right_click(world: Vector2) -> void:
	var npc := _npc_at(world)
	_select(null if npc == _selected else npc)


## A left-click on one of the selected NPC's tactical points shows its details; anywhere else it
## does nothing.
func _on_left_click(world: Vector2) -> void:
	if _selected != null and is_instance_valid(_selected):
		var zone := _zone_at(world)
		if not zone.is_empty():
			_show_zone(zone)


## The NPC nearest `world` within PICK_RADIUS, or null when the click missed everyone.
func _npc_at(world: Vector2) -> Node:
	var best: Node = null
	var best_d := PICK_RADIUS
	for npc in _combatants:
		if not is_instance_valid(npc):
			continue
		var d: float = (npc.global_position as Vector2).distance_to(world)
		if d <= best_d:
			best_d = d
			best = npc
	return best


## The selected NPC's tactical zone nearest `world` within ZONE_PICK_RADIUS (its `debug_zones()`
## entry `{ point, category, label, desc }`), or an empty dict when the click wasn't on one.
func _zone_at(world: Vector2) -> Dictionary:
	var ctrl := HudProbe.controller_of(_selected)
	if ctrl == null:
		return {}
	var best := {}
	var best_d := ZONE_PICK_RADIUS
	for zone in ctrl.debug_zones():
		var d: float = (zone["point"] as Vector2).distance_to(world)
		if d <= best_d:
			best_d = d
			best = zone
	return best


## Select `npc` (null = none): show only the selected NPC's own overlays and cache its controller
## for the live marker refresh. Clears any tactical-point detail/highlight from the previous
## selection (on the PREVIOUS NPC, not the new one — _clear_zone must run before _selected_ctrl is
## reassigned).
func _select(npc: Node) -> void:
	_clear_zone()
	_selected = npc
	_selected_ctrl = HudProbe.controller_of(npc)
	_apply_overlays()
	if npc != null:
		_card.show_for(npc)
	else:
		_card.close()
	_refresh_markers()


## Show the enabled overlays on the NPCs that show them and hide every other NPC's; the brain
## overlay draws (bars, ring and short labels) on the selected NPC alone.
func _apply_overlays() -> void:
	for c in _combatants:
		if is_instance_valid(c):
			var flags: Dictionary = (_flags if _shows(c) else _flags_off()).duplicate()
			flags["brain_labels"] = c == _selected
			OverlayRegistry.apply(c, flags)


## Whether `npc` shows its overlays: it is the selected one, or in the scope.
func _shows(npc: Node) -> bool:
	return npc == _selected or OverlayRegistry.in_scope(npc, _scope)


## Push the selected NPC's current contact knowledge to the world-space marker overlay (empty when
## nothing is selected), so each ring sits on the position that NPC last knew the contact to be at.
func _refresh_markers() -> void:
	if _contact_markers == null:
		return
	var display: Array = []
	if _selected_ctrl != null and is_instance_valid(_selected_ctrl):
		for c in _selected_ctrl.known_contacts_for_display():
			display.append({
				"pos": c["pos"],
				"name": c["name"],
				"hostile": c["hostile"],
				"visible": c["visible"],
			})
	_contact_markers.set_contacts(display)


## Every flag of `_flags` set false: what a hidden NPC's overlays are given.
func _flags_off() -> Dictionary:
	var off := {}
	for flag in _flags:
		off[flag] = false
	return off


## Highlight the clicked tactical point on the selected NPC and show its kind, label and the
## reasoning text Von read in the card.
func _show_zone(zone: Dictionary) -> void:
	if _selected_ctrl != null and is_instance_valid(_selected_ctrl):
		_selected_ctrl.debug_focus = zone["point"]
	_card.set_point(zone)


## Drop any tactical-point detail: clear the highlight on the selected NPC and the card's Point
## section.
func _clear_zone() -> void:
	if _selected_ctrl != null and is_instance_valid(_selected_ctrl):
		_selected_ctrl.debug_focus = Vector2.INF
	if _card != null:
		_card.set_point({})
