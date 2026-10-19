extends GameTest
## Ticket #65 round 2, `docs/tactical-entry.md` E2 (the stack moves up): a member does not move up
## while the slot's holder, still on its way, may be within `MOVE_UP_REACH` + `MOVE_UP_MARGIN` of
## the slot the move-up would hand it, or the two meet mid-swap and the stack jams
## (`stack_reach_garage_home_garage_six`: the mover stood a stride off its old slot and the
## latecomer a stride off the new one, each reading the other's slot as taken). The garage home
## (seed 1, furnished) doorway from the kitchen into the garage, the stack on its east side. Two
## teammates (invader puppets that radio their claims, as an AI member does) stand on slots 1 and 2;
## the invader (ENTER the doorway, scripted Von) claims slot 4 and walks into it from the south. The
## third teammate holds slot 3 still on its way (its claim at `claim`), standing `LATE_FROM` px from
## slot 4 at `LATE_AT`: farther from slot 3 than the invader in slot 4, so the move-up's other tests
## hold, and near enough to slot 4 to meet the invader's step. Once the invader stands in slot 4 the
## third teammate comes in: to slot 3 when the invader stays, or, when the invader has moved up into
## slot 3, to slot 4 as an AI latecomer does, stopping where `garage_six`'s latecomer stood held
## (`HELD_AT`, a stride off slot 3). The invader must not move up, and must stand in its slot.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const DOOR := { "id": "door_500_-360" }
## The slots of a four-member stack on the doorway's east side
## (`stack_reach_garage_home_garage_six`'s points).
const SLOT_1 := Vector2(436, -318)
const SLOT_2 := Vector2(396, -338)
const SLOT_3 := Vector2(436, -274)
const SLOT_4 := Vector2(396, -294)
const START := Vector2(396, -200)
## Where slot 3's holder stands until the invader is in slot 4 (`LATE_FROM` px from slot 4, 65 px
## from slot 3), and where it stops when it takes slot 4 after a move-up (where `garage_six`'s
## latecomer stood held, 21 px from slot 3).
const LATE_AT := Vector2(500, -262)
const HELD_AT := Vector2(457, -271)
## How long (s) the invader is watched in slot 4 for a move-up before the third teammate comes in.
const MOVE_WATCH_S := 1.5
## How long (s) after the third teammate comes in the invader may take to stand in its slot.
const SETTLE_S := 6.0
## Within this (px) of its slot's point it is in its slot (`Entry.SLOT_REACH` and a few px).
const SLOT_NEAR := 10.0


func describe() -> Dictionary:
	return {
		"name": "No move-up while the latecomer is near",
		"description": "An invader in slot 4 does not move up into slot 3 while slot 3's holder, "
			+ "still on its way, stands near enough to slot 4 to meet its step; it stands in its "
			+ "slot as the holder comes in.",
		"tags": ["ai", "entry", "stack", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1, "garage_home")
	Entry.rules(s, DOOR)
	Entry.npc(s, &"walker", START)
	s.actor(&"p1", &"puppet", SLOT_1, { "faction": &"invader", "max_health": 1.0e6 })
	s.actor(&"p2", &"puppet", SLOT_2, { "faction": &"invader", "max_health": 1.0e6 })
	s.actor(&"p3", &"puppet", LATE_AT, { "faction": &"invader", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var brain := Entry.brain(t, &"walker")
	var claim_frame := GameClock.frame()
	var st := {
		"radio_in": 0.0, "p3_slot": 3, "in_4_at": INF, "came_at": INF, "moved_at": INF,
		"settled_at": INF,
	}
	while t.time < 40.0:
		st["radio_in"] = float(st["radio_in"]) - 1.0 / Engine.physics_ticks_per_second
		if float(st["radio_in"]) <= 0.0:
			st["radio_in"] = 0.5
			_radio(t.actor(&"p1"), 1, claim_frame)
			_radio(t.actor(&"p2"), 2, claim_frame)
			_radio(t.actor(&"p3"), int(st["p3_slot"]), claim_frame)
		var e: Dictionary = Entry.entry(brain)
		var spot: Vector2 = e["stack_point"] if e.get("stack_point") is Vector2 else Vector2.INF
		var here: Vector2 = walker.global_position
		var in_slot := String(e.get("phase", "")) == "stack" and here.distance_to(spot) <= SLOT_NEAR
		if (st["moved_at"] == INF
				and Entry.calls(t, "claim", &"walker").any(func(c): return int(c["slot"]) == 3)):
			st["moved_at"] = t.time
		if st["in_4_at"] == INF and in_slot and int(e.get("slot", 0)) == 4:
			st["in_4_at"] = t.time
		if (st["came_at"] == INF
				and st["in_4_at"] != INF
				and (st["moved_at"] != INF or t.time >= float(st["in_4_at"]) + MOVE_WATCH_S)):
			st["came_at"] = t.time
			if st["moved_at"] != INF:
				# The latecomer takes the slot the move-up freed, as an AI member does, and is held
				# a stride off slot 3.
				st["p3_slot"] = 4
				t.puppet(&"p3").walk_to(HELD_AT)
			else:
				t.puppet(&"p3").walk_to(SLOT_3)
		if st["came_at"] != INF and in_slot and t.time >= float(st["came_at"]) + 1.0:
			st["settled_at"] = t.time
			break
		if st["came_at"] != INF and t.time > float(st["came_at"]) + SETTLE_S:
			break
		t.trace("walker_to_slot", here.distance_to(spot) if spot != Vector2.INF else -1.0)
		await t.frames(1)
	if not t.require(
			st["in_4_at"] != INF,
			"premise: it claimed slot 4 behind the teammates' 1 to 3 and stood in it",
	):
		return
	t.check(
		st["moved_at"] == INF,
		("it does not move up into slot 3 while slot 3's holder stands %.0f px from slot 4 (moved "
				+ "up at %s s)")
			% [
				LATE_AT.distance_to(SLOT_4),
				"never" if st["moved_at"] == INF else "%.1f" % st["moved_at"],
			],
	)
	t.check(Entry.calls(t, "abort", &"walker").is_empty(), "it never gives the entry up (abort)")
	t.check(
		st["settled_at"] != INF,
		("it stands in its slot within %.0f s of the holder coming in (came at %.1f s, settled at "
				+ "%s)")
			% [
				SETTLE_S,
				st["came_at"],
				"never" if st["settled_at"] == INF else "%.1f s" % st["settled_at"],
			],
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
