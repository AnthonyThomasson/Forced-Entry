extends Node2D
## AI domain, debug: the shared base of every draw-only overlay (vision / agent / tactics / search /
## contacts / hearing / combat / territory / targets / brain / routes / stuck / grenade / entry /
## entry team). Each subclass declares its own `@export var show_<x>` toggle(s) (found by property
## name, the names in the UI's OverlayRegistry), overrides `_on()` to report them and `_paint()` to
## draw, and reads only the sibling GoalController's public getters and exports (the agent overlay
## also the NavigationAgent2D's path) — it senses nothing and feeds nothing back. The base finds the
## controller and character, runs PROCESS_MODE_ALWAYS so it keeps drawing while the tree is paused,
## redraws every frame only while `_on()` is true and paints only while the NPC is alive.
##
## Its words can leave the world: `text_in_world` (on by default) off, the overlays that say
## their status in words (agent, brain, search, entry) draw none, leaving the words to the
## spectator's detail card, which reads each one's `card_lines()`. What an overlay draws as text is
## recorded through `DebugText` (`drawn_texts()`, cleared at each paint), which is how a test reads
## it.

const DebugText := preload("res://scenes/ai/debug/debug_text.gd")
const FONT_SIZE := 16

## The GoalController to read from (a sibling under the NPC).
@export var controller_path: NodePath = NodePath("../GoalController")

## Whether the overlay's status words (label, badge, timers, bars) draw in the world. Off, they are
## left to the detail card (`card_lines()`); the overlay's geometry draws as ever (the agent, search
## and entry overlays leave no text in the world; the brain overlay draws nothing at all unless its
## `brain_labels` is on; the other overlays' short tags are not gated).
var text_in_world := true
## The GoalController read for the overlay's data.
var _controller: Node
## The NPC body this overlay is a child of.
var _character: Node2D
## The strings drawn since the last paint began, in order.
var _texts := PackedStringArray()


func _ready() -> void:
	ViewLayers.overlay(self)
	_controller = get_node_or_null(controller_path)
	_character = get_parent() as Node2D
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _on():
		queue_redraw()


func _draw() -> void:
	_texts.clear()
	if not _on() or _controller == null or _character == null or _character.get("is_dead") == true:
		return
	_paint()


## The words this overlay says about its NPC, one line each, as it draws them with `text_in_world`
## on: what the detail card shows, whatever the toggles and `text_in_world` say. None by default;
## the agent, brain, search and entry overlays override it.
func card_lines() -> PackedStringArray:
	return PackedStringArray()


## The strings the last paint drew, in order (read by tests and nothing else).
func drawn_texts() -> PackedStringArray:
	return _texts


## Record that `text` was drawn on this overlay (called by `DebugText`).
func note_text(text: String) -> void:
	_texts.append(text)


## Whether this overlay's toggle is on. Subclasses return their `show_<x>` flag.
func _on() -> bool:
	return false


## Draw the overlay. Called only while the toggle is on and the NPC is alive; subclasses override.
func _paint() -> void:
	pass


## Status words at local position `pos`, drawn only while `text_in_world`.
func _say(pos: Vector2, text: String, size: int, color: Color) -> void:
	if text_in_world:
		DebugText.string(self, pos, text, size, color)


## A small text label at world point `world` (drawn in this node's local space).
func _label(world: Vector2, text: String, color: Color, offset := Vector2(6, -6)) -> void:
	DebugText.string(self, to_local(world) + offset, text, FONT_SIZE, color)


## A ring (circle outline) of world radius `radius` around world point `world`.
func _ring(world: Vector2, radius: float, color: Color, width := 1.5) -> void:
	draw_arc(to_local(world), radius, 0.0, TAU, 40, color, width)


## A line between two world points.
func _line(a: Vector2, b: Vector2, color: Color, width := 1.5) -> void:
	draw_line(to_local(a), to_local(b), color, width)


## An arrow from world point `a` toward `b` with a small head.
func _arrow(a: Vector2, b: Vector2, color: Color, width := 2.0) -> void:
	var la := to_local(a)
	var lb := to_local(b)
	draw_line(la, lb, color, width)
	var dir := (lb - la).normalized()
	if dir == Vector2.ZERO:
		return
	var head := 7.0
	draw_line(lb, lb - dir.rotated(0.45) * head, color, width)
	draw_line(lb, lb - dir.rotated(-0.45) * head, color, width)


## A pie-style countdown arc around world point `world`: `fraction` (0..1) of a full circle, from
## the top.
func _timer_arc(world: Vector2, radius: float, fraction: float, color: Color, width := 3.0) -> void:
	if fraction <= 0.0:
		return
	draw_arc(
		to_local(world),
		radius,
		-PI * 0.5,
		-PI * 0.5 + TAU * clampf(fraction, 0.0, 1.0),
		24,
		color,
		width,
	)
