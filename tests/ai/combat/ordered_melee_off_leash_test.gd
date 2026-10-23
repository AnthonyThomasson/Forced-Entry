extends GameTest
## LD23's leash binds only a follower holding no order: a member carrying one fights where the order
## takes it, closing on its contact too (`Combat.melee`), whatever the distance to its leader. A
## puppet stands in for the human leader of a squad of one invader NPC (bound as Main binds it), at
## the far end of an open hall, more than two leashes away; the NPC, ordered to defend the hall
## (`defend_room`, the arena's one room), has a dry gun and no spare magazine, so only its fists and
## feet. A household gunman stands in plain sight down the hall, out of reach and farther from the
## leader than the leash, and fires at the NPC every 1.4 s (it aims for 0.4 s, then fires). Under
## fire, the NPC fights it and closes on it to strike: a leash would hold it where it stands, since
## the gunman is off it, and it would never land a blow.
##
## Real Von, the whole pipeline; no switch. Premises: nobody is killed (`max_health`), and the
## gunman, a puppet, never moves.

const Follow := preload("res://tests/_ai/follow_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const HALL := Rect2(0, 0, 1700, 900)
## The leader: at the hall's west end, some 750 px from the NPC.
const LEAD_AT := Vector2(150, 450)
const NPC_AT := Vector2(900, 450)
## The gunman: 220 px east of the NPC, out of punching reach.
const GUNMAN_AT := Vector2(1120, 450)
## How long (s) the NPC has to land a blow once it holds the order.
const WATCH_S := 15.0


func describe() -> Dictionary:
	return {
		"name": "An ordered member closes on a contact beyond its leader's leash",
		"description": "Ordered to defend the hall, far from its human leader, with only its fists "
			+ "and feet, an invader shot at closes on the gunman off the leash and strikes it: "
			+ "the leash does not bind a member holding an order (LD23).",
		"tags": ["ai", "combat", "melee", "squad", "leash", "order", "leadership", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(HALL)
	Stack.human(s, &"me", LEAD_AT, { "aim_point": GUNMAN_AT })
	s.actor(
		&"m",
		&"invader",
		NPC_AT,
		{
			"max_health": 1_000_000.0,
			"start_slot": 2,
			"start_rounds": 0,
			"spare_magazine_types": [],
		},
	)
	s.actor(
		&"gunman",
		&"puppet",
		GUNMAN_AT,
		{ "faction": &"household", "max_health": 1_000_000.0, "start_slot": 3 },
	)
	s.squads({ "human": &"me" })


func run(t: TestContext) -> void:
	var squad := t.squad(&"invader")
	var me := t.actor(&"me")
	var m := t.actor(&"m")
	var gunman := t.actor(&"gunman")
	var puppet := t.puppet(&"gunman")
	var b := Order.brain(t, &"m")
	if not t.require(
			GUNMAN_AT.distance_to(LEAD_AT) > squad.leash,
			"premise: the gunman stands off the leader's leash (%.0f px, leash %.0f)"
				% [GUNMAN_AT.distance_to(LEAD_AT), squad.leash],
	):
		return
	Order.issue(squad, { "kind": Order.DEFEND, "to": [m], "room": "arena" })
	if not t.require(
			await t.until(func(): return Order.on_order(b), 5.0),
			"premise: the NPC takes the order to defend the hall (act %s)" % b.current_act(),
	):
		return
	var struck := func(d):
		return d["actor"] == &"m" and d["body"] == gunman and int(d["hand"]) >= 0
	var next_shot := [t.time]
	var each := func(_rec: Dictionary) -> void:
		if t.time >= float(next_shot[0]):
			puppet.aim_at(m)
			if t.time >= float(next_shot[0]) + 0.4:
				puppet.shoot()
				next_shot[0] = t.time + 1.0
	var w: Dictionary = await Follow.watch(
		t,
		[me, m],
		squad,
		WATCH_S,
		func(_rec): return t.happened(&"hit_landed", struck),
		each,
	)
	if not t.require(
			t.happened(&"hit", func(d): return d.get("attacker") == gunman),
			"premise: the gunman's rounds landed (the NPC was under fire)",
	):
		return
	if not t.require(
			Follow.took(w, m, "combat"),
			"the ordered NPC fights the gunman (acts %s)" % Follow.acts_of(w, m),
	):
		return
	t.check(
		t.happened(&"hit_landed", struck),
		"it closes on the gunman off the leash and strikes it (it ends %.0f px from it, %.0f "
			% [
				m.global_position.distance_to(gunman.global_position),
				m.global_position.distance_to(me.global_position),
			] + "px from its leader; acts %s)" % Follow.acts_of(w, m),
	)
