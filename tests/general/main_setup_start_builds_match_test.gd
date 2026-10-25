extends GameTest
## The setup window's Start builds the match it was set to: Main reads the window's config into a
## match spec (`MatchBuilder.spec_from_setup`, over its exports' spec) and starts it
## (`Main.start_match`). Main run whole (`tests/_main/main_probe.gd`) as a fresh launch starts it,
## in a world of its own, with an older choice saved (`Settings.setup`: one a side, the defender's
## seat); then the window's `start_requested` is emitted with a different choice, a played match on
## the invaders' side with "Lead the team" on: two defenders with a pistol, no stun and one frag,
## and two invaders with a rifle, two stuns, no frag and a plate carrier holding one plate, in
## front. Read through the match's public nodes only: its `World` (the group `match_world`), the
## characters under it, the human `Player`, its stack radio, and each NPC's controller's squad
## (interface 21). Scripted Von (the first option offered). Runs against a scratch settings file,
## never the real one.

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_setup_start_test.json"
## The choice the window's Start hands Main.
const CONFIG := {
	"mode": "play",
	"side": "invader",
	"seed": 31,
	"lead": true,
	"defenders": { "count": 2, "weapon": "pistol", "stuns": 0, "frags": 1 },
	"invaders": {
		"count": 2,
		"weapon": "rifle",
		"stuns": 2,
		"frags": 0,
		"outfit": {
			"head": "helmet",
			"body": "shirt",
			"vest": "plate_carrier",
			"pants": "tactical_pants",
			"feet": "boots",
			"front_plate": "steel_iii",
			"back_plate": "",
		},
	},
}


func describe() -> Dictionary:
	return {
		"name": "The setup window's Start builds the match it was set to",
		"description": "Start in the setup window: Main builds a match with the chosen counts, "
			+ "each side armed with its chosen loadout, and the human leading its side with its "
			+ "stack radio.",
		"tags": ["setup", "match", "loadout", "leadership"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {
		"mode": "play",
		"side": "defender",
		"seed": 5,
		"lead": false,
		"defenders": { "count": 1 },
		"invaders": { "count": 1 },
	})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", Settings.debug)
	s.von_script([])


func run(t: TestContext) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	var viewport := MainProbe.viewport(t)
	var main = MainProbe.open(viewport)
	var menu := MainProbe.setup_menu(main)
	if not t.require(menu != null, "premise: Main opened the setup window"):
		await MainProbe.close(t, viewport)
		return
	menu.start_requested.emit(CONFIG.duplicate(true))
	var built := func():
		var match_world := _world(main)
		return match_world != null and match_world.get_node_or_null("Player") != null
	if not t.require(
			await t.until(built, 8.0),
			"Start builds a match: a World with the human in it",
	):
		await MainProbe.close(t, viewport)
		return
	var world := _world(main)
	_check_sides(t, world)
	_check_squad(t, world)
	await MainProbe.close(t, viewport)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


## The match under `world` has the chosen counts, the human on the invaders' side, and each side
## armed and dressed as chosen.
func _check_sides(t: TestContext, world: Node) -> void:
	var player: Node = world.get_node("Player")
	var defenders := _npcs(world, MatchBuilder.DEFENDER_FACTION)
	var invaders := _npcs(world, MatchBuilder.INVADER_FACTION)
	t.expect_eq(defenders.size(), 2, "two defender NPCs, as chosen")
	t.expect_eq(invaders.size(), 2, "two invader NPCs, as chosen")
	t.expect_eq(
		player.get("faction"),
		MatchBuilder.INVADER_FACTION,
		"the human joins the chosen side, the invaders",
	)

	for c: Node in defenders:
		t.check(
			_carries(c, &"pistol", 0, 1),
			"%s carries the defenders' choice: a pistol, no stun, a frag (%s)"
				% [c.name, _kit(c)],
		)
	for c: Node in invaders + [player]:
		t.check(
			_carries(c, &"rifle", 2, 0),
			"%s carries the invaders' choice: a rifle, two stuns, no frag (%s)"
				% [c.name, _kit(c)],
		)
		var ids: Dictionary = c.outfit().ids()
		t.check(
			ids.get("vest") == &"plate_carrier"
				and ids.get("front_plate") == &"steel_iii"
				and ids.get("back_plate") == &"",
			"%s wears the invaders' choice: a plate carrier, one plate in front (%s)"
				% [c.name, str(ids)],
		)


## The human under `world` has its stack radio and leads its side's squad, the invader NPCs in it.
func _check_squad(t: TestContext, world: Node) -> void:
	var player: Node = world.get_node("Player")
	var invaders := _npcs(world, MatchBuilder.INVADER_FACTION)
	var stack := _stack_of(player)
	t.check(stack != null, "the human has its stack radio (a PlayerStack)")
	var squad: Node = stack.get("squad") if stack != null else null
	t.check(
		squad != null and squad.leader() == player,
		"leading on: the human leads its side's squad (leader %s)"
			% (str(squad.leader()) if squad != null else "no squad"),
	)
	t.check(
		invaders.all(func(npc): return TestContext.controller_of(npc).get("squad") == squad),
		"the invader NPCs are in the human's squad",
	)


## Main's match world (its child in the group `match_world`), or null before Start.
func _world(main: Node) -> Node:
	if not is_instance_valid(main):
		return null
	for child in main.get_children():
		if child.is_in_group(&"match_world"):
			return child
	return null


## The NPCs of `faction` under `world`: the characters with an AI controller.
func _npcs(world: Node, faction: StringName) -> Array:
	return world.get_children().filter(func(c): return (
		c.is_in_group(&"characters")
			and c.get("faction") == faction
			and TestContext.controller_of(c) != null
			and TestContext.controller_of(c).is_in_group(&"npc_controllers")
	))


## Whether `c` holds the gun `gun` and carries `stuns` stun and `frags` frag grenades.
func _carries(c: Node, gun: StringName, stuns: int, frags: int) -> bool:
	var held: Object = c.current_item()
	return (held != null
		and held.gun_id() == gun
		and c.item_count(ItemRegistry.STUN_SLOT) == stuns
		and c.item_count(ItemRegistry.FRAG_SLOT) == frags)


## What `c` carries, for a message.
func _kit(c: Node) -> String:
	var held: Object = c.current_item()
	return "holds %s, stuns %d, frags %d" % [
		held.gun_id() if held != null else &"nothing",
		c.item_count(ItemRegistry.STUN_SLOT),
		c.item_count(ItemRegistry.FRAG_SLOT),
	]


## The human's stack radio: its child with a `view()` and a `squad`, or null.
func _stack_of(player: Node) -> Node:
	for child in player.get_children():
		if child.has_method("view") and "squad" in child:
			return child
	return null
