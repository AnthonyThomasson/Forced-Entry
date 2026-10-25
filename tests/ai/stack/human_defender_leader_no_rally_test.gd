extends GameTest
## LD24 and D29 (`docs/leadership.md`, with interface 17): the human leader's own claim is the
## invaders'. A human defender leading its crew steps up to an interior doorway nobody stacks at:
## it makes no claim of its own there, the squad gives no `join` order, and its free teammate goes
## on following it. A puppet of the household faction stands in for the human, and the match is
## Main's own with "Lead the team" on (`Main.start_match`, the window's config through
## `MatchBuilder.spec_from_setup`: the human's stack radio, the squads), on the bare Terrace house
## (the spec's `house`), its one defender NPC and the human at the spec's start points; Main runs
## whole in a world of its own, as in `command_menu_wiring_test.gd`. The human walks up beside the
## hall doorway into the living room, where the first of a stack stands, and holds there.
##
## Real Von, the whole pipeline; no switch. `Settings.path` points at a scratch file.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Follow := preload("res://tests/_ai/follow_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const MainProbe := preload("res://tests/_main/main_probe.gd")
## Where the human stands: in the hall against the wall east of the hall doorway into the living
## room, past its jamb, where the first of a stack stands (as `Order.BACK_NORTH` is at the back
## door).
const STEP_UP := Vector2(210, 392)
## Where the human and the defender NPC start: in the hall, near each other.
const HUMAN_AT := Vector2(330, 420)
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
	s.set_static(Settings, "path", "user://test_human_defender_leader_no_rally_settings.json")
	s.set_static(Settings, "setup", {})
	s.set_static(Settings, "overlays", {})
	s.set_static(Settings, "debug", Settings.debug)
	s.actor(
		&"me",
		&"puppet",
		HUMAN_AT,
		{ "faction": &"household", "max_health": 1_000_000.0, "aim_point": STEP_UP },
	)


func run(t: TestContext) -> void:
	var viewport := MainProbe.viewport(t)
	var me := t.actor(&"me")
	var built: Dictionary = await _start(viewport, me)
	var mate := _mate(t, built, me)
	if mate == null:
		await MainProbe.close(t, viewport)
		return
	var squad: Node = (built.get("squads", {}) as Dictionary).get(me.get("faction"))
	var w := Follow.new_watch()
	if not await _step_up(t, w, [me, mate], squad):
		await MainProbe.close(t, viewport)
		return
	_check_no_rally(t, w, me, mate)
	await MainProbe.close(t, viewport)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))


func _start(viewport: SubViewport, me: Node) -> Dictionary:
	var main = MainProbe.open(viewport)
	var layout := TestSetup.new()
	Maps.house(layout, false)
	var base := MatchBuilder.spec({
		"house": MainProbe.house(layout, viewport),
		"defenders": { "at": [NPC_AT] },
		"human": { "node": me, "at": HUMAN_AT },
	})
	var spec := MatchBuilder.spec_from_setup(
		{ "mode": "play", "side": "defender", "seed": 5, "lead": true,
			"defenders": { "count": 1 }, "invaders": { "count": 0 } },
		base,
	)
	return await main.start_match(spec)


func _mate(t: TestContext, built: Dictionary, me: Node) -> Node:
	var squad: Node = (built.get("squads", {}) as Dictionary).get(me.get("faction"))
	var mates: Array = (built.get("combatants", []) as Array).filter(func(c): return c != me)
	if not t.require(
			squad != null and mates.size() == 1 and squad.leader() == me
				and squad.follows(mates[0]),
			"premise: Main built the defenders' squad, the human leads it and its teammate follows",
	):
		return null
	var mate: Node = mates[0]
	var stack: Node = built["player_stack"]
	if not t.require(
			stack != null and stack.get_parent() == me and stack.get("squad") == squad,
			"premise: the human has its stack radio (bind_player), handed its squad (bind_squad)",
	):
		return null
	return mate


func _step_up(t: TestContext, w: Dictionary, nodes: Array, squad: Node) -> bool:
	var puppet := t.puppet(&"me")
	puppet.walk_to(STEP_UP)
	var arrived := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return puppet.has_arrived()
	if not t.require(await t.until(arrived, 8.0), "the human walked up beside the hall doorway"):
		return false
	puppet.stop()
	var stood := func() -> bool:
		Follow.tick(w, t, nodes, squad)
		return false
	await t.until(stood, HOLD)
	return true


func _check_no_rally(t: TestContext, w: Dictionary, me: Node, mate: Node) -> void:
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
