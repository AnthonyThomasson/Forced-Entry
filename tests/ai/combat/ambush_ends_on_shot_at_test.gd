extends GameTest
## D18 (`docs/leadership.md`, LD15): an ambush ends on first contact, and being shot at is contact.
## The order ends `done` when the ambusher sees a hostile anywhere, or is hit or shot at
## (`under_fire`), wherever the shots come from; footsteps and callouts do not end it. It radios
## `done` and decides without it (a member of a squad bound as a match's: it follows its leader
## again, LD19).
##
## The doorway is the Terrace house's hall / living room doorway (`door_150_360`), ambushed from the
## living room, as in `ambush_door_post_test.gd`: the one Terrace doorway with a post hidden from
## every slot and pie step of an entry by it. A defender in the living room is ordered (by its
## squad's leader, a household puppet in the kitchen standing in for the human leader; the squad
## built and bound as a match's, `s.squads`) to ambush it. Once it holds its post, an
## intruder puppet walks along the east end of the hall, behind the living room's south wall and out
## of the ambusher's sight (premise, required each frame): its footsteps do not end the order. Then
## the intruder, still in the hall and still unseen (required each frame through the shots), fires
## real pistol rounds at the hall face of the living room's south wall straight below the post: each
## round flies the projectile's own path and strikes the wall within the ambusher's
## `hit_awareness_radius` (its tracer, impact and gunshot seen and heard in the window), not through
## the doorway: the order ends `done`, not before the first shot, and its next decision holds no
## order.
##
## Scripted Von (the first option offered): what the ambusher decides after the order is not under
## test, only that it decides without it. The intruder is unkillable and holds a pistol.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const OrderBrain := preload("res://tests/_ai/order_brain_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
## The click that orders the ambush: in the living room, on the doorway's axis.
const CLICK := Vector2(150, 330)
## The intruder's walk along the hall's east end, behind the living room's south wall.
const HALL_EAST := Vector2(800, 430)
const HALL_MID := Vector2(520, 430)
## How long (s) the posted ambusher is watched holding before the shots.
const HOLD := 3.0
## The living room's south wall (the hall's north one), whose hall face the rounds strike.
const SOUTH_WALL_Y := 360.0
## The intruder's shots: how many, and the time (s) between them.
const SHOTS := 3
const SHOT_GAP := 0.4


func describe() -> Dictionary:
	return {
		"name": "An ambush ends when the ambusher is shot at, not on footsteps",
		"description": "A defender ambushing the hall doorway from the living room holds through "
			+ "an unseen intruder's footsteps; gunfire landing beside it ends the order done and "
			+ "it decides without it (D18).",
		"tags": ["ai", "combat", "leadership", "order", "ambush", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_script([])
	# Every round that arrives lands: none flies over cover.
	s.switch(&"projectile.flyover", false)
	s.actor(&"a", &"defender", Vector2(240, 150), { "max_health": 1_000_000.0 })
	s.actor(&"lead", &"puppet", Vector2(700, 120), { "faction": &"household" })
	s.actor(
		&"intruder",
		&"puppet",
		HALL_EAST,
		{ "faction": &"invader", "max_health": 1_000_000.0, "start_slot": 3 },
	)
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	var brain := await _take_post(t, a)
	if brain == null:
		return
	if not await _holds_through_footsteps(t, a, brain):
		return
	await _ends_on_shots(t, a, brain)


func _take_post(t: TestContext, a: Node) -> Node:
	var squad: Node = t.world.squad(&"household")
	await t.seconds(0.5)
	var order := Order.issue(squad, { "kind": Order.AMBUSH, "to": [a], "pos": CLICK })
	if not t.require(
			not order.is_empty(),
			"the squad posts the ambush order (issue of kind ambush returned %s)" % str(order),
	):
		return null
	var brain := OrderBrain.brain(t, &"a")
	if not t.require(
			await t.until(func(): return OrderBrain.primitive(brain) == "ambush", 5.0),
			"the defender takes the ambush (primitive %s)" % OrderBrain.primitive(brain),
	):
		return null
	if not t.require(
			await t.until(func(): return not Order.progress(t, "in_position", a).is_empty(), 20.0),
			"it reaches its post and radios in_position",
	):
		return null
	return brain


func _holds_through_footsteps(t: TestContext, a: Node, brain: Node) -> bool:
	var intruder := t.puppet(&"intruder")
	var intruder_node := t.actor(&"intruder")
	intruder.walk_to(HALL_MID)
	var seen := false
	var end := t.time + HOLD
	while t.time < end:
		seen = seen or GrenadeAi.line_clear(t, a.global_position, intruder_node.global_position)
		await t.frames(1)
	if not t.require(
			not seen,
			"the intruder walks the hall out of the ambusher's sight (premise: no clear line from "
				+ "the post)",
	):
		return false
	t.check(
		Order.progress(t, "done", a).is_empty() and OrderBrain.primitive(brain) == "ambush",
		"footsteps out of sight do not end the ambush (primitive %s, done %d)"
			% [OrderBrain.primitive(brain), Order.progress(t, "done", a).size()],
	)
	return true


func _ends_on_shots(t: TestContext, a: Node, brain: Node) -> void:
	t.puppet(&"intruder").aim_at(Vector2(a.global_position.x, SOUTH_WALL_Y))
	await t.seconds(0.5)
	# Counted before the shots: a follower's next decision (FOLLOW, LD19) can land on the frame it
	# radios done.
	var before := OrderBrain.decisions(brain)
	var shot_at := await _fire_unseen(t, a)
	if shot_at < 0.0:
		return
	t.check(
		not Order.progress(t, "done", a).is_empty(),
		"shot at, the ambusher radios its order done",
	)
	var dones := Probe.raw(
		t,
		&"callout",
		func(d): return d.get("speaker") == a and String(d.get("order_step", "")) == "done",
	)
	if not dones.is_empty():
		t.check(
			float(dones[0]["time"]) >= shot_at,
			"not before the shots (shots at %.2f s, done at %.2f s)"
				% [shot_at, float(dones[0]["time"])],
		)
	var ends := func():
		return (OrderBrain.decisions(brain) > before
				and not OrderBrain.ordered(brain)
				and not OrderBrain.on_order(brain))
	t.check(
		await t.until(ends, 4.0),
		"its next decision holds no order (ordered %s, act %s)"
			% [str(OrderBrain.ordered(brain)), brain.current_act()],
	)


## Fires the intruder's SHOTS from where it stands, aimed at the south wall's hall face below the
## post, until the ambusher radios done or a while after the last; requires that the ambusher never
## has a clear line to the intruder meanwhile and that a round left the barrel. The time of the
## first shot, or -1 when a premise failed.
func _fire_unseen(t: TestContext, a: Node) -> float:
	var intruder := t.puppet(&"intruder")
	var intruder_node := t.actor(&"intruder")
	var seen := false
	var fired := 0
	var next_shot := t.time
	var end := t.time + SHOTS * SHOT_GAP + 3.0
	while t.time < end and Order.progress(t, "done", a).is_empty():
		seen = seen or GrenadeAi.line_clear(t, a.global_position, intruder_node.global_position)
		if fired < SHOTS and t.time >= next_shot:
			intruder.shoot()
			fired += 1
			next_shot = t.time + SHOT_GAP
		await t.frames(1)
	if not t.require(
			not seen,
			"the intruder shoots from the hall out of the ambusher's sight (premise: no clear line "
				+ "from the post)",
	):
		return -1.0
	var shots := Probe.raw(t, &"shot", func(d): return d.get("attacker") == intruder_node)
	if not t.require(not shots.is_empty(), "the intruder fires real rounds"):
		return -1.0
	return float(shots[0]["time"])
