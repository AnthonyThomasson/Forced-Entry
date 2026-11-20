extends GameTest
## A vehicle's pile (`docs/vehicles.md` V6): the bodies pressed one against the next in front of the
## one the bumper met are found through the twin space, not the 2D one. A person with another
## person right ahead of it is a pile of two; a person with a chair pressed against it and a second
## person pressed against the chair's far side is a pile of three (the chair is followed into the
## person it presses); a person alone in the open is a pile of one; a person off to the side of the
## line is not in it.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const CAR_AT := Vector2(300, 300)
## The first person of each row: x of the bumper's meeting, the rows 150 px apart.
const FIRST_X := 450.0
const ROW_ONE := 200.0
const ROW_TWO := 350.0
const ROW_THREE := 500.0
## A chair's half width (28 px square) and the gap (px) a pressed body is placed inside the touch.
const CHAIR_HALF := 14.0
const PRESSED := 1.0


func describe() -> Dictionary:
	return {
		"name": "A vehicle's pile is found in the twin space",
		"description": "The pile a bumper's blow carries on (people pressed against people, and a "
			+ "chair against the person behind it) is the bodies pressed one against the next.",
		"tags": ["vehicle", "car", "character", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", CAR_AT)
	s.actor(&"first", &"puppet", Vector2(FIRST_X, ROW_ONE))
	s.actor(&"behind", &"puppet", Vector2(FIRST_X + 36.0, ROW_ONE))
	s.actor(&"aside", &"puppet", Vector2(FIRST_X, ROW_ONE + 80.0))
	s.actor(&"lone", &"puppet", Vector2(FIRST_X, ROW_THREE))
	s.actor(&"pusher", &"puppet", Vector2(FIRST_X, ROW_TWO))
	s.object(&"chair", "armchair", Vector2(FIRST_X + 40.0, ROW_TWO))
	s.actor(&"pressed", &"puppet", Vector2(FIRST_X + 80.0, ROW_TWO))


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"first", &"behind", &"aside", &"lone", &"pusher", &"pressed"]):
		return
	await t.frames(4)
	var contacts: VehicleContacts = (t.vehicle(&"car") as Node2D).contacts
	_place_against(t.actor(&"behind"), t.actor(&"first"))
	_place_against(t.actor(&"pressed"), t.object(&"chair"))
	_place_against(t.object(&"chair"), t.actor(&"pusher"))
	await t.frames(4)
	var two := contacts._pile(t.actor(&"first"), Vector2.RIGHT)
	_expect(t, two, [t.actor(&"first"), t.actor(&"behind")], "a person and the one pressed ahead")
	var three := contacts._pile(t.actor(&"pusher"), Vector2.RIGHT)
	_expect(
		t, three, [t.actor(&"pusher"), t.object(&"chair"), t.actor(&"pressed")],
		"a person, the chair pressed ahead of it, the person pressed against the chair",
	)
	var one := contacts._pile(t.actor(&"lone"), Vector2.RIGHT)
	_expect(t, one, [t.actor(&"lone")], "a person alone in the open")


## Put `body` ahead of `against` (along +x) with its near edge `PRESSED` px inside `against`'s far
## edge: the half widths are read off the bodies' shapes' reach, a person's radius, a chair's 14.
func _place_against(body: Node2D, against: Node2D) -> void:
	var gap := _half(body) + _half(against) - PRESSED
	body.global_position = against.global_position + Vector2(gap, 0.0)


## The half width (px) of a person (`radius`) or a chair (`CHAIR_HALF`) along the push.
func _half(body: Node2D) -> float:
	return float(body.radius) if body.is_in_group(&"characters") else CHAIR_HALF


## The pile `pile` holds exactly `bodies`, in order, with nothing blocking it.
func _expect(t: TestContext, pile: Dictionary, bodies: Array, what: String) -> void:
	var found: Array = []
	for member: Dictionary in pile["members"]:
		found.append(member["body"])
	t.check(found == bodies, "%s: the pile is %s, not %s" % [what, _names(bodies), _names(found)])
	t.check(pile["blocked"] == null, "%s: nothing blocks it" % what)


func _names(bodies: Array) -> String:
	var names: Array[String] = []
	for body: Node in bodies:
		names.append(String(body.name))
	return ", ".join(names)
