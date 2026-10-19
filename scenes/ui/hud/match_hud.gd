extends CanvasLayer
## UI domain, spectator-match observer: the HUD for an N-AI contest (defenders vs invaders).
## Across the top is a running match timer and, once one side dies, the winner banner.
##
## It is a decoupled observer, reading only a published contract — the Character public API/signals
## (`faction`, the `died` signal) — so it never reaches into any domain's internals.
## Main calls `begin()` with the combatants when it sets up a match (and again for each new one in
## an endless run). `match_ended` tells Main the verdict, so it never has to work out a winner
## itself.

## Emitted once per match when it is decided: `verdict` is the banner text ("DEFENDER WINS", "TIME
## UP - DRAW", …).
signal match_ended(verdict: String)

## The characters of each side.
var _combatants: Array = []
## Match time so far (s); stops once decided.
var _elapsed: float = 0.0
## When it was decided; -1 while ongoing (freezes the timer).
var _end_ms: int = -1
## Winner banner text once decided.
var _verdict: String = ""
## Seconds before an undecided match is called a draw; 0 = no limit.
var _time_limit: float = 0.0
## Footer line under the verdict (e.g. the next-match countdown).
var _countdown: String = ""
## Top-centre running match time.
var _timer_label: Label
## Centre winner banner, empty until the match is decided.
var _verdict_label: Label
## Under the verdict banner; blank unless Main set a countdown.
var _countdown_label: Label


func _process(delta: float) -> void:
	if _combatants.is_empty():
		return
	if _end_ms < 0:
		# frame time, so pausing the tree (Space) also pauses the clock and the limit
		_elapsed += delta
		if _time_limit > 0.0 and _elapsed >= _time_limit:
			_decide("TIME UP - DRAW")
	_timer_label.text = "MATCH  %.1fs" % _elapsed
	_verdict_label.text = _verdict
	_countdown_label.text = _countdown


## Begin observing a match between `combatants` (character nodes). Builds the UI and wires each
## side's death signal. Safe to call again for a new match: the previous match's UI, combatants and
## verdict are dropped first. A `time_limit` > 0 calls a match still undecided after that many
## seconds a draw.
func begin(combatants: Array, time_limit := 0.0) -> void:
	for c in get_children():
		c.queue_free()
	_combatants.clear()
	_verdict = ""
	_countdown = ""
	_end_ms = -1
	_time_limit = time_limit
	_elapsed = 0.0
	_build_ui()
	for c in combatants:
		_combatants.append(c)
		if c.has_signal("died"):
			c.died.connect(_on_died)


## Show `text` under the verdict banner (blank clears it). Main uses it for the next-match
## countdown.
func set_countdown(text: String) -> void:
	_countdown = text


## Record the outcome when a combatant dies, by General's `MatchVerdict` (the rule the dev
## command server's `match` verb decides by too): a single death does not end a multi-NPC side, the
## match is decided once a side is wiped out. The one side left standing wins, named by its lone
## survivor or by its faction label; nobody, or more than one side, left is a draw.
func _on_died() -> void:
	if _end_ms >= 0:
		return
	var verdict := MatchVerdict.decide(_combatants)
	if verdict.is_empty():
		return  # Every side still has someone alive: the match goes on.
	var survivors: Array = verdict["survivors"]
	if verdict["winner"] == null:
		_decide("DRAW")
	elif survivors.size() == 1:
		_decide("%s WINS" % str(survivors[0].name))
	else:
		_decide("%s WINS" % str(verdict["winner"]).to_upper())


## Fix the result: freeze the timer, show `verdict` and tell the observers (once).
func _decide(verdict: String) -> void:
	if _end_ms >= 0:
		return
	_end_ms = Time.get_ticks_msec()
	_verdict = verdict
	match_ended.emit(verdict)


# --- UI construction (labels anchored like the debug HUD; no scene-side layout) ----------


## Build the shared chrome: the top timer, the centre verdict banner and the countdown under it.
func _build_ui() -> void:
	_timer_label = _add_label(
		0.5,
		0.0,
		Vector2(-130, 16),
		Vector2(260, 52),
		34,
		Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_verdict_label = _add_label(
		0.5,
		0.4,
		Vector2(-350, 0),
		Vector2(700, 88),
		62,
		Color.GOLD,
		HORIZONTAL_ALIGNMENT_CENTER,
	)
	_countdown_label = _add_label(
		0.5,
		0.4,
		Vector2(-350, 96),
		Vector2(700, 48),
		30,
		Color.WHITE,
		HORIZONTAL_ALIGNMENT_CENTER,
	)


## Create and return a Label anchored at (`ax`,`ay`) with the given offset, size, font size, colour
## and horizontal alignment.
func _add_label(
	ax: float,
	ay: float,
	pos: Vector2,
	size: Vector2,
	font_size: int,
	color: Color,
	align: HorizontalAlignment,
) -> Label:
	var label := Label.new()
	add_child(label)
	label.anchor_left = ax
	label.anchor_right = ax
	label.anchor_top = ay
	label.anchor_bottom = ay
	label.offset_left = pos.x
	label.offset_top = pos.y
	label.offset_right = pos.x + size.x
	label.offset_bottom = pos.y + size.y
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
