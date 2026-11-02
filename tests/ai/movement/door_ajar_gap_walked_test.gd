extends GameTest
## Issue #183 (`docs/doors.md` DR14): a walker whose way runs through a door that stands short of
## its open stop but open by a gap that clears a body (the body, the leaf's thickness and room each
## side) walks through the gap between the leaf's free end and the latch jamb as the door stands,
## and round the leaf's free end to a point behind it: it neither opens the door nor walks into the
## leaf that stands across the middle of its doorway.
##
## The hall and bedroom of `door_open_leaf_walked_round`, the door open at 70 degrees (a 55 px gap,
## well over the 42 px a body of radius 14 needs past a 6 px leaf with 4 px each side), hinged on
## the north jamb: its leaf stands across the bedroom side of the doorway, the gunfire behind it. A
## defender in the hall goes to the gunfire (scripted Von, investigate). The defender must get there
## with the door still ajar where it stood, never used open (no door `open` event, interface 10),
## and its body (a circle of the spec's radius) must never overlap the leaf's rectangle where it
## stands at that moment.

const Probe := preload("res://tests/_ai/investigate_probe.gd")
const HALL := Rect2(0, 0, 400, 400)
const BEDROOM := Rect2(400, 0, 300, 400)
const DOORWAY := Vector2(400, 200)
## Half a wall in from the north jamb, as a house hangs its doors: 48 px between the jambs.
const HINGE := Vector2(400, 176)
## Short of the open stop (DR3: 90) and of the carve's slack (DR14: 80), by a clean gap.
const AJAR := 70.0
## The gap (px) that clears a body: its width, the leaf's thickness and 4 px each side (DR14).
const CLEAN := 2.0 * 14.0 + 6.0 + 8.0
## Still where it stood within this many degrees: neither opened nor pushed round.
const KEPT := 3.0
## Just past the leaf's far side, in the bedroom: the straight way there from the doorway runs
## over the leaf.
const GUNFIRE := Vector2(445, 120)
## A character's body radius (px), the spec's number (DR14: a 34 px pass for a body of radius 14).
const BODY_RADIUS := 14.0
## Within this many px of the gunfire the defender has got there.
const ARRIVED := 30.0


func describe() -> Dictionary:
	return {
		"name": "A walker goes through an ajar door's gap",
		"description": "A defender walking to gunfire behind a door open at 70 degrees goes "
			+ "through the gap by its latch and round the leaf, leaving the door as it stood.",
		"tags": ["ai", "movement", "door", "navigation", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "hall", "type": "hallway", "rect": HALL },
		{ "key": "bedroom", "type": "bedroom", "rect": BEDROOM },
	], [
		{
			"pos": DOORWAY, "width": 60.0,
			"door": {
				"name": "bedroom_door", "material": "hollow", "style": "flush",
				"hinge": HINGE, "swing_into": Vector2.RIGHT, "angle": AJAR,
			},
		},
	])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.von_script([{ "pick": "investigate" }])
	s.actor(&"npc", &"defender", Vector2(300, 260), { "facing": Vector2.RIGHT })


func run(t: TestContext) -> void:
	var door: Node = t.object(&"bedroom_door")
	var npc := t.actor(&"npc")
	if not t.require(
			absf(door.angle() - AJAR) < 1.0 and door.gap() >= CLEAN,
			"the door stands short of its stop by a clean gap (%.0f deg, gap %.0f px)"
				% [door.angle(), door.gap()],
	):
		return
	Probe.gunfire(GUNFIRE)
	var brain := t.controller(&"npc", &"current_act")
	if not t.require(
			await t.until(
				func(): return String(brain.current_act()).begins_with("investigate/"), 4.0,
			),
			"the defender is sent to the gunfire (%s)" % brain.current_act(),
	):
		return
	var walk := await _walk(t, npc, door)
	t.check(
		npc.global_position.distance_to(GUNFIRE) <= ARRIVED,
		"it got to the gunfire (at %s after %.1f s)" % [npc.global_position.round(), walk["time"]],
	)
	t.check(
		absf(door.angle() - AJAR) <= KEPT,
		"the door still stood ajar where it was when it got there (%.0f deg)" % door.angle(),
	)
	t.check(
		not t.happened(&"door", func(d): return d["door"] == door and d["stage"] == &"open"),
		"it never used the door open (no door `open` event)",
	)
	t.check(
		walk["touched_at"] == Vector2.INF,
		"it never touched the leaf (closest %.1f px, touching at %s)"
			% [walk["closest"], walk["touched_at"]],
	)


## Follow `npc`, every physics frame for up to 15 s, until it is at the gunfire: how long it
## took (`time`), how close it
## came to the leaf's rectangle where it stood each moment (`closest`), where it first touched it
## (`touched_at`, INF never).
static func _walk(t: TestContext, npc: Node2D, door: Node) -> Dictionary:
	var out := { "time": 0.0, "closest": INF, "touched_at": Vector2.INF }
	var size: Vector2 = door.leaf_size()
	var start := t.time
	while out["time"] < 15.0 and npc.global_position.distance_to(GUNFIRE) > ARRIVED:
		await t.frames(1)  # Every physics frame: a graze lasts only a few.
		out["time"] = t.time - start
		var d := _to_leaf(door.leaf_pose(door.angle()), size, npc.global_position)
		if d < out["closest"]:
			out["closest"] = d
			if d <= BODY_RADIUS and out["touched_at"] == Vector2.INF:
				out["touched_at"] = npc.global_position.round()
	return out


## How far `p` is from the leaf's rectangle (`size`, centred on `pose`): 0 inside it.
static func _to_leaf(pose: Transform2D, size: Vector2, p: Vector2) -> float:
	var local: Vector2 = pose.affine_inverse() * p
	var half := size * 0.5
	var on := Vector2(clampf(local.x, -half.x, half.x), clampf(local.y, -half.y, half.y))
	return local.distance_to(on)
