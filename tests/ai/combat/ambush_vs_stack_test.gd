extends GameTest
## LD15 (`docs/leadership.md`): an ambushed doorway against a real stack. An ambusher holds a post
## off the doorway's axis, unseen from the stack's slots and pie steps, crouched, gun on the
## threshold; the stack slices the pie and sees nothing, and the first of them to step into the
## fatal funnel is shot by the ambusher before any of them fires.
##
## The doorway is the Terrace house's hall / living room doorway (`door_150_360`), ambushed from the
## living room, the stack coming from the hall: the one Terrace doorway with a post hidden from
## every slot and pie step of an entry by it (`ambush_door_post_test.gd` says why). Two invaders
## stand at the west end of the hall, by the living room's doorway: it is a short route into a room
## they have not searched, the kitchen's doorway a medium one (the front door leads out), so
## entering it together is their natural pick (measured with the real Von and a puppet walking to an
## east post in the living room: both claim this doorway within half a second, and the point goes in
## about 3 s in; with the second invader 80 px farther east it splits off to the kitchen). A
## defender in the east of the living room is ordered at once by its squad's leader (a household
## puppet in the kitchen's far corner, out of the invaders' sight) to ambush that doorway from the
## living room: from the hall the stack sees only the west of the living room through the doorway,
## so its walk to an east post (the stand-in puppet's took 0.6 s) is out of their sight. Nobody is
## scripted and the rest of the AI is on: real Von at every level for the invaders and for the
## defender once its order ends.
##
## Required first (a set-up finding otherwise): both invaders claim slots at that doorway, the
## defender radios `in_position` at its post before the point radios `going_in`, and someone goes
## in. Then: the defender fires before any invader does, its first shot is at the first to go in
## (its facing on them), and that one is in the doorway's funnel when it is shot.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const IDS := [&"a", &"b"]
const DOOR := Entry.HALL_LIVING
## The click that orders the ambush: in the living room, on the doorway's axis.
const CLICK := Vector2(150, 330)
## The defender's facing within this of the entrant (dot of the facing with the direction to them)
## is a shot at them.
const AT_DOT := 0.9


func describe() -> Dictionary:
	return {
		"name": "An ambusher shoots the first of a real stack to step into the doorway, before any "
			+ "of them fires",
		"description": "A defender ambushing the hall doorway from the living room is posted "
			+ "before a real two-invader stack from the hall goes in; it fires first, at the "
			+ "entrant, while the entrant is in the funnel (LD15).",
		"tags": ["ai", "combat", "entry", "leadership", "order", "ambush", "von"],
		"requires_von": true,
		"timeout": 100.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", Vector2(230, 430))
	s.actor(&"b", &"invader", Vector2(200, 445))
	s.actor(&"d", &"defender", Vector2(430, 220))
	s.actor(&"lead", &"puppet", Vector2(810, 40), { "faction": &"household" })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var invaders: Array = IDS.map(func(id): return t.actor(id))
	var squad: Node = t.world.squad(&"household")
	var order := Order.issue(squad, { "kind": Order.AMBUSH, "to": [d], "pos": CLICK })
	if not t.require(
			not order.is_empty(),
			"the squad posts the ambush order (issue of kind ambush returned %s)" % str(order),
	):
		return

	var d_shot := func(): return t.happened(&"shot", func(e): return e.get("attacker") == d)
	var stop := func():
		return (d_shot.call()
				or not invaders.all(func(n): return is_instance_valid(n) and n.health > 0.0))
	var samples := await Entry.watch(t, IDS + [&"d"], DOOR, 85.0, stop)
	var acts := ", ".join((IDS + [&"d"]).map(
		func(id): return "%s %s" % [id, Order.brain(t, id).current_act()],
	))
	if not t.require(
			IDS.all(func(id): return Entry.first_call_time(t, "claim", id, DOOR["id"]) < INF),
			"both invaders chose the living room's hall doorway (claims there; %s)" % acts,
	):
		return
	var point := _point_went_in(t, d, acts)
	if point == &"":
		return
	if not t.check(d_shot.call(), "the ambusher fires (%s)" % acts):
		return
	_check_first_shot(t, d, invaders, samples, point)


## The point, the first invader to radio going in, with its going in and the defender's post
## before it required; &"" when one fails.
func _point_went_in(t: TestContext, d: Node, acts: String) -> StringName:
	var going_at := INF
	var point: StringName = &""
	for id in IDS:
		var at := Entry.first_call_time(t, "going_in", id, DOOR["id"])
		if at < going_at:
			going_at = at
			point = id
	if not t.require(going_at < INF, "the point radioed going in (%s)" % acts):
		return &""
	var posted := _progress_time(t, "in_position", d)
	if not t.require(
			posted < going_at,
			("the defender was posted (in_position) before the point went in (posted %.2f s, going "
					+ "in %.2f s)") % [posted, going_at],
	):
		return &""
	return point


## The defender's first shot: before the stack's, its facing on the point, the point in the
## funnel.
func _check_first_shot(
		t: TestContext,
		d: Node,
		invaders: Array,
		samples: Array,
		point: StringName,
) -> void:
	var d_first := float(Probe.raw(t, &"shot", func(e): return e.get("attacker") == d)[0]["time"])
	var theirs := Probe.raw(t, &"shot", func(e): return invaders.has(e.get("attacker")))
	t.check(
		theirs.is_empty() or float(theirs[0]["time"]) > d_first,
		"it fires first (its first shot %.2f s, the stack's %s)"
			% [d_first, "none" if theirs.is_empty() else "%.2f s" % float(theirs[0]["time"])],
	)
	var at_shot := _sample_at(samples, d_first)
	var p: Vector2 = at_shot["pos"].get(point, Vector2.INF)
	var dp: Vector2 = at_shot["pos"].get(&"d", Vector2.INF)
	var facing: Vector2 = at_shot["facing"].get(&"d", Vector2.ZERO)
	t.check(
		p != Vector2.INF and facing.normalized().dot((p - dp).normalized()) >= AT_DOT,
		"at the first to go in, %s (facing %s, %s at %s)"
			% [point, str(facing.normalized()), point, str(p.round())],
	)
	t.check(
		p != Vector2.INF and Entry.in_funnel(DOOR, p),
		("who is in the doorway's funnel when shot (%s at %s, %.0f px out of the wall plane, %.0f "
				+ "px along it)")
			% [point, str(p.round()), Entry.outward(DOOR, p), Entry.lateral(DOOR, p)],
	)


## The time of `who`'s first `order_step` `step` callout, or INF.
func _progress_time(t: TestContext, step: String, who: Node) -> float:
	var calls := Probe.raw(
		t,
		&"callout",
		func(e): return e.get("speaker") == who and String(e.get("order_step", "")) == step,
	)
	return float(calls[0]["time"]) if not calls.is_empty() else INF


## The watch sample nearest time `at`.
func _sample_at(samples: Array, at: float) -> Dictionary:
	var best: Dictionary = { "pos": {}, "facing": {} }
	var gap := INF
	for s: Dictionary in samples:
		if absf(float(s["t"]) - at) < gap:
			gap = absf(float(s["t"]) - at)
			best = s
	return best
