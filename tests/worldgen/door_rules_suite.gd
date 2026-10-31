extends UnitSuite
## Native unit suite (pure logic) for World-Gen's `DoorRules` (docs/doors.md DR2): the chance of a
## door between two rooms comes from the more private room's type. It supplements the simulation
## test `worldgen/door_placement`, which cannot build a floorplan with two hallways joined (none
## exists). The expected values are the spec's: bathrooms and netrunner dens always, bedrooms,
## offices and ripperdocs mostly, kitchens, living spaces and studios rarely, two hallways never.


func test_two_hallways_never_have_a_door() -> void:
	assert_float(DoorRules.chance("hallway", "hallway")).is_equal(0.0)


func test_a_bathroom_always_has_its_door_whatever_it_opens_onto() -> void:
	for other in ["hallway", "bedroom", "living_room", "studio", "kitchen_living"]:
		assert_float(DoorRules.chance("bathroom", other)).is_equal(1.0)
		assert_float(DoorRules.chance(other, "bathroom")).is_equal(1.0)


func test_the_netrunner_den_always_has_its_door() -> void:
	assert_float(DoorRules.chance("netrunner_den", "ripperdoc")).is_equal(1.0)


func test_a_bedroom_office_or_ripperdoc_door_is_mostly_there() -> void:
	for room in ["bedroom", "home_office", "ripperdoc"]:
		var chance := DoorRules.chance(room, "living_room")
		assert_bool(chance > 0.5 and chance < 1.0).override_failure_message(
			"%s: a chance of %s is not 'mostly'" % [room, chance],
		).is_true()


func test_a_kitchen_living_space_or_studio_door_is_rarely_there() -> void:
	for room in ["kitchen", "living_room", "kitchen_living", "studio"]:
		var chance := DoorRules.chance(room, "hallway")
		assert_bool(chance > 0.0 and chance < 0.5).override_failure_message(
			"%s: a chance of %s is not 'rarely'" % [room, chance],
		).is_true()


func test_the_more_private_room_sets_the_chance() -> void:
	assert_float(DoorRules.chance("bedroom", "bathroom")).is_equal(1.0)
	assert_bool(DoorRules.rank("bathroom") > DoorRules.rank("bedroom")).is_true()
	assert_bool(DoorRules.rank("bedroom") > DoorRules.rank("living_room")).is_true()
	assert_bool(DoorRules.rank("living_room") > DoorRules.rank("hallway")).is_true()
