extends GameTest
## #193 phase 3, L2 in 3D: a doorway is lit, not a dark strip. Rooms meet at the walls' centre
## lines, so the room map (`ToonLight.set_rooms`) gives every spot of the opening between two rooms
## to one of them, the half across the wall to the one and the half beyond to the other: a light
## of either reaches its half and the two meet, and 2D's spill through a door shows as the pool of
## the room on each side. Every interior opening of the house resolves on both sides of its wall
## to its two rooms, along its whole width; the front door's inside is its room's.
##
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D` and Art's `ToonLight.room_at`
## (the room map's id at a world point), and the house's `WorldGen.get_openings`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
## Half a wall (the house plans' 12) and how many spots along the opening are read.
const HALF_WALL := 6.0
const ALONG := 5


func describe() -> Dictionary:
	return {
		"name": "A doorway between two rooms is in those rooms' map, with no strip of none",
		"description": "Along every opening of a house, a spot half a wall inside each of its "
			+ "rooms is in that room's map.",
		"tags": ["lighting", "3d", "doorway"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.house(1)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var lighting := Probe.light(t, t.rooms)
	if lighting == null:
		return
	var interior := 0
	for opening: Dictionary in WorldGen.get_openings(t.world.house):
		_check_opening(t, opening)
		if (opening["rooms"] as Array).size() == 2:
			interior += 1
	t.check(interior > 0, "the house has interior openings (%d)" % interior)


## Spots along `opening`, half a wall inside each of its rooms, are in that room's map.
func _check_opening(t: TestContext, opening: Dictionary) -> void:
	var names: Array = opening["rooms"]
	var out: Array = opening["outward"]
	var across := out[0] as Vector2
	var along := Vector2(-across.y, across.x)
	var reach: float = float(opening["width"]) * 0.4
	for k in ALONG:
		var spot: Vector2 = opening["pos"] + along * lerpf(-reach, reach, float(k) / (ALONG - 1))
		for side in names.size():
			var inside := spot - (out[side] as Vector2) * HALF_WALL
			var id := ToonLight.room_at(inside)
			t.check(
				id != 0 and id == Probe.room_at(t.rooms, inside)
					and String(t.rooms[id - 1]["key"]) == names[side],
				"%s's opening at %s is in %s inside" % [names, spot.round(), names[side]],
			)
