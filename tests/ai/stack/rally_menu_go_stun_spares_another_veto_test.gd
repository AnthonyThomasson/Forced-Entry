extends GameTest
## D31 rule 4: the command menu's go on a held rally beats every veto but a member of the rally
## losing its grenade (D1 / D15). `rally_menu_go_stun`'s world, with a third teammate at the back
## door that is not in the rally: once both joiners stand ready, it radios a claim in the stack
## that gave the bang up (`bang_off`, slot 4, ready). The leader then gives "Go into the kitchen
## with stun": that claim is no joiner's, so it vetoes nothing; a stun goes off in the kitchen
## before any AI crosses, then both AIs go in.
##
## Real Von, the whole pipeline; no switch. Each NPC carries one stun, as a match arms an invader.

const Rally := preload("res://tests/_ai/rally_probe.gd")
const FollowWatch := preload("res://tests/_ai/follow_watch_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Grenades := preload("res://tests/_ai/grenade_probe.gd")
## How long (s) the stack is held, the other claim on the radio, before the go.
const HELD := 3.0
## How long (s) the AIs have, once the go is given, to be in.
const IN_WITHIN := 25.0
## How often (s) the other teammate radios its claim again, well inside a claim's 6 s on the radio.
const HEARTBEAT := 1.0
## Where the other teammate stands: in the back garden, south of the stack, out of its way.
const OTHER_AT := Vector2(1000, 330)


func describe() -> Dictionary:
	return {
		"name": "A human leader's rally's go with stun is not vetoed by a claim outside it",
		"description": "A puppet human leader rallies its two NPC teammates at the back door; a "
			+ "third teammate, not in the rally, radios a claim there that gave the bang up. The "
			+ "go with stun still throws a stun into the kitchen before anyone crosses.",
		"tags": ["ai", "stack", "squad", "join", "leadership", "human", "grenade", "von"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Rally.world(s)
	s.actor(&"other", &"puppet", OTHER_AT, { "faction": &"invader", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	if not Rally.arm(t, 1, 0):
		return
	var w := FollowWatch.new_watch()
	if not await Rally.rallied(t, w):
		return
	var side := _human_side(t)
	if not t.require(side != 0, "set-up: the human's claim names its side of the back door"):
		return
	var radio := { "on": true }
	_radio_other(t, side, radio)
	await t.seconds(HELD)
	if not t.require(Grenades.booms(t).is_empty(), "set-up: no grenade went off while held"):
		return
	if Rally.menu_go(t, "stun").is_empty():
		return
	await Rally.both_in(t, w, IN_WITHIN)
	radio["on"] = false
	var booms := Grenades.booms(t, &"stun")
	var boom_at: float = booms[0]["time"] if not booms.is_empty() else INF
	var going := Rally.first_going_in(t)
	t.check(
		boom_at < INF and (booms[0]["data"]["position"] as Vector2).x < Entry.BACK["pos"].x
			and boom_at < going,
		"a stun went off in the kitchen before any AI crossed, the other claim's bang_off no veto "
			+ "(burst at %.2f s, first going_in %.2f s)" % [boom_at, going],
	)
	Rally.check_went_without_human(t)


## The side of the back door (1 / -1 along its wall) the human's latest claim there names, or 0.
func _human_side(t: TestContext) -> int:
	var me := t.actor(&"me")
	var side := 0
	for e in t.events:
		var d: Dictionary = e["data"]
		if (e["topic"] == &"callout" and d.get("speaker") == me
				and String(d.get("opening", "")) == String(Entry.BACK["id"])
				and String(d.get("entry_step", "")) != ""):
			side = int(d.get("side", 0))
	return side


## Radio the other teammate's claim at the back door every `HEARTBEAT` s while `radio.on`: slot 4 on
## the human's `side`, ready, its bang given up (`bang_off`), no order and no join.
func _radio_other(t: TestContext, side: int, radio: Dictionary) -> void:
	var other := t.actor(&"other")
	var frame := GameClock.frame()
	while radio["on"] and is_instance_valid(other):
		EventBus.post(&"callout", {
			"speaker": other, "faction": other.faction, "position": other.global_position,
			"status": "", "path": "", "label": "", "target_id": 0, "point": Vector2.ZERO,
			"opening": String(Entry.BACK["id"]), "into": String(Entry.BACK["room_key"]),
			"slot": 4, "side": side, "entry_step": "ready", "claim_frame": frame,
			"claim_pos": other.global_position, "bang": false, "bang_off": true,
		})
		await t.seconds(HEARTBEAT)
