extends GameTest
## A door still nudges a walker clear of its leaf (interface 24, duck-typed) now the walker's 3D
## body is the truth (#194): the nudge moves the 2D body and the 3D body takes the new
## place (`CharacterTwin.follow`), so it does not snap back, and it walks on from there.

const JAMB := 20.0
const MOVED := 5.0


func describe() -> Dictionary:
	return {
		"name": "A door's nudge reaches the walker's 3D body",
		"description": "A puppet in the arc of a door opened toward it is moved clear; its 3D body "
			+ "stands where the 2D body was moved to, stays there, and walks on from there.",
		"tags": ["door", "nudge", "character", "3d", "twins", "leader"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 300) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 300) },
	], [
		{
			"pos": Vector2(400, 100), "width": 52.0,
			"door": {
				"name": "nudger", "material": "hollow", "style": "flush",
				"hinge": Vector2(400, 100 - JAMB), "swing_into": Vector2.RIGHT,
			},
		},
	])
	s.von_down()
	s.actor(&"pushed", &"puppet", Vector2(420, 108))


func run(t: TestContext) -> void:
	await t.seconds(0.4)
	var body: Node2D = t.actor(&"pushed")
	var lead := TwinSpace.twin_for(body) as CharacterBody3D
	if not t.require(lead != null, "premise: the walker has a 3D body"):
		return
	var start: Vector2 = body.global_position
	t.object(&"nudger").toggle(null)
	await t.seconds(1.0)
	t.check(
		body.global_position.distance_to(start) > MOVED,
		"the door nudged the walker (%.1f px)" % body.global_position.distance_to(start),
	)
	t.check(
		PlanSpace.plan_of(lead.global_position).distance_to(body.global_position) < 0.1,
		"its 3D body is where it was nudged to",
	)
	var nudged: Vector2 = body.global_position
	await t.seconds(0.5)
	t.check(
		body.global_position.distance_to(nudged) < 1.0,
		"it stays there (%.1f px)" % body.global_position.distance_to(nudged),
	)
	t.puppet(&"pushed").walk(Vector2.DOWN)
	await t.seconds(0.5)
	t.check(
		body.global_position.y > nudged.y + 20.0,
		"and walks on from the nudged place (%.1f px)" % (body.global_position.y - nudged.y),
	)
