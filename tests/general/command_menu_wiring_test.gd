extends GameTest
## LD11 and interface 21 (`docs/leadership.md`): the wiring, in a match Main builds. With "Lead the
## team" on, Main's match (`Main.start_match`, through `MatchBuilder`) has one squad per faction
## over its combatants, armed first, each NPC handed its squad, and, because the human leads, the
## command menu and the order markers, the menu's `order_requested` connected to the squad's
## `issue`. The human leader opens the menu on the Terrace house's back door, ticks its two NPC
## teammates and orders "Stack into the kitchen with stun"; after the menu closes (and the tree is
## unpaused), both NPCs claim slots at the back door under the order, in bang mode. Part 2 (LD13,
## LD16): the order is given with the menu's "Hold for my go" ticked, so the stack holds once
## formed; the leader opens the menu on the door again and chooses "Go into the kitchen", and the
## stack bangs and goes in.
##
## Main runs whole in a world of its own (`tests/_main/main_probe.gd`), through its public members:
## the window's config turned into a match spec (`MatchBuilder.spec_from_setup`) over a base that
## names the bare Terrace house as the match's house, the NPC invaders' start points (`at`) and a
## puppet of the test standing in for the player as the human, then `Main.start_match(spec)`.
## Scripted Von (the first option offered): the NPCs' own decisions are not under test, and the
## order level asks nothing. `Settings.path` points at a scratch file.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const MainProbe := preload("res://tests/_main/main_probe.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const OrderMenu := preload("res://tests/_ai/order_menu_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const NPC_AT := [Vector2(960, 60), Vector2(985, 110)]
## How long (s) the held stack is watched holding once both are ready.
const HOLD := 8.0


func describe() -> Dictionary:
	return {
		"name": "The leader's menu orders a stun stack in a Main-built match",
		"description": "With Lead the team on, Main builds the squads and the command menu; "
			+ "ordering two ticked teammates to stack on the back door with a stun makes both "
			+ "claim slots there in bang mode once the menu closes (LD11, interface 21); ordered "
			+ "with Hold for my go it holds until the menu's Go, then bangs and goes in (LD13, "
			+ "LD16).",
		"tags": ["setup", "match", "leadership", "order", "ui"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	s.von_script([])
	s.lock_interaction([&"camera", &"pause"])
	s.set_static(Settings, "path", "user://test_command_menu_wiring_settings.json")
	s.set_static(Settings, "setup", {})
	s.set_static(Settings, "overlays", {})
	s.set_static(Settings, "debug", Settings.debug)
	s.actor(
		&"me",
		&"puppet",
		Vector2(1150, 500),
		{ "faction": &"invader", "max_health": 1_000_000.0 },
	)


func run(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var me := t.actor(&"me")
	var built: Dictionary = await _start(viewport, main, me)
	var menu := _premise_menu(t, built, me)
	if menu == null:
		await MainProbe.close(t, viewport)
		return
	var npcs: Array = (built["combatants"] as Array).filter(func(c): return c != me)
	if not await _order_stack(t, menu, npcs):
		await MainProbe.close(t, viewport)
		return
	await _check_claims(t, npcs)
	await _hold_then_go(t, menu, npcs)
	await MainProbe.close(t, viewport)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))


## Main's match from the window's config over a base naming the bare Terrace house, the NPC
## invaders' start points and `me` as the human: what `main.start_match` returns.
func _start(viewport: SubViewport, main: Variant, me: Node) -> Dictionary:
	var layout := TestSetup.new()
	Maps.house(layout, false)
	var base := MatchBuilder.spec({
		"house": MainProbe.house(layout, viewport),
		"invaders": { "at": NPC_AT },
		"human": { "node": me },
	})
	var spec := MatchBuilder.spec_from_setup(
		{ "mode": "play", "side": "invader", "seed": 5, "lead": true,
			"defenders": { "count": 0 }, "invaders": { "count": 2 } },
		base,
	)
	return await main.start_match(spec)


## The premises on the match `built`: Main built it, armed the two NPC invaders with a stun each,
## built the invaders' squad led by `me`, and put the command menu in its world. The menu, or null
## when a premise failed.
func _premise_menu(t: TestContext, built: Dictionary, me: Node) -> Node:
	if not t.require(not built.is_empty(), "premise: Main built the match (start_match)"):
		return null
	var npcs: Array = (built["combatants"] as Array).filter(func(c): return c != me)
	if not t.require(
			npcs.size() == 2 and npcs.all(func(n): return Probe.count(n, Probe.STUN) >= 1),
			"Main armed the two NPC invaders with a stun each (premise: the invaders' loadout)",
	):
		return null
	var squad: Node = (built["squads"] as Dictionary).get(&"invader")
	if not t.require(
			squad != null and squad.leader() == me,
			"Main built the invaders' squad, led by the human (Lead the team)",
	):
		return null
	var menu := _find_menu(built["world"])
	if not t.require(
			menu != null,
			"the command menu is in the match's world (a node with open_at under World)",
	):
		return null
	return menu


## The leader ticks both `npcs` in the menu, opens it on the back door, ticks "Hold for my go" and
## chooses "Stack into the kitchen with stun"; false when the item was not offered (the tree
## unpaused, the test ended).
func _order_stack(t: TestContext, menu: Node, npcs: Array) -> bool:
	for npc in npcs:
		t.check(
			OrderMenu.tick(menu, String(npc.name), true),
			"the menu lists teammate %s to tick" % npc.name,
		)
	menu.open_at(Order.BACK_NORTH)
	await t.frames(1)
	t.check(t.world.get_tree().paused, "the menu pauses the match")
	t.check(_set_hold(menu, true), "the menu has a \"Hold for my go\" checkbox to tick (LD16)")
	if not t.require(
			OrderMenu.choose(menu, "Stack into the kitchen with stun"),
			"it offers \"Stack into the kitchen with stun\" (items %s)"
				% str(OrderMenu.labels(menu)),
	):
		t.world.get_tree().paused = false
		return false
	await t.frames(1)
	t.check(not t.world.get_tree().paused, "choosing it closes the menu and unpauses")
	t.check(
		not Order.orders(t).is_empty(),
		"the squad posted the order (Main wired order_requested to Squad.issue)",
	)
	return true


## Both `npcs` claim slots at the back door under the order, in bang mode.
func _check_claims(t: TestContext, npcs: Array) -> void:
	var claimed := func():
		return npcs.all(func(n): return not Order.ordered_claims(t, n, Entry.BACK["id"]).is_empty())
	t.check(
		await t.until(claimed, 10.0),
		"both teammates claim slots at the back door under the order",
	)
	for n in npcs:
		var claims := Order.ordered_claims(t, n, Entry.BACK["id"])
		t.check(
			not claims.is_empty() and claims.all(func(c): return c.get("bang") == true),
			"%s claims in bang mode (%s)"
				% [n.name, str(claims.map(func(c): return c.get("bang")))],
		)


## LD13 / LD16 (part 2): the stun stack was ordered with "Hold for my go" ticked, so it holds once
## formed: no bang call, no crossing. The leader opens the menu on the back door again and chooses
## "Go into the kitchen"; the squad posts the go, the bang is called and the stack goes in.
func _hold_then_go(t: TestContext, menu: Node, npcs: Array) -> void:
	t.expect_eq(
		Order.orders(t).back().get("wait_go") if not Order.orders(t).is_empty() else null,
		true,
		"the stack ordered with Hold for my go ticked is held (wait_go)",
	)
	var ready := func():
		return npcs.all(func(n): return not Order.raw_calls(t, n, "ready").is_empty())
	if not t.require(await t.until(ready, 20.0), "both teammates stack and radio ready"):
		return
	var early := await t.until(
		func(): return (
			not Entry.calls(t, "bang").is_empty() or not Entry.calls(t, "going_in").is_empty()
		),
		HOLD,
	)
	t.check(
		not early,
		("the held stack holds: no bang call and nobody goes in for %.0f s (bang calls %d, "
				+ "going_in %d)")
			% [HOLD, Entry.calls(t, "bang").size(), Entry.calls(t, "going_in").size()],
	)
	if early:
		return
	menu.open_at(Order.BACK_NORTH)
	await t.frames(1)
	if not t.require(
			OrderMenu.choose(menu, "Go into the kitchen"),
			"the menu offers \"Go into the kitchen\" on the held stack's door (items %s)"
				% str(OrderMenu.labels(menu)),
	):
		t.world.get_tree().paused = false
		return
	await t.frames(1)
	t.check(not t.world.get_tree().paused, "choosing it closes the menu and unpauses")
	t.check(
		Order.orders(t).any(func(o): return String(o.get("kind", "")) == Order.GO),
		"the squad posted the go (Main wired the go request to Squad.issue)",
	)
	t.check(
		await t.until(func(): return not Entry.calls(t, "bang").is_empty(), 10.0),
		"after the go the bang is called",
	)
	t.check(
		await t.until(func(): return not Entry.calls(t, "going_in").is_empty(), 20.0),
		"and the stack goes in",
	)


## Tick or untick the menu's "Hold for my go" checkbox the way a click does; false when it has none.
func _set_hold(menu: Node, on: bool) -> bool:
	for box: BaseButton in menu.find_children("*", "BaseButton", true, false):
		if ((box is CheckBox or box is CheckButton)
				and String(box.text).to_lower().contains("hold for my go")):
			if box.button_pressed != on:
				box.button_pressed = on
				box.toggled.emit(on)
			return true
	return false


## The command menu Main built: the node with `open_at` and `order_requested` under `root`, or null.
func _find_menu(root: Node) -> Node:
	for n in root.find_children("*", "", true, false):
		if n.has_method("open_at") and n.has_signal("order_requested"):
			return n
	return null
