extends GameTest
## LD14 / D15 (`docs/leadership.md`): an ordered frag stack whose frags are gone. Two invaders, each
## carrying a frag when the order is given, are ordered to stack on the Terrace house's back door
## with a frag; their frags are then taken away before they reach the door. With no frag in the
## stack the stack goes in quietly and radios `bang_off`, and the order is still done at the cleared
## kitchen (as D1 for a stun).
##
## Part 1 already sends a stun stack with no stun in quietly
## (`ai/entry/order_stack_no_stun_goes_quiet`), so what this test adds is that the stack in question
## is a frag stack: its claims carry the order's mode, `order_mode: "frag"`, on the radio (the stack
## does not read a frag order as a stun one), and no grenade of any kind is thrown.
##
## Scripted Von, down: the members' own decisions hold steady, so what they do is the order's alone.
## Premises: both are armed with one frag the way Main arms a spawn, then re-armed with none
## (`LoadoutConfig.apply`, as a new loadout), standing in for a frag lost.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Bang := preload("res://tests/_ai/bang_probe.gd")
const IDS := [&"a", &"b"]


func describe() -> Dictionary:
	return {
		"name": "An ordered frag stack with no frag goes in quietly",
		"description": "Ordered to stack on the back door with a frag, two invaders whose frags "
			+ "are gone keep the order's frag mode on the radio, go in quietly with bang_off and "
			+ "no throw, and are done at the cleared kitchen (LD14, D15).",
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
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var door: String = Entry.BACK["id"]
	for id in IDS:
		Probe.arm(t.actor(id), 0, 1)
	if not t.require(
			IDS.all(func(id): return Probe.count(t.actor(id), Probe.FRAG) == 1),
			"both invaders carry a frag when the order is given (Character.item_count(8))",
	):
		return
	var squad := t.squad(&"invader")
	var order := Order.stack_order(
		squad,
		IDS.map(func(id): return t.actor(id)),
		Order.BACK_NORTH,
		"frag",
		false,
	)
	if not t.require(not order.is_empty(), "the squad posts the frag stack order (issue)"):
		return
	t.check(
		String(order.get("mode", "")) == "frag",
		"the order's mode is frag (%s)" % str(order.get("mode")),
	)
	await t.frames(2)
	for id in IDS:
		Probe.arm(t.actor(id), 0, 0)
	if not t.require(
			IDS.all(func(id): return Probe.count(t.actor(id), Probe.FRAG) == 0),
			"the frags are gone (premise)",
	):
		return
	var claimed := func():
		return IDS.all(func(id): return not Order.ordered_claims(t, t.actor(id), door).is_empty())
	if not t.require(
			await t.until(claimed, 10.0),
			"both claim the back door under the order (claims carrying order_id)",
	):
		return
	_check_ordered_modes(t, door)
	await _check_quiet_entry(t)


func _check_ordered_modes(t: TestContext, door: String) -> void:
	for id in IDS:
		var modes := Order.ordered_claims(t, t.actor(id), door).map(
			func(c): return str(c.get("order_mode", "")),
		)
		t.check(
			not modes.is_empty() and modes.all(func(m): return m == "frag"),
			"%s's ordered claims carry the order's mode, frag (%s)" % [id, str(modes.slice(0, 3))],
		)


func _check_quiet_entry(t: TestContext) -> void:
	t.check(
		await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), 45.0),
		"the stack goes in",
	)
	t.check(not t.happened(&"throw") and Probe.booms(t).is_empty(), "no grenade was thrown")
	var gave_up := IDS.filter(
		func(id): return Entry.calls(t, "", id).any(func(c): return c.get("bang_off") == true),
	)
	t.check(not gave_up.is_empty(), "the stack radioed bang_off: the frag given up")
	var done := func():
		return IDS.all(func(id): return not Order.progress(t, "done", t.actor(id)).is_empty())
	t.check(
		await t.until(done, 40.0),
		"the order is still done at the cleared kitchen (order_step done from %s)" % str(IDS.filter(
			func(id): return not Order.progress(t, "done", t.actor(id)).is_empty(),
		)),
	)
	t.check(
		t.happened(&"callout", func(c): return String(c.get("cleared_room", "")) == "kitchen"),
		"the kitchen was radioed cleared",
	)
