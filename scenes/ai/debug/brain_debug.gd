extends "res://scenes/ai/debug/debug_overlay.gd"
## AI domain, debug: the NPC's decision machinery. A "thinking…" badge while Von is being asked, a
## red FALLBACK badge when the last walk failed (the NPC then holds steady), the time to the next
## decision and why the last one was forced, the commitment / tactic timers, the facts that hold,
## and — per level of the last walk — Von's probability bars with the pick highlighted. Reads the
## controller's `debug_brain()` only.

const THINK := Color(1.0, 0.85, 0.2)
const FAIL := Color(1.0, 0.3, 0.3)
const PICK := Color(0.4, 0.95, 0.5)
const BAR := Color(0.55, 0.65, 0.9)
const TEXT := Color(1, 1, 1, 0.8)
## Where the panel sits relative to the NPC, and its bar geometry.
const ORIGIN := Vector2(40, -96)
const BAR_W := 90.0
const LINE_H := 21.0
const MAX_BARS := 4
## The next-decision ring's radius round the NPC.
const RING_RADIUS := 33.0
## Where the next-decision ring's seconds sit relative to the NPC (above the ring).
const RING_LABEL_AT := Vector2(-14, -40)
## How long (s) after a forced decision its reason stays shown.
const FORCE_SHOW := 4.0
## The badge shown when the last walk failed and the NPC holds steady.
const FALLBACK_TEXT := "FALLBACK: no decision, holding"

## Whether to draw the brain overlay.
@export var show_brain: bool = false
## Whether the overlay draws at all while `text_in_world` is off (a spectator match): with both
## off it draws nothing, no bars, no ring, no labels. On, it draws its bars and ring and short
## labels by them: the THINKING / FALLBACK badges, each level's node title, each bar's option and
## percentage and the next-decision ring's seconds (the facts, the timers line and the forced
## reason stay card-only). The spectator inspector sets it on the selected NPC alone, so under a
## side scope only the right-clicked NPC shows its brain; with `text_in_world` on it changes
## nothing (the full overlay draws, with no ring label).
@export var brain_labels: bool = false

## What the last paint drew: `{ kind: &"bar", option, probability, picked }` per probability bar,
## `{ kind: &"ring", fraction, radius }` for the next-decision ring and `{ kind: &"label", text }`
## per string, in drawing order.
var _drawn: Array = []


## Every redraw starts `drawn()` over, also one that draws nothing (toggled off, the NPC dead).
func _draw() -> void:
	_drawn.clear()
	super()


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_brain


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
	if not text_in_world and not brain_labels:
		return
	var b: Dictionary = _controller.debug_brain()
	if b.is_empty():
		return
	var x := ORIGIN.x
	var y := _paint_badges(b, x, ORIGIN.y)
	y = _paint_timers(b, x, y)
	y = _paint_facts(b, x, y)
	# One block per level of the last walk: the node and Von's probability for each offered option.
	for level in b["levels"]:
		y = _paint_level(level, x, y + 3.0)


## What the last paint drew, `bar`, `ring` and `label` entries (read by tests and nothing else).
func drawn() -> Array:
	return _drawn


## Record the string too: a `label` entry of `drawn()`.
func note_text(text: String) -> void:
	super(text)
	_drawn.append({ "kind": &"label", "text": text })


## The words of the overlay, one line each in the order they are drawn, for the detail card: the
## THINKING and FALLBACK badges, the timers, why the last decision was forced, the facts that hold
## and, per level of the last walk, its node and Von's probability for each offered option.
func card_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var b: Dictionary = _controller.debug_brain()
	if b.is_empty():
		return out
	if b["pending"]:
		out.append(_thinking_text())
	if b["failed"]:
		out.append(FALLBACK_TEXT)
	out.append(_timers_text(b))
	if _forced(b):
		out.append(_forced_text(b))
	var facts := _facts_text(b)
	if facts != "":
		out.append(facts)
	for level: Dictionary in b["levels"]:
		out.append(_level_text(level))
		for id in _top_ids(level):
			out.append(_bar_text(id, level["probabilities"][id]))
		if _picked_alone(level):
			out.append(_pick_text(level))
	return out


## The THINKING and FALLBACK badges of brain `b` from (`x`, `y`); returns the y below them.
func _paint_badges(b: Dictionary, x: float, y: float) -> float:
	if b["pending"]:
		_tag(Vector2(x, y), _thinking_text(), FONT_SIZE + 2, THINK)
		y += LINE_H + 2
	if b["failed"]:
		_tag(Vector2(x, y), FALLBACK_TEXT, FONT_SIZE + 1, FAIL)
		y += LINE_H + 2
	return y


## An indicator's label at local position `pos` (every paint that gets this far draws it: the
## paint is skipped with both `text_in_world` and `brain_labels` off).
func _tag(pos: Vector2, text: String, size: int, color: Color) -> void:
	DebugText.string(self, pos, text, size, color)


## The THINKING badge's text, its dots cycling with the game clock.
func _thinking_text() -> String:
	return "THINKING" + ".".repeat(1 + int(GameClock.msec() / 300.0) % 3)


## The timers line of brain `b` at (`x`, `y`) (the next decision, plus the commitment / tactic
## countdowns the behaviour is on), the next decision's arc round the NPC and why the last one was
## forced; returns the y below them.
func _paint_timers(b: Dictionary, x: float, y: float) -> float:
	_say(Vector2(x, y), _timers_text(b), FONT_SIZE, TEXT)
	y += LINE_H
	var fraction: float = 1.0 - b["decide_in"] / maxf(b["decide_interval"], 0.01)
	_timer_arc(_character.global_position, RING_RADIUS, fraction, THINK, 2.0)
	if fraction > 0.0:
		_drawn.append({ "kind": &"ring", "fraction": fraction, "radius": RING_RADIUS })
	if brain_labels and not text_in_world:
		_label(_character.global_position, "%.1fs" % b["decide_in"], THINK, RING_LABEL_AT)
	if _forced(b):
		_say(Vector2(x, y), _forced_text(b), FONT_SIZE, THINK)
		y += LINE_H
	return y


## The timers line of brain `b`: the next decision, the tactic and the commitment countdowns.
func _timers_text(b: Dictionary) -> String:
	var t: Dictionary = b.get("timers", {})
	var parts: Array = ["next decision %.1fs" % b["decide_in"]]
	if t.get("tactic", 0.0) > 0.0:
		parts.append("tactic %.1fs" % t["tactic"])
	if t.get("commit", 0.0) > 0.0:
		parts.append("commit %.1fs" % t["commit"])
	return " · ".join(parts)


## Whether brain `b` shows why its last decision was forced (a reason, still fresh).
func _forced(b: Dictionary) -> bool:
	return b["force_reason"] != "" and b["force_age"] <= FORCE_SHOW


## The line saying why brain `b`'s last decision was forced.
func _forced_text(b: Dictionary) -> String:
	return "forced: %s" % b["force_reason"]


## The facts that hold in brain `b`, on one line at (`x`, `y`); returns the y below it.
func _paint_facts(b: Dictionary, x: float, y: float) -> float:
	var text := _facts_text(b)
	if text == "":
		return y
	_say(Vector2(x, y), text, FONT_SIZE, Color(0.7, 0.9, 1.0, 0.85))
	return y + LINE_H


## The facts that hold in brain `b`, on one line ("" with none).
func _facts_text(b: Dictionary) -> String:
	var facts: Array = []
	for k in b["facts"]:
		if b["facts"][k] == true:
			facts.append(str(k))
	return "" if facts.is_empty() else "facts: " + ", ".join(facts)


## One level of the last walk at (`x`, `y`): its node and Von's probability bar for each offered
## option, the pick highlighted (or the pick alone when it was auto-picked); returns the y below it.
func _paint_level(level: Dictionary, x: float, y: float) -> float:
	_tag(Vector2(x, y), _level_text(level), FONT_SIZE, TEXT)
	y += LINE_H
	var probs: Dictionary = level.get("probabilities", {})
	var pick: String = str(level.get("pick", ""))
	for id in _top_ids(level):
		var p: float = probs[id]
		var col := PICK if str(id) == pick else BAR
		draw_rect(Rect2(Vector2(x, y - 12), Vector2(BAR_W * clampf(p, 0.0, 1.0), 12)), col)
		_drawn.append(
			{ "kind": &"bar", "option": str(id), "probability": p, "picked": str(id) == pick },
		)
		_tag(Vector2(x + BAR_W + 4, y), _bar_text(id, p), FONT_SIZE - 1, col)
		y += LINE_H - 2
	if _picked_alone(level):
		_say(Vector2(x, y), _pick_text(level), FONT_SIZE - 1, PICK)
		y += LINE_H - 2
	return y


## The title of a level: its node, and Von's time on it or "(auto)".
func _level_text(level: Dictionary) -> String:
	var auto: bool = level.get("auto", false)
	return "%s%s" % [level["node"], " (auto)" if auto else " %dms" % level.get("ms", 0)]


## The options of `level` that get a bar: the most probable `MAX_BARS`, most probable first.
func _top_ids(level: Dictionary) -> Array:
	var probs: Dictionary = level.get("probabilities", {})
	var ids: Array = probs.keys()
	ids.sort_custom(func(a, c): return probs[a] > probs[c])
	return ids.slice(0, MAX_BARS)


## The label of an option's bar: its id and probability.
func _bar_text(id: Variant, p: float) -> String:
	return "%s %d%%" % [id, int(p * 100.0)]


## Whether `level` has a pick but no probabilities to show (it was picked without asking Von).
func _picked_alone(level: Dictionary) -> bool:
	var probs: Dictionary = level.get("probabilities", {})
	return probs.is_empty() and str(level.get("pick", "")) != ""


## The line of a level picked alone: an arrow to the pick.
func _pick_text(level: Dictionary) -> String:
	return "→ " + str(level["pick"])
