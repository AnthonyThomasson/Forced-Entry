extends GameTest
## A roof over a house's rooms (`ObjectTwins`, interface 29, #194 D11a): a roofed floor (a room of a
## house or a tower) is twinned with a slab at the walls' height over it, on its own layer
## (`PhysicsLayers.TWIN_ROOF`, outside `TWIN_ALL`, so a ray from the sky still reaches what is under
## it), which a lob under it is stopped by as by a real ceiling; a floor with no roof (the open
## ground, a roofless shell, the street) has none.

const Probe := preload("res://tests/_general/twin_probe.gd")
## The room's floor, and open ground east of it (no floor there: the sky is open over it).
const ROOM := Rect2(0, 0, 400, 400)
const OPEN := Rect2(600, 0, 400, 400)
## The walls' height: the roof's underside.
const WALLS := 96.0


func describe() -> Dictionary:
	return {
		"name": "A room has a roof at the walls' height and open ground has none",
		"description": "A ray dropped from the sky onto a room strikes its roof at 96 px; onto "
			+ "open ground it reaches the floor.",
		"tags": ["twins", "3d", "heights", "roof", "floor"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([{ "key": "room", "type": "living_room", "rect": ROOM }], [])


func run(t: TestContext) -> void:
	await t.frames(3)
	var roofs := PhysicsLayers.TWIN_ROOF
	var inside := Probe.top_at(t, ROOM.get_center(), roofs)
	t.check(inside >= WALLS, "a ray onto the room lands on its roof, at %.0f px" % inside)
	t.check(
		inside <= WALLS + 12.0,
		"the roof is a slab on the walls, not higher (%.0f px)" % inside,
	)
	var under := Probe.level(
		t,
		ROOM.get_center() + Vector2(-100, 0),
		ROOM.get_center() + Vector2(100, 0),
		WALLS - 10.0,
		roofs | PhysicsLayers.TWIN_ALL,
	)
	t.check(under.is_empty(), "under the roof the room is open at %.0f px" % (WALLS - 10.0))
	var open := Probe.top_at(t, OPEN.get_center(), roofs)
	t.check(open < -500.0, "over open ground there is no roof (%.1f px)" % open)
	# What a ray from the sky looks for (`TWIN_ALL`: the player's aim, a sight line) is under the
	# roof: it lands on the room's floor.
	var floor_hit := Probe.top_at(t, ROOM.get_center(), PhysicsLayers.TWIN_ALL)
	t.check(floor_hit < 5.0, "a ray from the sky reaches the room's floor (%.1f px)" % floor_hit)
