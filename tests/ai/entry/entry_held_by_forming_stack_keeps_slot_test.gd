extends GameTest
## Ticket #65 round 2, `docs/tactical-entry.md` E2 / "Bodies on the way": a walk to the stack held
## by a teammate of the same stack that is still on its way to its own slot (its claim at `claim`)
## keeps its slot. Such a hold is the stack forming (two walkers giving way to each other stand
## still for a moment, the garage home's six-member stack after a move-up), not the stack keeping
## the member from its slot, so the member waits instead of taking the back; at most `CAP` s, after
## which the rule for a walk the stack seals holds (the back of the stack, or `abort`)
## (`entry_held_by_forming_stack_cap`). Never for the human (`stack_ai_goes_round_player_in_slot`).
##
## The map of `entry_held_walk_replans`: a row of counters splits the room the invader starts in,
## one gap a body wide by the south wall, and a teammate stands still in the gap. Here the teammate
## is an invader puppet that radios a claim on the doorway (slot 1, still `claim`), and a second
## puppet far off claims slot 3, so the invader (ENTER the doorway, scripted Von) claims slot 2 and
## its walk there has no way but the gap. Once its approach has no waypoint left and it has been
## held past its first re-plan (`HELD_S`, under the cap), the teammate steps out of the gap: the
## invader must have kept slot 2 (no new claim, no `abort`) and reach it.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const WEST := Rect2(0, 0, 600, 400)
const EAST := Rect2(600, 0, 300, 400)
const DOOR := {
	"id": "door_600_200",
	"pos": Vector2(600, 200),
	"width": 80.0,
	"out": Vector2.LEFT,
	"room": EAST,
	"room_key": "east",
}
const ROW_X := 300.0
const ROW := [Vector2(ROW_X, 50), Vector2(ROW_X, 150), Vector2(ROW_X, 250)]
const GAP := Vector2(ROW_X, 352)
const START := Vector2(100, 200)
const FAR_MATE := Vector2(80, 60)
## Where the teammate in the gap steps to, leg by leg (east along the south wall, then north, clear
## of the walk to the door).
const ASIDE := [Vector2(430, 352), Vector2(450, 60)]
## The spec's cap on waiting for a teammate on its way (s, from when the hold began).
const CAP := 3.0
## How long into the hold (s, with no waypoint left) the teammate steps aside: past Locomotion's
## first re-plan of a held walk (0.75 s), short of the cap.
const HELD_S := 2.4
## Within this (px) of its slot's point it is in its slot (`Entry.SLOT_REACH` and a few px).
const SLOT_NEAR := 10.0


func describe() -> Dictionary:
	return {
		"name": "A walk held by a teammate still on its way keeps its slot",
		"description": "A teammate that has claimed a slot of the same stack stands in the only "
			+ "gap on the way; the invader, held short of it past its re-plan (under the cap), "
			+ "keeps its slot (no back of the stack, no abort) and reaches it once the teammate "
			+ "steps aside.",
		"tags": ["ai", "entry", "stack", "navigation", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "kitchen", "rect": EAST },
	], [{ "pos": DOOR["pos"], "width": DOOR["width"] }])
	for i in ROW.size():
		s.object(StringName("counter_%d" % i), "kitchen_counter", ROW[i], { "rotated": true })
	Entry.rules(s, DOOR)
	Entry.npc(s, &"walker", START)
	s.actor(&"mate", &"puppet", GAP, { "faction": &"invader", "max_health": 1.0e6 })
	s.actor(&"far_mate", &"puppet", FAR_MATE, { "faction": &"invader", "max_health": 1.0e6 })


## Whether the teammate in the gap steps aside once the invader has been held `HELD_S` (the cap case
## keeps it there).
func steps_aside() -> bool:
	return true


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var mate := t.puppet(&"mate")
	var brain := Entry.brain(t, &"walker")
	var claim_frame := GameClock.frame()
	# The state each frame's watch updates, in one Dictionary.
	var st := {
		"radio_in": 0.0, "held_bare": 0.0, "held_bare_at": INF, "aside_at": INF, "slots": [],
		"in_slot_at": INF, "spot": Vector2.INF, "rise_at": INF,
	}
	# The leg of `ASIDE` the teammate in the gap is walking (-1: not yet stepping aside).
	var leg := -1
	while t.time < 30.0:
		if _watch(t, st, walker, brain, claim_frame):
			break
		if st["aside_at"] != INF and leg < ASIDE.size() - 1 and (leg < 0 or mate.has_arrived()):
			leg += 1
			mate.walk_to(ASIDE[leg])
		if not steps_aside() and float(st["held_bare"]) > CAP + 2.0:
			break
		await t.frames(1)
	if not t.require(
			String(brain.current_act()).contains(DOOR["id"])
				or not (st["slots"] as Array).is_empty(),
			"the walker was sent to ENTER the doorway (%s)" % brain.current_act(),
	):
		return
	if not t.require(
			(st["slots"] as Array).size() > 0 and int(st["slots"][0]) == 2,
			"premise: it claimed slot 2 behind the teammate's slot 1 (%s)" % [st["slots"]],
	):
		return
	if not t.require(
			st["held_bare_at"] != INF,
			"premise: its approach, no waypoint left, was held short of the teammate in the gap",
	):
		return
	_judge(t, st)


## One frame's watch: radios the puppets' claims, notes the walker's claims, its hold with no
## waypoint left, the teammate's step aside and the walker in its slot, into `st`. True when the
## case is decided.
func _watch(
		t: TestContext,
		st: Dictionary,
		walker: Node,
		brain: Node,
		claim_frame: int,
) -> bool:
	_radio_claims(t, st, claim_frame)
	_note_slots(t, st)
	var e: Dictionary = Entry.entry(brain)
	var view: Dictionary = brain.debug_entry_view().get("entry", {})
	var loco: Dictionary = brain.debug_state().get("loco", {})
	var bare: bool = (String(e.get("phase", "")) == "approach"
			and (view.get("waypoints", [1]) as Array).is_empty())
	if (bare
			and String(loco.get("way", "")) == "held"
			and walker.global_position.distance_to(t.actor(&"mate").global_position) < 140.0):
		if st["held_bare_at"] == INF:
			st["held_bare_at"] = t.time - float(loco.get("held_for", 0.0))
		st["held_bare"] = t.time - float(st["held_bare_at"])
	if steps_aside() and st["aside_at"] == INF and float(st["held_bare"]) >= HELD_S:
		st["aside_at"] = t.time
	if e.get("stack_point") is Vector2:
		st["spot"] = e["stack_point"]
	if (st["in_slot_at"] == INF
			and String(e.get("phase", "")) == "stack"
			and walker.global_position.distance_to(st["spot"]) <= SLOT_NEAR):
		st["in_slot_at"] = t.time
	t.trace(
		"walker_to_mate",
		walker.global_position.distance_to(t.actor(&"mate").global_position),
	)
	return st["aside_at"] != INF and not steps_aside() or st["in_slot_at"] != INF


## Every half second the two puppets radio their claims again (slots 1 and 3).
func _radio_claims(t: TestContext, st: Dictionary, claim_frame: int) -> void:
	st["radio_in"] = float(st["radio_in"]) - 1.0 / Engine.physics_ticks_per_second
	if float(st["radio_in"]) <= 0.0:
		st["radio_in"] = 0.5
		_radio(t.actor(&"mate"), 1, claim_frame)
		_radio(t.actor(&"far_mate"), 3, claim_frame)


## Notes each slot the walker has claimed, in order, and when its slot first rose.
func _note_slots(t: TestContext, st: Dictionary) -> void:
	for c in Entry.calls(t, "claim", &"walker"):
		if not (st["slots"] as Array).has(int(c["slot"])):
			(st["slots"] as Array).append(int(c["slot"]))
			if (st["slots"] as Array).size() > 1 and st["rise_at"] == INF:
				st["rise_at"] = t.time


## The checks of this case: it kept its slot under the cap and reached it once the teammate stepped
## aside.
func _judge(t: TestContext, st: Dictionary) -> void:
	t.check(
		(st["slots"] as Array).size() == 1,
		("its slot never rises while a teammate on its way holds it (claimed %s; first rise at "
				+ "%.1f s, the hold began at %.1f s)")
			% [st["slots"], st["rise_at"], st["held_bare_at"]],
	)
	t.check(Entry.calls(t, "abort", &"walker").is_empty(), "it never gives the entry up (abort)")
	t.check(
		st["in_slot_at"] != INF and float(st["in_slot_at"]) - float(st["aside_at"]) < 8.0,
		"it reaches its slot once the teammate steps aside (aside at %.1f s, in its slot at %.1f s)"
			% [st["aside_at"], st["in_slot_at"]],
	)


## A puppet radios its claim on the doorway the way an AI member does: slot `slot`, still on its way
## (`claim`), made on `frame` where it stands.
static func _radio(c: Node2D, slot: int, frame: int) -> void:
	EventBus.post(
		&"callout",
		{
			"speaker": c, "faction": c.faction, "position": c.global_position, "status": "",
			"path": "", "label": "", "target_id": 0, "point": Vector2.ZERO, "opening": DOOR["id"],
			"into": "east", "slot": slot, "side": 1, "entry_step": "claim", "claim_frame": frame,
			"claim_pos": c.global_position,
		},
	)
