extends UnitSuite
## Native unit suite for `CharacterVisionConfig` (`docs/player-vision.md` V1): the human sees what
## the NPCs see, by their default numbers. The three numbers are the spec's, and they are the ones
## an NPC's `NpcSensesTuning` starts with, so a retune of one that forgets the other fails here.
## (What
## it looks over is no number: the height of its eye in its posture, `BodyHeights`.)


func test_a_character_sees_by_the_specs_numbers() -> void:
	assert_float(CharacterVisionConfig.fov_degrees).is_equal(110.0)
	assert_float(CharacterVisionConfig.view_distance).is_equal(2520.0)
	assert_float(CharacterVisionConfig.awareness_radius).is_equal(48.0)


func test_they_are_the_numbers_an_npc_starts_with() -> void:
	var senses: NpcSensesTuning = auto_free(NpcSensesTuning.new())
	assert_float(CharacterVisionConfig.fov_degrees).is_equal(senses.fov_degrees)
	assert_float(CharacterVisionConfig.view_distance).is_equal(senses.view_distance)
	assert_float(CharacterVisionConfig.awareness_radius).is_equal(senses.awareness_radius)
