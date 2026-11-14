extends GameTest
## Two NPCs on one target take different flank sides under the prices the game ships, a decision
## sliced over frames (`DecisionBudget`, `decision-job.md`): both want to decide at once on the same
## cadence, the pool starts one a frame, and the second's snapshot is built while the first's walk
## runs and radios its side. The second reads the callouts again as its walk begins
## (`AgentPerception.reread_claims`), so it is offered the side the first claimed as taken and
## goes to another (`docs/flanking-behavior.md` B3, B4). The re-read itself is pinned by
## `claim_seen_during_throw_piece` and `claim_seen_as_the_walk_begins`: with one start a frame and
## an oldest-first pool this scene stays green without it.
##
## The scene of `ai/flank/flank_two_invaders_split_sides` with the one thing taken out of it: the
## different cadences, which kept the two from deciding together (a tie claimed one side twice
## when a decision ran whole in a frame). Scripted Von prefers left, then right, then rear; the
## pool and the prices are the game's own.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const A_POS := Vector2(120, 350)
const B_POS := Vector2(120, 430)
const TARGET_POS := Vector2(620, 330)


func describe() -> Dictionary:
	return {
		"name": "Two NPCs on one target take different sides under sliced decisions",
		"description": "Side by side in the warehouse, on one cadence, both prefer the left; with "
			+ "decisions spread over frames the second reads the first's radio claim as its walk "
			+ "begins and takes another side.",
		"tags": ["ai", "decision", "flank", "callout", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	Flank.rules(s)
	Flank.npc(s, &"a", A_POS, {}, { "look_at": TARGET_POS })
	Flank.npc(s, &"b", B_POS, {}, { "look_at": TARGET_POS })
	Flank.target(s, &"target", TARGET_POS, A_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(A_POS)
	var a := t.controller(&"a", &"current_act")
	var b := t.controller(&"b", &"current_act")
	# Premise: a decision takes frames here (the shipped prices slice it): the longest, claim to
	# landing, of each NPC's decisions in the first 3 s.
	var longest := { &"a": 0, &"b": 0 }
	var claimed := { &"a": -1, &"b": -1 }
	var seen := { &"a": 0, &"b": 0 }
	for frame in 180:
		await t.frames(1)
		for id: StringName in [&"a", &"b"]:
			var state: Dictionary = t.controller(id, &"debug_state").debug_state()
			if int(state["decisions"]) > seen[id]:
				seen[id] = int(state["decisions"])
				claimed[id] = frame
			elif claimed[id] >= 0 and not bool(state["decision"]["pending"]):
				longest[id] = maxi(longest[id], frame - claimed[id] + 1)
				claimed[id] = -1
	var sa := Flank.side_of_act(a)
	var sb := Flank.side_of_act(b)
	t.check(
		sa != "" and sb != "",
		"both ended up flanking (%s / %s)" % [a.current_act(), b.current_act()],
	)
	t.check(sa != sb, "on different sides (%s / %s)" % [sa, sb])
	t.check(Flank.sides_claimed(t) >= 2, "each radioed its side")
	t.check(
		longest[&"a"] >= 2 and longest[&"b"] >= 2,
		"premise: the shipped prices took each NPC's longest decision over frames (%s)" % [longest],
	)
