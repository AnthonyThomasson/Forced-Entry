extends GameTest

## LD14 / D16 (`docs/leadership.md`): frag entry. A stack ordered with `mode: "frag"` has its frag carrier (the second of the stack if it
## carries one, else the lowest slot that does; picked as a stun thrower is) lob a frag into the room from beside the door, then everyone
## holds its slot until the burst; the throw is planned so that no claimed slot, nor the thrower's own, has a clear line to the burst within
## the frag's danger zone (`danger_radius` + `evade_margin`, the G16 zone: the wall shields the stack). On the burst in the room the stack
## is over the bang: the point crosses at once, with no pie.
##
## Two invaders, each carrying one frag, are ordered to stack on the Terrace house's back door, from its north side, with a frag. The
## kitchen behind it is where such a landing exists: a burst on the doorway's axis deep in the room (the plan's 0.85 / 0.7 / 0.55 of its
## 360 px) is out of line of every slot beside the door, since each line to it runs into the jamb, while the room is shallower than the
## frag's 370 px zone, so the wall is what keeps the stack safe. The test checks this with its own rays (walls and tall pieces, characters
## looked through) at the burst, not the plan's code.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone. Premise: both are armed with one frag
## the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Bang := preload("res://tests/_ai/bang_probe.gd")

const IDS := [&"a", &"b"]
## How soon (s) after the burst the point crosses: at once, a step's time.
const CROSS_WITHIN := 1.5


func describe() -> Dictionary:
	return {
		"name": "An ordered frag stack throws into the room and crosses on the burst",
		"description": "Two invaders ordered to stack on the back door with a frag: the second throws into the kitchen, nobody in the stack has a clear line to the burst within its danger zone, and the point crosses on the burst with no pie (LD14, D16).",
		"tags": ["ai", "grenade", "entry", "leadership", "order", "frag", "scripted"],
		"timeout": 60.0,
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
	var order := Order.stack_order(squad, IDS.map(func(id): return t.actor(id)), Order.BACK_NORTH, "frag", false)
	if not t.require(not order.is_empty(), "the squad posts the frag stack order (issue)"):
		return
	t.check(String(order.get("mode", "")) == "frag", "the order's mode is frag (%s)" % str(order.get("mode")))
	var claimed := func(): return IDS.all(func(id): return not Order.ordered_claims(t, t.actor(id), door).is_empty())
	if not t.require(await t.until(claimed, 10.0), "both claim the back door under the order (claims carrying order_id)"):
		return

	# Watch each member's place and entry phase every frame until the point goes in.
	var samples: Array = []
	var phases := {}
	for id in IDS:
		phases[id] = []
	while Entry.calls(t, "going_in").is_empty() and t.time < 50.0:
		var row := { "t": t.time, "pos": {} }
		for id in IDS:
			row["pos"][id] = t.actor(id).global_position
			var ph := String(Entry.entry(Entry.brain(t, id)).get("phase", ""))
			if not phases[id].has(ph):
				phases[id].append(ph)
		samples.append(row)
		await t.frames(1)

	var frag_throws := t.events_of(&"throw", func(d): return d.get("kind") == &"frag")
	if not t.check(not frag_throws.is_empty(), "a frag was thrown (throws %s; bang_off radioed: %s)" % [
			str(t.events_of(&"throw").map(func(d): return d.get("kind"))),
			str(IDS.filter(func(id): return Entry.calls(t, "", id).any(func(c): return c.get("bang_off") == true)))]):
		return
	var thrower = frag_throws[0].get("attacker")
	var second: StringName = Order.by_slot(t, IDS, door)[1]
	t.check(thrower == t.actor(second), "the second of the stack threw it (%s, slot 2 is %s)" % [thrower.name if thrower is Node else str(thrower), second])
	var booms := Probe.booms(t, &"frag")
	if not t.check(not booms.is_empty(), "the frag went off"):
		return
	var burst: Vector2 = booms[0]["data"]["position"]
	var burst_at := float(booms[0]["time"])
	t.check(Maps.HOUSE_KITCHEN.has_point(burst), "in the kitchen (%s)" % str(burst.round()))
	for id in IDS:
		var p := _pos_at(samples, id, burst_at)
		var safe := p.distance_to(burst) >= Probe.FRAG_ZONE or not Probe.line_clear(t, burst, p)
		t.check(safe, "%s had no clear line to the burst within its danger zone (%.0f px away at %s, line %s)" % [
			id, p.distance_to(burst), str(p.round()), "clear" if Probe.line_clear(t, burst, p) else "blocked"])
	if not t.check(not Entry.calls(t, "going_in").is_empty(), "the point goes in"):
		return
	var going := Order.first_time(t, &"callout", func(d): return String(d.get("entry_step", "")) == "going_in")
	t.check(going >= burst_at and going - burst_at <= CROSS_WITHIN, "the point crosses on the burst (burst at %.2f s, going in at %.2f s)" % [burst_at, going])
	for id in IDS:
		t.check(not phases[id].has("pie"), "%s sliced no pie (phases %s)" % [id, str(phases[id])])


## Where actor `id` stood at the first sample at or after `at` (the last sample when none is that late).
func _pos_at(samples: Array, id: StringName, at: float) -> Vector2:
	for s in samples:
		if float(s["t"]) >= at:
			return s["pos"][id]
	return samples.back()["pos"][id] if not samples.is_empty() else Vector2.INF
