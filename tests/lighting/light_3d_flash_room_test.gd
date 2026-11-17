extends GameTest
## #193 phase 3, L9 in 3D: a flash lights its own room, as every light does (the room map): a shot
## in a room is a flash of that room, one just outside a room's rect (a muzzle in a doorway or
## against a wall, within `flash_room_slack`) too, one on the street the street's (it reaches the
## spots in no room, never a room's inside). With no rooms nothing is clipped.
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D`: `flashes()`; a light's meta
## `room`, `street_of`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A 3D flash lights the room it stands in, the street when it stands in none",
		"description": "A shot in a house's room is a flash of that room and not a street light; "
			+ "a muzzle a few px outside its rect is that room's; one far outside is the street's.",
		"tags": ["lighting", "3d", "flash"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var lighting := Probe.light(t, t.rooms)
	if lighting == null:
		return
	var rect: Rect2 = t.rooms[0]["rect"]
	for room: Dictionary in t.rooms:
		if (room["rect"] as Rect2).position.x < rect.position.x:
			rect = room["rect"]
	var id := Probe.room_at(t.rooms, rect.get_center())
	_shoot(t, lighting, rect.get_center(), [id, false], "in the room")
	_shoot(
		t,
		lighting,
		rect.position + Vector2(-4, 40),
		[id, false],
		"a doorway's width outside it",
	)
	_shoot(t, lighting, rect.position + Vector2(-2000, -2000), [0, true], "far outside every room")


## A shot at `at` lights a flash standing as `want` says: `[room id (0 none), a street light]`.
func _shoot(
	t: TestContext,
	lighting: WorldLighting3D,
	at: Vector2,
	want: Array,
	what: String,
) -> void:
	EventBus.post(&"shot", { "position": at })
	var l := Probe.flash_at(lighting, at)
	if not t.require(l != null, "the shot %s lights a flash" % what):
		return
	t.expect_eq(Probe.room_of(l), want[0], "the flash %s is in room %d" % [what, want[0]])
	t.expect_eq(
		Probe.street_of(l),
		want[1],
		"and is %sa street light" % ("" if want[1] else "not "),
	)
