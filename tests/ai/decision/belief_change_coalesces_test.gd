extends GameTest
## A change of the hostile salient key forces at most one decision per 0.5 s. A defender keeps a
## nearer hostile engaged and in sight while a second steps into view and behind a fridge faster
## than that. Changes inside an open window coalesce into one pending decision at its end.
##
## One mechanism, scripted Von (COMBAT > ENGAGE > from where it stands). The short contact memory
## makes a hidden hostile leave the known set quickly; the defender and puppets cannot move or die,
## so only the second hostile's sightings change the salient key.

const ENGAGED_AT := Vector2(400, 100)
const OPEN_AT := Vector2(650, 100)
const HIDDEN_AT := Vector2(650, 250)
const STEP := 0.18


func describe() -> Dictionary:
	return {
		"name": "Hostile belief changes coalesce into one pending decision",
		"description": "A non-engaged hostile enters and leaves contact memory every 0.18 s: "
			+ "belief-forced decisions are at least 0.5 s apart, and a last change inside the "
			+ "window still starts one when it ends.",
		"tags": ["ai", "decision", "combat", "scripted"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.object(&"fridge", "fridge", Vector2(400, 250))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }, { "pick": "fire_here" }])
	s.switch(&"ai.callouts", false)
	s.actor(
		&"d",
		&"defender",
		Vector2(150, 250),
		{ "movement:speed": 0.0, "facing": Vector2.RIGHT },
	)
	s.set_props(
		&"d",
		"GoalController",
		{
			"tuning:decision:decide_interval": 30.0,
			"tuning:decision:tactic_interval": 30.0,
			"tuning:memory:contact_ttl": 0.12,
		},
	)
	for pair in [[&"engaged", ENGAGED_AT], [&"mover", OPEN_AT]]:
		s.actor(
			pair[0],
			&"puppet",
			pair[1],
			{ "faction": &"invader", "max_health": 1_000_000.0 },
		)


func run(t: TestContext) -> void:
	var brain := t.controller(&"d", &"debug_state")
	if not t.require(
			await t.until(func(): return str(brain.current_act()).begins_with("combat/"), 5.0),
			"the defender engaged a hostile",
	):
		return
	if not t.require(
			int(brain.debug_state().get("engage_id", 0)) == t.actor(&"engaged").get_instance_id(),
			"set-up: the nearer, stationary hostile stays engaged",
	):
		return

	var belief_times: Array = []
	for leg in 8:
		t.actor(&"mover").global_position = HIDDEN_AT if leg % 2 == 0 else OPEN_AT
		await _watch(t, brain, STEP, belief_times)
	if not t.require(
			belief_times.size() >= 3 and _known(brain, &"engaged"),
			"set-up: repeated sightings changed belief while the engaged contact stayed known",
	):
		return
	var gaps := _gaps(belief_times)
	t.check(
		not gaps.any(func(gap): return gap < 0.49),
		"belief-forced decisions are at least 0.5 s apart (gaps %s)" % [gaps],
	)
	await _check_pending(t, brain, belief_times)


## End the fixture with one appearance and disappearance inside a window, then no more changes.
func _check_pending(t: TestContext, brain: Node, belief_times: Array) -> void:

	# One last appearance and disappearance, both inside the latest window, then no more changes.
	t.actor(&"mover").global_position = OPEN_AT
	if not t.require(await t.until(func(): return _known(brain, &"mover"), 0.4),
			"the mover became known once more"):
		return
	_record(brain, belief_times)
	t.actor(&"mover").global_position = HIDDEN_AT
	if not t.require(await t.until(func(): return not _known(brain, &"mover"), 0.4),
			"the mover's last sighting expired inside the window"):
		return
	_record(brain, belief_times)
	var before: int = belief_times.size()
	var previous: float = belief_times[-1]["at"]
	var fired := await t.until(func():
		_record(brain, belief_times)
		return belief_times.size() > before, 0.7)
	if not t.require(fired, "the coalesced change fired when its window ended"):
		return
	var delay: float = belief_times[-1]["at"] - previous
	t.check(
		delay >= 0.49 and delay <= 0.65,
		"the pending decision fired at the 0.5 s window's end (after %.3f s)" % delay,
	)


## Watch for decision starts on every physics frame, recording GameClock seconds for belief ones.
func _watch(t: TestContext, brain: Node, seconds: float, times: Array) -> void:
	var end := t.time + seconds
	while t.time < end:
		await t.frames(1)
		_record(brain, times)


func _record(brain: Node, times: Array) -> void:
	var state: Dictionary = brain.debug_state()
	var decisions := int(state.get("decisions", 0))
	if not times.is_empty() and times[-1]["decisions"] == decisions:
		return
	if str(state.get("decision_reason", "")) == "hostile belief changed":
		times.append({ "at": GameClock.msec() / 1000.0, "decisions": decisions })


func _gaps(times: Array) -> Array:
	var out: Array = []
	for i in range(1, times.size()):
		out.append(snappedf(times[i]["at"] - times[i - 1]["at"], 0.001))
	return out


func _known(brain: Node, id: StringName) -> bool:
	return (brain.debug_state().get("contacts", []) as Array).any(
		func(c): return str(c.get("name", "")) == str(id)
	)
