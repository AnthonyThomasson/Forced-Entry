extends GameTest
## Ticket #65 round 2, `docs/tactical-entry.md` E2 / "Bodies on the way": the hold of a walk to the
## stack is timed by how long the member has stood, not by how long its latest walk has lasted. The
## map and stack of `entry_held_by_forming_stack_cap`: a row of counters splits the room the invader
## starts in, one gap a body wide by the south wall, and a teammate (an invader puppet radioing slot
## 1, still `claim`) stands for ever in the gap; a second puppet far off claims slot 3, so the
## invader (ENTER the doorway, scripted Von) claims slot 2 and its walk there has no way but the
## gap. Here the teammate in the gap radios its slot on one side of the door and then the other,
## every `FLIP_S` s, so the invader's slot point moves (its place in its file, or its side, follows
## the claims) and its walk is aimed again, more than a few px each time, while it stands held. Its
## hold still runs from when it stopped: past the cap (`CAP` s of standing) the rule for a walk the
## stack seals holds, and it takes the back of the stack (slot 4, behind the far teammate's 3) by
## `CAP` + `LATE_S` s of standing.

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
## The spec's cap on waiting for a teammate on its way (s of standing held).
const CAP := 3.0
## How long past the cap (s) the back of the stack may come: the re-plan that hands the entry the
## hold runs on Locomotion's clock.
const LATE_S := 1.0
## Seconds between the teammate's claims on one side of the door and the other.
const FLIP_S := 0.6
## How far (px) the invader's slot point must move for its walk to be aimed again
## (`Locomotion.NEW_WALK` is 8).
const REAIM_PX := 8.0
## The invader stands when it moves less than this (px) over `STILL_WINDOW` s, within `NEAR_MATE` px
## of the teammate in the gap.
const STILL_PX := 3.0
const STILL_WINDOW := 0.25
const NEAR_MATE := 140.0


func describe() -> Dictionary:
	return {
		"name": "A held walk aimed again still reaches the cap on time",
		"description": "A teammate on its way stands for ever in the only gap and its claim flips "
			+ "from one side of the door to the other, moving the invader's slot point while it "
			+ "stands held; past the cap of standing it takes the back of the stack.",
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


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var mate := t.actor(&"mate")
	var brain := Entry.brain(t, &"walker")
	var claim_frame := GameClock.frame()
	var st := {
		"radio_in": 0.0, "flip_in": FLIP_S, "side": 1, "slots": [], "rise_at": INF, "still_at": INF,
		"spot": Vector2.INF, "reaims": 0, "trail": [],
	}
	while t.time < 30.0:
		_radio_claims(t, st, mate, claim_frame)
		_note_slots(t, st)
		_watch_walker(t, st, walker, mate, brain)
		if st["rise_at"] != INF or not Entry.calls(t, "abort", &"walker").is_empty():
			break
		if st["still_at"] != INF and t.time > float(st["still_at"]) + CAP + LATE_S + 4.0:
			break
		await t.frames(1)
	if not _premises_hold(t, st):
		return
	_judge(t, st)


## Every half second the two puppets radio their claims again (slots 1 and 3); once the walker
## stands, the teammate in the gap flips its side every `FLIP_S` s and radios at once.
func _radio_claims(t: TestContext, st: Dictionary, mate: Node, claim_frame: int) -> void:
	st["radio_in"] = float(st["radio_in"]) - 1.0 / Engine.physics_ticks_per_second
	st["flip_in"] = float(st["flip_in"]) - 1.0 / Engine.physics_ticks_per_second
	if float(st["flip_in"]) <= 0.0 and st["still_at"] != INF:
		st["flip_in"] = FLIP_S
		st["side"] = -int(st["side"])
		st["radio_in"] = 0.0
	if float(st["radio_in"]) <= 0.0:
		st["radio_in"] = 0.5
		_radio(mate, 1, int(st["side"]), claim_frame)
		_radio(t.actor(&"far_mate"), 3, 1, claim_frame)


## Notes each slot the walker has claimed, in order, and when its slot first rose.
func _note_slots(t: TestContext, st: Dictionary) -> void:
	for c in Entry.calls(t, "claim", &"walker"):
		if not (st["slots"] as Array).has(int(c["slot"])):
			(st["slots"] as Array).append(int(c["slot"]))
			if (st["slots"] as Array).size() > 1 and st["rise_at"] == INF:
				st["rise_at"] = t.time


## Notes when the walker began to stand held near the teammate in the gap, and each time its slot
## point moved enough to aim its walk again while it stood.
func _watch_walker(t: TestContext, st: Dictionary, walker: Node, mate: Node, brain: Node) -> void:
	var e: Dictionary = Entry.entry(brain)
	var trail: Array = st["trail"]
	trail.append([t.time, walker.global_position])
	while trail.size() > 1 and float(trail[0][0]) < t.time - STILL_WINDOW:
		trail.pop_front()
	var still: bool = (float(trail[0][0]) <= t.time - STILL_WINDOW + 0.02
			and (trail[0][1] as Vector2).distance_to(walker.global_position) < STILL_PX)
	if (st["still_at"] == INF
			and String(e.get("phase", "")) == "approach"
			and still
			and walker.global_position.distance_to(mate.global_position) < NEAR_MATE):
		st["still_at"] = t.time - STILL_WINDOW
	if e.get("stack_point") is Vector2:
		if (st["still_at"] != INF
				and st["rise_at"] == INF
				and (st["spot"] as Vector2).distance_to(e["stack_point"]) > REAIM_PX):
			st["reaims"] = int(st["reaims"]) + 1
		st["spot"] = e["stack_point"]
	t.trace("walker_to_mate", walker.global_position.distance_to(mate.global_position))


## The premises: slot 2 claimed, the walk stood held short of the teammate, its slot point moved
## at least twice while it stood.
func _premises_hold(t: TestContext, st: Dictionary) -> bool:
	if not t.require(
			(st["slots"] as Array).size() > 0 and int(st["slots"][0]) == 2,
			"premise: it claimed slot 2 behind the teammate's slot 1 (%s)" % [st["slots"]],
	):
		return false
	if not t.require(
			st["still_at"] != INF,
			"premise: its walk to the stack stood held short of the teammate in the gap",
	):
		return false
	return t.require(
		int(st["reaims"]) >= 2,
		("premise: its slot point moved more than %.0f px at least twice while it stood (%d "
				+ "times)") % [REAIM_PX, st["reaims"]],
	)


## The checks: no abort, and the back of the stack taken once it had stood the cap.
func _judge(t: TestContext, st: Dictionary) -> void:
	var to_rise := float(st["rise_at"]) - float(st["still_at"])
	t.check(
		Entry.calls(t, "abort", &"walker").is_empty(),
		"it never gives the entry up (abort): the back of the stack has room",
	)
	t.check(st["rise_at"] != INF and int(st["slots"][st["slots"].size() - 1]) == 4,
		"past the cap of standing it takes the back of the stack (claimed %s)" % [st["slots"]])
	t.check(
		st["rise_at"] != INF and to_rise >= CAP - 0.25 and to_rise <= CAP + LATE_S,
		("it takes the back once it has stood the cap, whatever its walk was aimed at meanwhile "
				+ "(the slot rose %.2f s after it stopped, the cap %.1f s; aimed again %d times)")
			% [to_rise, CAP, st["reaims"]],
	)


## A puppet radios its claim on the doorway: slot `slot` on side `side`, still on its way, made on
## `frame`.
static func _radio(c: Node2D, slot: int, side: int, frame: int) -> void:
	Entry.radio_claim(c, DOOR["id"], "east", Vector2i(slot, side), frame)
