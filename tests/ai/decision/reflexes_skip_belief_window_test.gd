extends GameTest
## Immediate decision reflexes do not wait for the hostile-belief window. Four isolated defenders
## each open a window with a non-engaged contact's loss, then respectively: know their first hostile
## while holding no target, lose the engaged contact, come under fire, and receive an order.
## Scripted Von isolates decision cadence. Short contact memory makes stepping behind a fridge a
## prompt belief change; all puppets are held and invulnerable so nothing else changes.

const Order := preload("res://tests/_ai/order_probe.gd")
const ROOM := Vector2(800, 400)
const STEP := Vector2(900, 0)
const NPC := Vector2(150, 250)
const ENGAGED := Vector2(400, 100)
const OPEN := Vector2(650, 100)
const HIDDEN := Vector2(650, 250)
const CASES := [&"first", &"lost", &"hit", &"order"]


func describe() -> Dictionary:
	return {
		"name": "Immediate reflexes skip an open hostile-belief window",
		"description": "First hostile known with no target, lost engaged contact, incoming fire "
			+ "and an order each start a decision on their tick inside an open belief window.",
		"tags": ["ai", "decision", "combat", "leadership", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	var rooms: Array = []
	for i in CASES.size():
		rooms.append({
			"key": "%s_room" % CASES[i], "type": "living_room", "rect": Rect2(STEP * i, ROOM),
		})
	s.layout(rooms)
	s.von_script([
		{ "pick": "idle" }, { "pick": "wait" }, { "pick": "combat" }, { "pick": "engage" },
		{ "pick": "fire_here" },
	])
	s.switch(&"ai.callouts", false)
	for i in CASES.size():
		_npc(s, CASES[i], STEP * i)
	for id in [&"first", &"hit"]:
		s.set_props(
			id,
			"GoalController",
			{
				"tuning:decision:pursue_hostiles": false,
				"tuning:decision:disabled_nodes": [&"combat"],
			},
		)


func _npc(s: TestSetup, id: StringName, at: Vector2) -> void:
	s.actor(id, &"defender", at + NPC, { "movement:speed": 0.0, "facing": Vector2.RIGHT })
	s.set_props(
		id,
		"GoalController",
		{
			"tuning:decision:decide_interval": 30.0,
			"tuning:decision:tactic_interval": 30.0,
			"tuning:memory:contact_ttl": 0.12,
		},
	)
	s.object(StringName("%s_fridge" % id), "fridge", at + Vector2(400, 250))
	if id != &"first":
		_hostile(s, StringName("%s_mover" % id), at + OPEN)
	if id in [&"lost", &"order"]:
		_hostile(s, StringName("%s_engaged" % id), at + ENGAGED)
	# The first-hostile case starts with nobody known; the mover is hidden by its fridge.
	if id == &"first":
		_hostile(s, &"first_mover", at + HIDDEN)


func _hostile(s: TestSetup, id: StringName, at: Vector2) -> void:
	s.actor(id, &"puppet", at, { "faction": &"invader", "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	await t.frames(3)
	await _first_known(t)
	await _lost_engaged(t)
	await _hit(t)
	await _ordered(t)


func _first_known(t: TestContext) -> void:
	var brain := t.controller(&"first", &"debug_state")
	var mover := t.actor(&"first_mover")
	if not t.require(int(brain.debug_state().get("engage_id", 0)) == 0, "first case has no target"):
		return
	# A hostile known and then forgotten with no fight adopted opens a window without a target.
	mover.global_position = Vector2(0, 0) + OPEN
	if not t.require(await t.until(func(): return _known(brain, &"first_mover"), 0.4),
			"first case initially knows its hostile"):
		return
	await t.seconds(0.55)  # Let the first-known window close before the window under test.
	await _open_window(t, &"first", mover)
	var before := int(brain.debug_state().get("decisions", 0))
	mover.global_position = OPEN
	if not t.require(await t.until(func(): return _known(brain, &"first_mover"), 0.4),
			"the first hostile becomes known inside the window"):
		return
	_check_immediate(
		t,
		brain,
		before,
		"hostile belief changed",
		"first hostile known with no target",
	)


func _lost_engaged(t: TestContext) -> void:
	var brain := t.controller(&"lost", &"debug_state")
	if not t.require(
			await t.until(func(): return str(brain.current_act()).begins_with("combat/"), 3.0),
			"lost-contact case adopted combat",
	):
		return
	await _open_window(t, &"lost", t.actor(&"lost_mover"))
	var before := int(brain.debug_state().get("decisions", 0))
	var engaged := t.actor(&"lost_engaged")
	engaged.global_position = Vector2(900, 0) + HIDDEN
	if not t.require(await t.until(func(): return not _known(brain, &"lost_engaged"), 0.4),
			"the engaged contact was lost inside the window"):
		return
	_check_immediate(t, brain, before, "lost the engaged contact", "lost engaged contact")


func _hit(t: TestContext) -> void:
	var brain := t.controller(&"hit", &"debug_state")
	await _open_window(t, &"hit", t.actor(&"hit_mover"))
	var before := int(brain.debug_state().get("decisions", 0))
	Order.gunfire_near(t.actor(&"hit"))
	await t.frames(1)
	_check_immediate(t, brain, before, "attacked", "incoming fire")


func _ordered(t: TestContext) -> void:
	var brain := t.controller(&"order", &"debug_state")
	await _open_window(t, &"order", t.actor(&"order_mover"))
	var before := int(brain.debug_state().get("decisions", 0))
	var npc := t.actor(&"order")
	Order.post({
		"id": "inside-window", "leader": npc, "faction": npc.faction, "to": [npc],
		"kind": Order.DEFEND, "room": "order_room",
	})
	await t.frames(1)
	_check_immediate(t, brain, before, "ordered", "an order")


## Hide a non-engaged hostile and require its loss to open a belief window; let that walk finish.
func _open_window(t: TestContext, id: StringName, mover: Node2D) -> void:
	var brain := t.controller(id, &"debug_state")
	var mover_id := StringName("%s_mover" % id)
	if not t.require(_known(brain, mover_id), "%s mover starts known" % id):
		return
	var before := int(brain.debug_state().get("decisions", 0))
	mover.global_position = Vector2(CASES.find(id) * 900, 0) + HIDDEN
	if not t.require(await t.until(func(): return not _known(brain, mover_id), 0.4),
			"%s mover's loss opened the window" % id):
		return
	if not t.require(int(brain.debug_state().get("decisions", 0)) == before + 1
			and str(brain.debug_state().get("decision_reason", "")) == "hostile belief changed",
			"%s loss forced the window-opening decision" % id):
		return
	await t.frames(2)


func _check_immediate(
	t: TestContext,
	brain: Node,
	before: int,
	reason: String,
	label: String,
) -> void:
	var state: Dictionary = brain.debug_state()
	t.check(int(state.get("decisions", 0)) == before + 1
			and str(state.get("decision_reason", "")) == reason,
		"%s started one decision on that tick (reason %s)"
			% [label, str(state.get("decision_reason", ""))])


func _known(brain: Node, id: StringName) -> bool:
	return (brain.debug_state().get("contacts", []) as Array).any(
		func(c): return str(c.get("name", "")) == str(id)
	)
