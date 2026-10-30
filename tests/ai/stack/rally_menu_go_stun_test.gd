extends GameTest
## D31 rule 4: the command menu's go with stun on a held rally. A puppet human leader rallies its
## two NPC teammates at the bare Terrace house's back door and holds the threshold in slot 1; once
## both stand ready, the leader gives "Go into the kitchen with stun". The thrower bangs first: a
## stun goes off in the kitchen before any AI crosses; then both AIs go in, the human not waited for
## (it never steps in).
##
## Real Von, the whole pipeline; no switch. Each NPC carries one stun, as a match arms an invader.

const Rally := preload("res://tests/_ai/rally_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
## How long (s) the stack is held before the go.
const HELD := 3.0
## How long (s) the AIs have, once the go is given, to be in.
const IN_WITHIN := 25.0


func describe() -> Dictionary:
	return {
		"name": "A human leader's rally goes in on the menu's go with stun",
		"description": "A puppet human leader rallies its two NPC teammates at the back door and "
			+ "holds; it gives the go with stun: a stun goes off in the kitchen before anyone "
			+ "crosses, then both AIs go in without waiting for the human.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "grenade", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Rally.world(s)


func run(t: TestContext) -> void:
	if not Rally.arm(t, 1, 0):
		return
	var w := FollowWatch.new_watch()
	if not await Rally.rallied(t, w):
		return
	await t.seconds(HELD)
	if not t.require(Grenades.booms(t).is_empty(), "set-up: no grenade went off while held"):
		return
	if Rally.menu_go(t, "stun").is_empty():
		return
	await Rally.both_in(t, w, IN_WITHIN)
	var booms := Grenades.booms(t, &"stun")
	var boom_at: float = booms[0]["time"] if not booms.is_empty() else INF
	var going := Rally.first_going_in(t)
	t.check(
		boom_at < INF and (booms[0]["data"]["position"] as Vector2).x < Entry.BACK["pos"].x
			and boom_at < going,
		"a stun went off in the kitchen before any AI crossed (burst at %.2f s, first going_in "
			% boom_at + "%.2f s)" % going,
	)
	Rally.check_went_without_human(t)
