extends GameTest
## Issue #183 (`docs/doors.md` DR14): a door open wide enough to pass is no obstacle in the
## doorway, but its leaf stands in the room it swings into, and a walker plans round it there as
## round any other solid thing, instead of walking into it.
##
## A hand-laid hall and bedroom, the doorway between them with a hollow door hinged on its north
## jamb, swinging into the bedroom and standing fully open: its leaf lies out from the hinge into
## the bedroom, along the wall's normal. Gunfire is heard in the bedroom just past the leaf's far
## side, so the straight way from the doorway to it crosses the leaf. A defender in the hall goes to
## it (scripted Von, investigate). It must reach the gunfire without once touching the leaf: its
## body (a circle of the spec's radius) never overlaps the leaf's rectangle.

const Probe := preload("res://tests/_ai/investigate_probe.gd")
const HALL := Rect2(0, 0, 400, 400)
const BEDROOM := Rect2(400, 0, 300, 400)
const DOORWAY := Vector2(400, 200)
## Half a wall in from the north jamb, as a house hangs its doors: 48 px between the jambs.
const HINGE := Vector2(400, 176)
## Fully open: the spec's open stop (DR3).
const OPEN := 90.0
## Just past the leaf's far side, in the bedroom: the straight way there from the doorway runs
## over the leaf.
const GUNFIRE := Vector2(445, 120)
## A character's body radius (px), the spec's number (DR14: a 34 px pass for a body of radius 14).
const BODY_RADIUS := 14.0
## Within this many px of the gunfire the defender has got there.
const ARRIVED := 30.0


func describe() -> Dictionary:
	return {
		"name": "A walker goes round an open door's leaf",
		"description": "A defender walking to gunfire past a fully open door reaches it without "
			+ "touching the leaf that stands in its straight way.",
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
				"hinge": HINGE, "swing_into": Vector2.RIGHT, "angle": OPEN,
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
	if not t.require(door.angle() >= OPEN - 1.0, "the door stands open (%.0f deg)" % door.angle()):
		return
	var pose: Transform2D = door.leaf_pose(door.angle())
	var size: Vector2 = door.leaf_size()
	var a: Vector2 = pose * Vector2(-size.x * 0.5, 0.0)
	var b: Vector2 = pose * Vector2(size.x * 0.5, 0.0)
	if not t.require(
			BEDROOM.has_point(b) and _crosses(DOORWAY, GUNFIRE, a, b),
			"the leaf (%s..%s) stands in the bedroom across the straight way"
				% [a.round(), b.round()],
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
	var walk := await _walk(t, npc, pose, size)
	t.check(
		npc.global_position.distance_to(GUNFIRE) <= ARRIVED,
		"it got to the gunfire (at %s after %.1f s)" % [npc.global_position.round(), walk["time"]],
	)
	t.check(
		walk["touched_at"] == Vector2.INF,
		"it never touched the leaf (closest %.1f px, touching at %s)"
			% [walk["closest"], walk["touched_at"]],
	)


## Follow `npc` for up to 15 s until it is at the gunfire: how long it took (`time`), how close it
## came to the leaf's rectangle (`closest`) and where it first touched it (`touched_at`, INF never).
static func _walk(t: TestContext, npc: Node2D, pose: Transform2D, size: Vector2) -> Dictionary:
	var out := { "time": 0.0, "closest": INF, "touched_at": Vector2.INF }
	while out["time"] < 15.0 and npc.global_position.distance_to(GUNFIRE) > ARRIVED:
		await t.seconds(0.05)
		out["time"] += 0.05
		var d := _to_leaf(pose, size, npc.global_position)
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


## Whether segment p1-p2 crosses segment q1-q2.
static func _crosses(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> bool:
	return Geometry2D.segment_intersects_segment(p1, p2, q1, q2) != null
