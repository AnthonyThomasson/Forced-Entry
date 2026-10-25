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
## How long (s) after a forced decision its reason stays shown.
const FORCE_SHOW := 4.0

## Whether to draw the brain overlay.
@export var show_brain: bool = false


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_brain


## Draws the overlay from the controller's public debug getters.
func _paint() -> void:
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


## The THINKING and FALLBACK badges of brain `b` from (`x`, `y`); returns the y below them.
func _paint_badges(b: Dictionary, x: float, y: float) -> float:
	if b["pending"]:
		var dots := ".".repeat(1 + int(GameClock.msec() / 300.0) % 3)
		DebugText.string(self, Vector2(x, y), "THINKING" + dots, FONT_SIZE + 2, THINK)
		y += LINE_H + 2
	if b["failed"]:
		DebugText.string(self, Vector2(x, y), "FALLBACK: no decision, holding", FONT_SIZE + 1, FAIL)
		y += LINE_H + 2
	return y


## The timers line of brain `b` at (`x`, `y`) (the next decision, plus the commitment / tactic
## countdowns the behaviour is on), the next decision's arc round the NPC and why the last one was
## forced; returns the y below them.
func _paint_timers(b: Dictionary, x: float, y: float) -> float:
	var t: Dictionary = b.get("timers", {})
	var parts: Array = ["next decision %.1fs" % b["decide_in"]]
	if t.get("tactic", 0.0) > 0.0:
		parts.append("tactic %.1fs" % t["tactic"])
	if t.get("commit", 0.0) > 0.0:
		parts.append("commit %.1fs" % t["commit"])
	DebugText.string(self, Vector2(x, y), " · ".join(parts), FONT_SIZE, TEXT)
	y += LINE_H
	_timer_arc(
		_character.global_position,
		33.0,
		1.0 - b["decide_in"] / maxf(b["decide_interval"], 0.01),
		THINK,
		2.0,
	)
	if b["force_reason"] != "" and b["force_age"] <= FORCE_SHOW:
		DebugText.string(self, Vector2(x, y), "forced: %s" % b["force_reason"], FONT_SIZE, THINK)
		y += LINE_H
	return y


## The facts that hold in brain `b`, on one line at (`x`, `y`); returns the y below it.
func _paint_facts(b: Dictionary, x: float, y: float) -> float:
	var facts: Array = []
	for k in b["facts"]:
		if b["facts"][k] == true:
			facts.append(str(k))
	if facts.is_empty():
		return y
	DebugText.string(
		self,
		Vector2(x, y),
		"facts: " + ", ".join(facts),
		FONT_SIZE,
		Color(0.7, 0.9, 1.0, 0.85),
	)
	return y + LINE_H


## One level of the last walk at (`x`, `y`): its node and Von's probability bar for each offered
## option, the pick highlighted (or the pick alone when it was auto-picked); returns the y below it.
func _paint_level(level: Dictionary, x: float, y: float) -> float:
	var auto: bool = level.get("auto", false)
	DebugText.string(
		self,
		Vector2(x, y),
		"%s%s" % [level["node"], " (auto)" if auto else " %dms" % level.get("ms", 0)],
		FONT_SIZE,
		TEXT,
	)
	y += LINE_H
	var probs: Dictionary = level.get("probabilities", {})
	var pick: String = str(level.get("pick", ""))
	var ids: Array = probs.keys()
	ids.sort_custom(func(a, c): return probs[a] > probs[c])
	for id in ids.slice(0, MAX_BARS):
		var p: float = probs[id]
		var col := PICK if str(id) == pick else BAR
		draw_rect(Rect2(Vector2(x, y - 12), Vector2(BAR_W * clampf(p, 0.0, 1.0), 12)), col)
		DebugText.string(
			self,
			Vector2(x + BAR_W + 4, y),
			"%s %d%%" % [id, int(p * 100.0)],
			FONT_SIZE - 1,
			col,
		)
		y += LINE_H - 2
	if probs.is_empty() and pick != "":
		DebugText.string(self, Vector2(x, y), "→ " + pick, FONT_SIZE - 1, PICK)
		y += LINE_H - 2
	return y
