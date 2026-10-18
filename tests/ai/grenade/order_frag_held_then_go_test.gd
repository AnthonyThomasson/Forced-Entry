extends GameTest

## LD13 x LD14 (`docs/leadership.md`): a frag stack held for go. A held stack holds before the bang as before the pie: no bang call and no
## throw until Go; after the Go the entry runs as a go-when-ready frag stack (the throw, the burst, the crossing).
##
## Two invaders, each carrying one frag, are ordered to stack on the Terrace house's back door from its north side with a frag, hold for
## go. They form and are ready; for 10 s nobody calls the bang, throws or crosses. The leader's Go is then posted through the squad: a frag
## is thrown into the kitchen, goes off, and the point goes in after it.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone. Premise: both are armed with one frag
## the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Bang := preload("res://tests/_ai/bang_probe.gd")

const IDS := [&"a", &"b"]
## How long (s) the held stack is watched not throwing once both are ready.
const HOLD := 10.0


func describe() -> Dictionary:
	return {
		"name": "A held frag stack throws only after the go",
		"description": "Two invaders ordered to stack on the back door with a frag, hold for go: no bang call, throw or crossing while held; after the go a frag goes off in the kitchen and the point goes in (LD13, LD14).",
		"tags": ["ai", "grenade", "entry", "leadership", "order", "frag", "scripted"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.von_down()
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	Bang.stack(s)
	s.actor(&"lead", &"puppet", Vector2(1250, 600), { "faction": &"invader" })


func run(t: TestContext) -> void:
	var door: String = Entry.BACK["id"]
	for id in IDS:
		Probe.arm(t.actor(id), 0, 1)
	if not t.require(IDS.all(func(id): return Probe.count(t.actor(id), Probe.FRAG) == 1), "both invaders carry a frag (premise: Character.item_count(8))"):
		return
	var squad := Order.raid(t, IDS, &"lead")
	if not t.require(squad != null, "the squad script exists (%s)" % Order.SQUAD_SCRIPT):
		return
	await t.seconds(0.3)
	var order := Order.stack_order(squad, IDS.map(func(id): return t.actor(id)), Order.BACK_NORTH, "frag", true)
	if not t.require(not order.is_empty(), "the squad posts the held frag stack order (issue)"):
		return
	if not t.require(await t.until(func(): return Order.all_called(t, IDS, "ready", door), 30.0), "the stack forms: both radio ready"):
		return

	var acted := func(): return t.happened(&"throw") or not Entry.calls(t, "bang").is_empty() or not Entry.calls(t, "going_in").is_empty()
	var early := await t.until(acted, HOLD)
	t.check(not early, "while held nobody calls the bang, throws or goes in (bang calls %d, throws %d, going_in %d)" % [
		Entry.calls(t, "bang").size(), t.events_of(&"throw").size(), Entry.calls(t, "going_in").size()])
	if early:
		return

	var go := Order.go(squad, Order.BACK_NORTH)
	if not t.require(not go.is_empty(), "the leader's go is posted (issue of kind go returned %s)" % str(go)):
		return
	var go_at := t.time
	t.check(await Probe.wait_boom(t, &"frag", 20.0), "after the go a frag goes off")
	var frag_throws := Probe.raw(t, &"throw", func(d): return d.get("kind") == &"frag")
	t.check(not frag_throws.is_empty() and float(frag_throws[0]["time"]) >= go_at, "thrown after the go (go at %.2f s, throws at %s)" % [go_at, str(frag_throws.map(func(e): return snappedf(float(e["time"]), 0.01)))])
	var booms := Probe.booms(t, &"frag")
	if not booms.is_empty():
		t.check(Maps.HOUSE_KITCHEN.has_point(booms[0]["data"]["position"]), "into the kitchen (%s)" % str((booms[0]["data"]["position"] as Vector2).round()))
	t.check(await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), 10.0), "and the point goes in after it")
