extends GameTest
## LD13 / D12 (`docs/leadership.md`): no leader to say go. When the leader who gave a held stack
## order is dead (the `&"leader"` event, or `Squad.alive(order.leader)` false), the held stack
## becomes go-when-ready: it goes on the ready barrier, or at once if already ready.
##
## Two invaders are ordered (quiet, hold for go) by their leader, a puppet standing in for the
## human, to stack on the Terrace house's back door from its north side. They form and hold; 5 s
## later the leader is killed (`take_damage`), the squad passes the lead on, and the stack goes in
## on its own, with no go from anyone.
##
## The squad is built the way Main builds it (`Squad.setup`, `MatchBuilder.bind_squad`). Scripted
## Von, down: the members' own decisions hold steady, so what they do is the order's alone.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const IDS := [&"a", &"b"]
## How long (s) the held stack is watched not crossing before the leader dies.
const HOLD := 5.0
## How soon (s) after the leader's death the stack, already ready, goes in.
const GOES_WITHIN := 6.0


func describe() -> Dictionary:
	return {
		"name": "A held stack goes on its own once its leader is dead",
		"description": "Two invaders hold a stack on the back door for their leader's go; the "
			+ "leader is killed and the stack goes in by itself, with no go (LD13, D12).",
		"tags": ["ai", "entry", "leadership", "order", "squad", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.actor(&"a", &"invader", Vector2(960, 60))
	s.actor(&"b", &"invader", Vector2(985, 110))
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var door: String = Entry.BACK["id"]
	var squad := Order.raid(t, IDS, &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	if not t.require(
			Order.bind(IDS.map(func(id): return t.actor(id)), squad),
			"each NPC is handed its squad (MatchBuilder.bind_squad)",
	):
		return
	await t.seconds(0.3)
	var order := Order.stack_order(
		squad,
		IDS.map(func(id): return t.actor(id)),
		Order.BACK_NORTH,
		"quiet",
		true,
	)
	if not t.require(not order.is_empty(), "the squad posts the held stack order (issue)"):
		return
	if not t.require(
			await t.until(func(): return Order.all_called(t, IDS, "ready", door), 30.0),
			"the stack forms: both radio ready",
	):
		return
	var crossed := await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), HOLD)
	t.check(
		not crossed,
		"the stack holds while its leader lives (%s went in)"
			% str(Entry.calls(t, "going_in").map(func(c): return c.get("speaker").name)),
	)
	if crossed:
		return

	var gos := Order.orders(t).filter(
		func(o): return String(o.get("kind", "")) == Order.GO and o.get("auto") != true,
	).size()
	var lead := t.actor(&"lead")
	lead.take_damage(1.0e9)
	if not t.require(lead.is_dead, "the leader is dead"):
		return
	var died_at := t.time
	t.check(
		await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), GOES_WITHIN),
		"with no leader to say go, the ready stack goes in on its own within %.0f s" % GOES_WITHIN,
	)
	var going := Order.first_time(
		t,
		&"callout",
		func(d): return String(d.get("entry_step", "")) == "going_in",
	)
	t.check(
		going >= died_at,
		"after the leader's death (died at %.2f s, going in at %.2f s)" % [died_at, going],
	)
	t.expect_eq(
		Order.orders(t).filter(
			func(o): return String(o.get("kind", "")) == Order.GO and o.get("auto") != true,
		).size(),
		gos,
		"nobody gave a go",
	)
