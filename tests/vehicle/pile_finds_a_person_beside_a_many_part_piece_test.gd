extends GameTest
## A vehicle's pile (`docs/vehicles.md` V6) is not cut short by a crowd of shapes: a piece's twin
## has one shape for each of its parts, and a body with many of them stands in the band a pile
## member is read in, so a capped answer of the twin space would drop the person pressed against
## the chair. The pile of a person, the chair against it and the person against the chair is still
## all three with a piece of many parts beside them.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const CAR_AT := Vector2(300, 300)
const FIRST_X := 450.0
const ROW := 350.0
## The half widths (px) of a chair (28 px square) and the gap a pressed body is placed inside the
## touch.
const CHAIR_HALF := 14.0
const PRESSED := 1.0
## How many parts (shapes) the piece beside the pile has, well over the answer a query could hold.
const PARTS := 60


func describe() -> Dictionary:
	return {
		"name": "A vehicle's pile is found beside a piece of many parts",
		"description": "A person, a chair pressed against it and a second person pressed against "
			+ "the chair are a pile of three with a piece of sixty parts beside them.",
		"tags": ["vehicle", "car", "character", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.actor(&"pusher", &"puppet", Vector2(FIRST_X, ROW))
	s.object(&"chair", "armchair", Vector2(FIRST_X + 40.0, ROW))
	s.actor(&"pressed", &"puppet", Vector2(FIRST_X + 80.0, ROW))
	s.object(&"fat", "armchair", Vector2(FIRST_X + 40.0, ROW + 90.0))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"pusher", &"pressed"]):
		return
	await t.frames(4)
	var fat := TwinSpace.twin_for(t.object(&"fat")) as Node3D
	if not t.require(fat != null, "premise: the piece beside the pile has a twin"):
		return
	for i in PARTS:
		var part := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 20.0, 4.0)
		part.shape = box
		part.position = Vector3(
			float(i % 6) * 5.0 - 12.0,
			10.0,
			floorf(float(i) / 6.0) * 5.0 - 25.0,
		)
		fat.add_child(part)
	var contacts: VehicleContacts = (t.vehicle(&"car") as Node2D).contacts
	_place_against(t.object(&"chair"), t.actor(&"pusher"))
	_place_against(t.actor(&"pressed"), t.object(&"chair"))
	await t.frames(4)
	var pile := contacts._pile(t.actor(&"pusher"), Vector2.RIGHT)
	var found: Array = []
	for member: Dictionary in pile["members"]:
		found.append(member["body"])
	t.check(
		found == [t.actor(&"pusher"), t.object(&"chair"), t.actor(&"pressed")],
		"the pile is the person, the chair and the person against it, not %s" % [found],
	)


## Put `body` ahead of `against` (along +x) with its near edge `PRESSED` px inside `against`'s far
## edge: a person's half width is its radius, a chair's 14.
func _place_against(body: Node2D, against: Node2D) -> void:
	var gap := _half(body) + _half(against) - PRESSED
	body.global_position = against.global_position + Vector2(gap, 0.0)


## The half width (px) of a person (`radius`) or a chair (`CHAIR_HALF`) along the push.
func _half(body: Node2D) -> float:
	return float(body.radius) if body.is_in_group(&"characters") else CHAIR_HALF
