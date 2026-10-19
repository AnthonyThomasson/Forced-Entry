extends GameTest
## LD24 and D29 (`docs/leadership.md`, with interface 17): the human leader's own claim is the
## invaders'. A human defender leading its crew steps up to an interior doorway nobody stacks at:
## it makes no claim of its own there, the squad gives no `join` order, and its free teammate goes
## on following it. A puppet of the household faction stands in for the human, and the match's
## squads are built by Main's own wiring with "Lead the team" on (`_on_setup_chosen`, the human's
## stack radio from `_build_stack_markers`, `_build_squads`), with one defender NPC placed by Main's
## `MatchSpawner`; Main runs out of the tree, as in `command_menu_wiring_test.gd`. The human walks
## up beside the bare Terrace house's hall doorway into the living room, where the first of a stack
## stands, and holds there.
##
## Real Von, the whole pipeline; no switch. `Settings.path` points at a scratch file.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const MainScript := preload("res://scenes/main.gd")
const MatchSpawner := preload("res://scenes/match_spawner.gd")
## Where the human stands: in the hall against the wall east of the hall doorway into the living
## room, past its jamb, where the first of a stack stands (as `Order.BACK_NORTH` is at the back
## door).
const STEP_UP := Vector2(210, 392)
## Where the defender NPC starts: in the hall, near the human.
const NPC_AT := Vector2(420, 430)
## How long (s) the squad is watched once the human stands stepped up: its claim's repeats (every
## 2 s) and a rally's walk to the doorway included.
const HOLD := 8.0


func describe() -> Dictionary:
	return {
		"name": "A human defender leader stepping up to a doorway rallies nobody",
		"description": "A human defender leading its crew (Main's wiring, Lead the team on) "
			+ "stands beside an interior doorway nobody stacks at: no join order is posted and "
			+ "its teammate keeps following it (LD24, D29).",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "defender", "von"],
		"requires_von": true,
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.set_static(Settings, "path", "user://test_human_defender_leader_no_rally_settings.json")
	s.set_static(Settings, "setup", {})
	s.actor(
		&"me",
		&"puppet",
		Vector2(330, 420),
		{ "faction": &"household", "max_health": 1_000_000.0, "aim_point": STEP_UP },
	)


func run(t: TestContext) -> void:
	var main = MainScript.new()
	await main._on_setup_chosen({ "mode": "play", "side": "defender", "seed": 5, "lead": true,
		"defenders": { "count": 1 }, "invaders": { "count": 0 } })
	var spawner = MatchSpawner.new()
	spawner.world = t.world
	spawner.openings = t.world.get("openings")
	spawner.add_npc(MatchSpawner.DEFENDER_SCENE, spawner.npc_name("Defender", 0), NPC_AT, t.rooms)
	var mate: Node = spawner.combatants[0]
	var me := t.actor(&"me")
	main._world = t.world
	main._spawner = spawner
	main._player = me
	main._build_stack_markers(t.rooms)
	main._build_squads([mate, me], t.rooms)
	var squad: Node = main._squads.get(me.get("faction"))
	if not t.require(
			squad != null and squad.leader() == me and squad.follows(mate),
			"premise: Main built the defenders' squad, the human leads it and its teammate follows",
	):
		main.free()
		return
	var stack: Node = main._player_stack
	if not t.require(
			stack != null and stack.get_parent() == me and stack.get("squad") == squad,
			"premise: the human has its stack radio (bind_player), handed its squad (bind_squad)",
	):
		main.free()
		return
	var nodes: Array = [me, mate]
	var w := Follow.new_watch()
	var puppet := t.puppet(&"me")
	puppet.walk_to(STEP_UP)
	var arrived := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return puppet.has_arrived()
	if not t.require(await t.until(arrived, 8.0), "the human walked up beside the hall doorway"):
		main.free()
		return
	puppet.stop()
	var stood := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return false
	await t.until(stood, HOLD)

	var door := String(Entry.HALL_LIVING["id"])
	t.check(
		Follow.own_claims(t, me).is_empty(),
		"the human defender made no claim of its own (claims %s)"
			% str(Follow.own_claims(t, me).map(func(e): return e["data"].get("opening"))),
	)
	t.check(
		Follow.raw_joins(t).is_empty(),
		"the squad gave no join order (joins %s)"
			% str(Follow.raw_joins(t).map(func(e): return e["data"])),
	)
	t.check(
		Follow.first_call(t, mate, "claim", door) == INF,
		"the teammate claimed no slot at the hall doorway",
	)
	t.check(
		not Follow.took(w, mate, "order") and Follow.following(mate),
		"the teammate kept following the human (acts %s)" % Follow.acts_of(w, mate),
	)
	main.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
