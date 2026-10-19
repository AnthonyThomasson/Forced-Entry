extends GameTest
## Ticket #65 round 2, `docs/tactical-entry.md` E2 / "Bodies on the way": the regression of
## `stack_reach_garage_home_garage_six`'s scenario, a walk into a slot whose way a teammate closes
## by stepping into its own slot goes round by another way when there is one; it is never held there
## for good. The garage home (seed 1, furnished) doorway from the kitchen into the garage. Three
## teammates (invader puppets that radio their claims on the doorway, as an AI member does) hold
## slots 1 to 3 on its east side, so the invader (ENTER the doorway, scripted Von) claims slot 4,
## which stands west of slots 1 and 3. Slots 1 and 2 are taken from the start; slot 3's holder waits
## off it. The invader comes from the kitchen's far corner, from the east, and once it is on its way
## in east of slot 3 the third teammate steps into slot 3 and stands: slots 1 and 3 then stand
## closer together than two bodies, across the invader's way in. The way round by the hall stays
## open. The invader must reach slot 4 by it, within `REACH_S` s of the slot being closed, without
## giving the entry up or taking another slot. It does not force a held last leg (`Locomotion`'s
## straight last stretch after a way round ends short of the goal): where a route to a goal no way
## reaches ends is the navigation server's own choice, so that hold came up only in `garage_six` run
## in a loaded batch.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const DOOR := { "id": "door_500_-360" }
## The slots of a four-member stack on the doorway's east side
## (`stack_reach_garage_home_garage_six`'s points), and where slot 3's holder waits.
const SLOT_1 := Vector2(436, -318)
const SLOT_2 := Vector2(396, -338)
const SLOT_3 := Vector2(436, -274)
const SLOT_4 := Vector2(396, -294)
const WAIT_3 := Vector2(436, -200)
const START := Vector2(660, -30)
## The invader is on its way in east of slot 3 once it is this near slot 4 (px) with its x past slot
## 3's.
const CLOSE_NEAR := 110.0
## How long (s) after slot 3 is taken the invader may take to stand in slot 4: the way round by the
## hall, walked, and the hold's re-plan.
const REACH_S := 8.0
## Within this (px) of its slot's point it is in its slot (`Entry.SLOT_REACH` and a few px).
const SLOT_NEAR := 10.0


func describe() -> Dictionary:
	return {
		"name": "A way into a slot closed by a teammate goes round",
		"description": "An invader walking into slot 4 from the east finds the gap between slots 1 "
			+ "and 3 closed by a teammate stepping into slot 3; it takes the way round by the "
			+ "hall and reaches slot 4, without giving the entry up or taking another slot.",
		"tags": ["ai", "entry", "stack", "navigation", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1, "garage_home")
	Entry.rules(s, DOOR)
	Entry.npc(s, &"walker", START)
	s.actor(&"p1", &"puppet", SLOT_1, { "faction": &"invader", "max_health": 1.0e6 })
	s.actor(&"p2", &"puppet", SLOT_2, { "faction": &"invader", "max_health": 1.0e6 })
	s.actor(&"p3", &"puppet", WAIT_3, { "faction": &"invader", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var brain := Entry.brain(t, &"walker")
	var claim_frame := GameClock.frame()
	var st := {
		"radio_in": 0.0,
		"closed_at": INF,
		"in_slot_at": INF,
		"slots": [],
		"spot": Vector2.INF,
	}
	while t.time < 40.0:
		st["radio_in"] = float(st["radio_in"]) - 1.0 / Engine.physics_ticks_per_second
		if float(st["radio_in"]) <= 0.0:
			st["radio_in"] = 0.5
			_radio(t.actor(&"p1"), 1, claim_frame)
			_radio(t.actor(&"p2"), 2, claim_frame)
			_radio(t.actor(&"p3"), 3, claim_frame)
		for c in Entry.calls(t, "claim", &"walker"):
			if not (st["slots"] as Array).has(int(c["slot"])):
				(st["slots"] as Array).append(int(c["slot"]))
		var e: Dictionary = Entry.entry(brain)
		if e.get("stack_point") is Vector2:
			st["spot"] = e["stack_point"]
		var here: Vector2 = walker.global_position
		if (st["closed_at"] == INF
				and String(e.get("phase", "")) == "approach"
				and here.x > SLOT_3.x + 20.0
				and here.distance_to(SLOT_4) < CLOSE_NEAR):
			st["closed_at"] = t.time
			t.puppet(&"p3").walk_to(SLOT_3)
		if (st["in_slot_at"] == INF
				and String(e.get("phase", "")) == "stack"
				and here.distance_to(st["spot"]) <= SLOT_NEAR):
			st["in_slot_at"] = t.time
			break
		if st["closed_at"] != INF and t.time > float(st["closed_at"]) + REACH_S + 4.0:
			break
		t.trace("walker_to_slot_4", here.distance_to(SLOT_4))
		await t.frames(1)
	if not t.require(
			(st["slots"] as Array).size() > 0 and int(st["slots"][0]) == 4,
			"premise: it claimed slot 4 behind the teammates' 1 to 3 (%s)" % [st["slots"]],
	):
		return
	if not t.require(
			st["closed_at"] != INF,
			"premise: it came in from the east of slot 3, and slot 3's holder stepped into it then",
	):
		return
	t.check(Entry.calls(t, "abort", &"walker").is_empty(), "it never gives the entry up (abort)")
	t.check((st["slots"] as Array).size() == 1, "it keeps slot 4 (claimed %s)" % [st["slots"]])
	t.check(
		st["in_slot_at"] != INF and float(st["in_slot_at"]) - float(st["closed_at"]) <= REACH_S,
		("it reaches slot 4 by the way round within %.0f s of slot 3 being taken (closed at %.1f "
				+ "s, in its slot at %.1f s)") % [REACH_S, st["closed_at"], st["in_slot_at"]],
	)


## A puppet radios its claim on the doorway the way an AI member does: slot `slot` on the stack's
## side (-1), still on its way (`claim`).
static func _radio(c: Node2D, slot: int, frame: int) -> void:
	EventBus.post(
		&"callout",
		{
			"speaker": c, "faction": c.faction, "position": c.global_position, "status": "",
			"path": "", "label": "", "target_id": 0, "point": Vector2.ZERO, "opening": DOOR["id"],
			"into": "garage", "slot": slot, "side": -1, "entry_step": "claim", "claim_frame": frame,
			"claim_pos": c.global_position,
		},
	)
