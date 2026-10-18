extends Node2D

## UI domain: the stack markers. While the human's stack radio (the AI domain's `PlayerStack`) holds a reserved
## slot, this draws the slots of that doorway on the floor where each stands (on both sides of the door when the stack is
## split), numbered in the order they were claimed: the human's own highlighted, the ones the AI holds dimmer, a free one
## faint. Nothing is drawn without a reservation. And every stack of the human's side, ordered or its own (`docs/leadership.md`
## LD18), read from the squad's view (`watch_squad`: `{ stacks: [{ opening, into, door, slots: [{ n, point, holder, held, there, mine,
## side, row }] }] }`): dim while its member is on its way (`held`, not `there`), filled once there, the human's own bright, a free one
## faint, until the stack is through (it leaves the squad's view). A slot both views give is drawn once, the squad's ring with the human's
## own flag. A decoupled observer like the contact markers: it polls the watched node's `view()` (`{ slots: [{ n, point, mine, held }],
## ... }`) and the squad's view, and never writes.
##
## Added under the match's `World` node (world space), so the positions map straight to the floor. Main builds it and
## calls `watch` with the player's stack and `watch_squad` with the human's side's squad view.

const RING_RADIUS := 15.0
const FONT_SIZE := 18
## Colour of the human's own slot, of one a member holds, and of one nobody holds.
const COLOR_MINE := Color(0.35, 1.0, 0.45)
const COLOR_HELD := Color(0.62, 0.72, 0.9)
const COLOR_FREE := Color(0.62, 0.72, 0.9)
const ALPHA_MINE := 0.95
const ALPHA_HELD := 0.5
const ALPHA_FREE := 0.25
## How strongly a ring whose member stands in its slot is filled.
const ALPHA_THERE_FILL := 0.3

var _stack: Node = null      ## The watched stack (anything with `view()`); null = none.
var _squad := Callable()     ## The watched squad's view (`Squad.view`); invalid = none.
var _slots: Array = []       ## The rings now drawn: { n, point, mine, held, there, side, row, opening }.


## Watch the human's stack (anything with `view()`).
func watch(stack: Node) -> void:
	_stack = stack
	z_index = DrawLayers.ABOVE   # Over the floor and the standing world, so a character on a slot never hides its ring.


## Watch the stacks of the human's side through its squad's view (`view`, returning `{ stacks: [...] }`).
func watch_squad(view: Callable) -> void:
	_squad = view
	z_index = DrawLayers.ABOVE


## The rings drawn right now, as `{ n, point, mine, held, there, side, row, opening }`, empty with no stack.
func drawn() -> Array:
	return _slots


func _process(_delta: float) -> void:
	var slots := _rings()
	if slots != _slots:
		_slots = slots
		queue_redraw()


## Every ring to draw: the squad's stacks, each slot once, the human's own flagged; the human's reserved doorway when the squad's view has
## no stack there.
func _rings() -> Array:
	var own := {}
	if _stack != null and is_instance_valid(_stack):
		own = _stack.view() as Dictionary
	var own_opening := str(own.get("opening", ""))
	var mine := int(own.get("mine", 0))
	var out: Array = []
	var drawn_own := false
	var stacks: Array = []
	if _squad.is_valid():
		stacks = (_squad.call() as Dictionary).get("stacks", [])
	for st: Dictionary in stacks:
		var opening := str(st.get("opening", ""))
		var here := opening != "" and opening == own_opening
		drawn_own = drawn_own or here
		for s: Dictionary in st.get("slots", []):
			out.append(_ring(s, opening, bool(s.get("mine", false)) or (here and int(s["n"]) == mine)))
	if not drawn_own and own_opening != "":
		for s: Dictionary in own.get("slots", []):
			out.append(_ring(s, own_opening, bool(s.get("mine", false))))
	return out


## One ring as `drawn()` gives it, from slot `s` (a squad stack's or the `PlayerStack`'s) of doorway `opening`, `mine` the human's.
func _ring(s: Dictionary, opening: String, mine: bool) -> Dictionary:
	return { "n": int(s["n"]), "point": s["point"], "mine": mine, "held": bool(s.get("held", false)), "there": bool(s.get("there", false)),
		"side": int(s.get("side", 0)), "row": int(s.get("row", 1)), "opening": opening }


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for s in _slots:
		var at: Vector2 = s["point"]
		var mine: bool = s["mine"]
		var base := COLOR_MINE if mine else (COLOR_HELD if s["held"] else COLOR_FREE)
		base.a = ALPHA_MINE if mine else (ALPHA_HELD if s["held"] else ALPHA_FREE)
		if mine:
			draw_circle(at, RING_RADIUS, Color(base, 0.22))
		elif s["there"]:
			draw_circle(at, RING_RADIUS, Color(base, ALPHA_THERE_FILL))
		draw_arc(at, RING_RADIUS, 0.0, TAU, 24, base, 3.0 if mine else 2.0)
		var label := str(int(s["n"]))
		var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
		var text_at := at + Vector2(-size.x * 0.5, FONT_SIZE * 0.35)
		draw_string_outline(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 4, Color(0, 0, 0, 0.9))
		draw_string(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(base, 1.0))
