extends GameTest
## The agent, brain, search and entry debug overlays (AI debug, `scenes/ai/debug/`) say their words
## in two places: floating in the world beside the NPC and, as `card_lines()`, on the spectator's
## detail card. `text_in_world` (the base's flag, on by default) decides the first: off, an overlay
## draws no text at all (what it drew is recorded through `DebugText` and read back by
## `drawn_texts()`) while its geometry still draws, and `card_lines()` still gives the lines it
## would have drawn. A spectator match's inspector turns it off on every NPC; a player match, which
## has no inspector, leaves it on.
##
## The brain overlay of the NPC the inspector has selected keeps short labels by its indicators
## even then (`brain_labels`): the THINKING / FALLBACK badges, each level's node title, each
## probability bar's option and percentage and the next-decision ring's seconds, and no facts,
## timers line or forced reason. With `text_in_world` on it draws its full text and no ring label.
##
## Each overlay reads a fake controller (the getters it reads, answering fixed data), so a search
## and an entry are under way without a house to set them up in.

const Inspector := preload("res://scenes/ui/hud/spectator_inspector.gd")
const OverlayToggles := preload("res://scenes/ui/overlays/overlay_toggles.gd")
## The four overlays, with the `show_<x>` flags that put each on.
const KINDS := [
	{ "script": "agent_debug", "flags": ["show_actions", "show_path"] },
	{ "script": "brain_debug", "flags": ["show_brain"] },
	{ "script": "search_debug", "flags": ["show_search"] },
	{ "script": "entry_debug", "flags": ["show_entry"] },
]
const TEXT_KINDS := ["agent_debug", "brain_debug", "search_debug", "entry_debug"]


func describe() -> Dictionary:
	return {
		"name": "The text overlays leave their words to the card when asked",
		"description": "With text_in_world off the agent, brain, search and entry overlays draw no "
			+ "text, and card_lines() gives the lines they draw with it on (the brain overlay "
			+ "keeps short labels by its indicators when brain_labels is on); a spectator "
			+ "match's inspector turns it off on every NPC, a player match leaves it on.",
		"tags": ["ai", "debug", "overlay", "ui"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"ai.vision", false)
	s.von_down()
	s.lock_interaction([&"camera", &"pause"])
	s.actor(&"watched", &"defender", Vector2(300, 250), { "movement:speed": 0.0 })
	s.actor(&"other", &"invader", Vector2(600, 250), { "movement:speed": 0.0 })


func run(t: TestContext) -> void:
	for kind: Dictionary in KINDS:
		await _check_overlay(t, kind)
	await _check_brain_labels(t)
	_check_player_mode(t)
	await _check_inspector(t)


## One overlay on a fake NPC: with the text in the world it draws its card lines; without, none.
func _check_overlay(t: TestContext, kind: Dictionary) -> void:
	var name: String = kind["script"]
	var overlay := await _spawn_overlay(t, name, kind["flags"])
	var body: Node2D = overlay.get_parent()
	if not t.require(overlay.has_method("card_lines"), "%s gives card_lines()" % name):
		return
	var lines: PackedStringArray = overlay.card_lines()
	t.check(not lines.is_empty(), "%s has lines for the card" % name)
	t.check(overlay.text_in_world, "%s draws its text in the world by default" % name)
	var drawn := _normal(overlay.drawn_texts())
	for line in _normal(lines):
		t.check(drawn.has(line), "%s draws its card line '%s' (drew %s)" % [name, line, drawn])

	overlay.text_in_world = false
	await t.frames(3)
	t.expect_eq(overlay.drawn_texts().size(), 0, "%s draws no text with text_in_world off" % name)
	t.expect_eq(
		_normal(overlay.card_lines()), _normal(lines), "%s still gives its card lines" % name,
	)
	body.queue_free()


## The brain overlay with `text_in_world` off and `brain_labels` on draws only its indicators'
## labels (the fake brain: THINKING and FALLBACK, a "mode" level of 120 ms offering combat 70% and
## search 30%, an auto-picked "tactic" level, the next decision in 0.8 s); with `text_in_world` on
## it draws its card lines and no ring label.
func _check_brain_labels(t: TestContext) -> void:
	var overlay := await _spawn_overlay(t, "brain_debug", ["show_brain"])
	overlay.text_in_world = false
	overlay.brain_labels = true
	await t.frames(3)
	var expected := [
		"THINKING", "FALLBACK: no decision, holding", "mode 120ms", "combat 70%", "search 30%",
		"tactic (auto)", "0.8s",
	]
	var drawn := _normal(overlay.drawn_texts())
	drawn.sort()
	expected.sort()
	t.expect_eq(drawn, expected, "brain_labels draws the badges, titles, bar labels and the ring")

	overlay.text_in_world = true
	await t.frames(3)
	t.expect_eq(
		_normal(overlay.drawn_texts()), _normal(overlay.card_lines()),
		"with text_in_world on the brain draws its full text",
	)
	t.check(not overlay.drawn_texts().has("0.8s"), "and no ring label")
	overlay.get_parent().queue_free()


## A fake NPC body in the world with the overlay script `name` on it, `flags` on, painted.
func _spawn_overlay(t: TestContext, name: String, flags: Array) -> Node2D:
	var body := Body.new()
	var brain := Brain.new()
	brain.name = "GoalController"
	body.add_child(brain)
	var overlay: Node2D = load("res://scenes/ai/debug/%s.gd" % name).new()
	for flag: String in flags:
		overlay.set(flag, true)
	body.add_child(overlay)
	t.world.add_child(body)
	body.global_position = Vector2(450, 250)
	await t.frames(3)
	return overlay


## A player match has no inspector: the overlays of a real NPC keep their text in the world.
func _check_player_mode(t: TestContext) -> void:
	for id: StringName in [&"watched", &"other"]:
		for name: String in TEXT_KINDS:
			var overlay := _overlay_of(t.actor(id), name)
			t.check(overlay != null and overlay.text_in_world, "%s/%s keeps its text" % [id, name])


## The spectator inspector's setup turns the text off on every NPC it is given.
func _check_inspector(t: TestContext) -> void:
	var inspector := CanvasLayer.new()
	inspector.set_script(Inspector)
	t.world.add_child(inspector)
	inspector.call(
		"setup", [t.actor(&"watched"), t.actor(&"other")], {}, OverlayToggles.RESERVED_WIDTH,
	)
	await t.frames(2)
	for id: StringName in [&"watched", &"other"]:
		for name: String in TEXT_KINDS:
			var overlay := _overlay_of(t.actor(id), name)
			t.check(
				overlay != null and not overlay.text_in_world,
				"the inspector turns off %s/%s's text" % [id, name],
			)
	inspector.queue_free()


## The overlay named `script` (its file's stem) among `npc`'s children, or null.
func _overlay_of(npc: Node, script: String) -> Node:
	for child in npc.get_children():
		var path: String = child.get_script().resource_path if child.get_script() else ""
		if path.get_file().get_basename() == script:
			return child
	return null


## `lines` with a trailing run of dots dropped (a THINKING badge animates them) as an Array.
func _normal(lines: PackedStringArray) -> Array:
	return Array(lines).map(func(l: String) -> String: return l.rstrip("."))


## A stand-in for the NPC's body.
class Body extends Node2D:
	var is_dead := false


## A stand-in for the NPC's controller: the getters the four overlays read, with fixed answers.
class Brain extends Node:
	func debug_status() -> String:
		return "COMBAT - Intruder - FLANK - their left side (kitchen)"

	func debug_brain() -> Dictionary:
		return {
			"pending": true, "failed": true,
			"timers": { "tactic": 2.0, "commit": 1.5 },
			"decide_in": 0.8, "decide_interval": 2.0,
			"force_reason": "under fire", "force_age": 1.0,
			"facts": { "under_fire": true, "alone": false },
			"levels": [
				{
					"node": "mode", "ms": 120, "pick": "combat",
					"probabilities": { "combat": 0.7, "search": 0.3 },
				},
				{ "node": "tactic", "auto": true, "pick": "flank" },
			],
		}

	func debug_search_coverage() -> Dictionary:
		return {
			"active": true,
			"points": [Vector2(10, 10), Vector2(40, 10), Vector2(10, 40), Vector2(40, 40)],
			"unseen": [Vector2(40, 40)], "target": Vector2(40, 40), "budget": 4.5,
		}

	func debug_entry_view() -> Dictionary:
		var door := Vector2(450, 150)
		return {
			"guard": { "views": [], "round_views": false, "cleared_rooms": [] },
			"entry": {
				"door": {
					"pos": door, "width": 60.0, "out": Vector2.UP, "along": Vector2.RIGHT,
					"funnel": 40.0,
				},
				"opening": "front", "into": "hall", "phase": "pie", "role": "point",
				"slot": 1, "side": 1, "place": 1, "my_slot": Vector2(400, 200),
				"slots": { 1: [Vector2(400, 200)], -1: [Vector2(500, 200)] },
				"team": [], "waypoints": [], "unseen": [], "corners": [],
				"corner": Vector2.INF, "gaze": Vector2.UP,
				"pie": { 1: [Vector2(430, 120), Vector2(450, 110), Vector2(470, 120)] },
				"pie_queue": [Vector2(470, 120)], "pie_side": 1, "pie_sides": 2,
				"seen_fraction": 0.4,
				"ready_left": 2.0, "ready_total": 5.0, "follow_left": -1.0, "follow_total": 3.0,
				"hold_left": 1.0, "hold_total": 4.0,
				"watch": [], "covering": "", "sweep": [], "rear_spot": Vector2.ZERO,
			},
		}
