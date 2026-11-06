extends GameTest
## AC8 (#192): the arrival filter drops only hits beyond both hearing radii (unless they hit this
## NPC) and callouts beyond radio range. Each case is also handed to the existing late classifier:
## an arrival drop must be a late no-op, while events ignored late for another reason still arrive.

const HEARING := 900.0
const HIT_AWARENESS := 160.0
const CALLOUT_RANGE := 1500.0
const DROP := 0
const KEEP := 1
const KEEP_LATE_NOOP := 2


func describe() -> Dictionary:
	return {
		"name": "Early hit and callout filtering matches late classification",
		"description": "Only hits outside both radii and not on the listener, and callouts outside "
			+ "radio range, are dropped on arrival; every dropped event is a late no-op.",
		"tags": ["ai", "perception", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2400, 500))
	s.von_down()
	s.switch(&"ai.hostile_on_sight", false)
	s.actor(&"listener", &"invader", Vector2(100, 250), { "movement:speed": 0.0 })
	s.actor(&"shooter", &"puppet", Vector2(300, 250), { "faction": &"household" })
	s.actor(&"ally", &"puppet", Vector2(400, 250), { "faction": &"invader" })


func run(t: TestContext) -> void:
	await t.frames(2)
	var brain := t.controller(&"listener", &"debug_state")
	if not t.require(brain != null, "the listener has a goal controller"):
		return
	var listener := t.actor(&"listener")
	var perception: Node = brain.get("_perception")
	var memory: RefCounted = perception.get("_memory")
	var comms: RefCounted = brain.get("_comms")
	var cases := _cases(listener, t.actor(&"shooter"), t.actor(&"ally"))
	for case: Dictionary in cases:
		var before: int = memory.size()
		if case["topic"] == &"hit":
			perception.hearing.process_hit(case["data"])
		else:
			perception.hearing.process_callout(case["data"])
		var late_ignored: bool = memory.size() == before
		t.check(
			late_ignored == (case["outcome"] != KEEP),
			"premise: late classification ignores %s: %s" % [case["outcome"] != KEEP, case["name"]],
		)
		EventBus.post(case["topic"], case["data"])
		var arrived: bool = comms.event_queue.any(
			func(ev: Array) -> bool: return ev[0] == case["topic"] and ev[1] == case["data"]
		)
		t.check(
			arrived == (case["outcome"] != DROP),
			"%s: arrival kept %s" % [case["name"], arrived],
		)
		comms.event_queue.clear()


func _cases(listener: Node, shooter: Node, ally: Node) -> Array[Dictionary]:
	var origin: Vector2 = listener.global_position
	return [
		_hit("a hit beyond both radii", shooter, null, origin + Vector2(2000, 0), DROP),
		_hit("the listener's own distant hit", listener, null, origin + Vector2(2000, 0), DROP),
		_hit("a hit at hearing range", shooter, null, origin + Vector2(HEARING, 0), KEEP),
		_hit("a distant hit on the listener", shooter, listener, origin + Vector2(2000, 0), KEEP),
		_hit(
			"a shot that makes the shooter hostile", shooter, null,
			origin + Vector2(HIT_AWARENESS, 0), KEEP,
		),
		_hit(
			"a known hostile's farther shot still arrives", shooter, null,
			origin + Vector2(500, 0), KEEP_LATE_NOOP,
		),
		_hit(
			"an ally's near hit still arrives", ally, null,
			origin + Vector2(HIT_AWARENESS, 0), KEEP_LATE_NOOP,
		),
		_callout(
			"a callout beyond radio range",
			ally,
			origin + Vector2(CALLOUT_RANGE + 1, 0),
			false,
		),
		_callout("a callout at radio range", ally, origin + Vector2(CALLOUT_RANGE, 0), true),
	]


func _hit(label: String, attacker: Node, victim: Node, at: Vector2, outcome: int) -> Dictionary:
	return {
		"name": label,
		"topic": &"hit",
		"data": {
			"attacker": attacker, "victim": victim, "position": at, "direction": Vector2.RIGHT,
		},
		"outcome": outcome,
	}


func _callout(label: String, speaker: Node, at: Vector2, kept: bool) -> Dictionary:
	return {
		"name": label,
		"topic": &"callout",
		"data": {
			"speaker": speaker, "faction": speaker.faction, "position": at,
			"status": "hold", "path": "", "label": label,
		},
		"outcome": KEEP if kept else DROP,
	}
