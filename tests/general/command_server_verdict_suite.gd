extends UnitSuite
## Native unit suite (pure logic) for the dev command server's `match` verdict
## (`command_server.gd` `verdict_of`), which `tools/match.py` scores rounds by: General's
## `MatchVerdict.decide`, the rule the MatchHUD decides by too, so a match of any size is decided
## when a side is wiped out, not at its first death. The expected verdicts are read off that rule:
## "none" while every side has someone alive; the side left standing, by its faction, once another
## is wiped out (in a 1v1 the survivor's name, where the HUD names a lone survivor in any match);
## "draw" with nobody, or more than one side, left.

const CommandServer := preload("res://scenes/general/command_server.gd")


## A side of `count` combatants of `faction`, the first `dead` of them dead, named `base`,
## `base 2`, ... as Main names its NPCs.
func _side(faction: StringName, base: String, count: int, dead := 0) -> Array:
	var out: Array = []
	for i in count:
		var b: Body = auto_free(Body.new())
		b.name = base if i == 0 else "%s %d" % [base, i + 1]
		b.faction = faction
		b.is_dead = i < dead
		out.append(b)
	return out


func test_a_match_with_both_sides_standing_is_ongoing() -> void:
	var fight := _side(&"household", "Defender", 3) + _side(&"invader", "Invader", 3)
	assert_str(CommandServer.verdict_of(fight)).is_equal("none")


func test_a_first_death_in_a_larger_match_decides_nothing() -> void:
	var fight := _side(&"household", "Defender", 3, 1) + _side(&"invader", "Invader", 3, 2)
	assert_str(CommandServer.verdict_of(fight)).is_equal("none")


func test_a_side_wiped_out_loses_to_the_side_left_standing() -> void:
	var fight := _side(&"household", "Defender", 5, 4) + _side(&"invader", "Invader", 5, 5)
	assert_str(CommandServer.verdict_of(fight)).is_equal("household")
	fight = _side(&"household", "Defender", 3, 3) + _side(&"invader", "Invader", 3, 1)
	assert_str(CommandServer.verdict_of(fight)).is_equal("invader")


func test_nobody_left_standing_is_a_draw() -> void:
	var fight := _side(&"household", "Defender", 3, 3) + _side(&"invader", "Invader", 3, 3)
	assert_str(CommandServer.verdict_of(fight)).is_equal("draw")


func test_a_1v1_names_the_survivor() -> void:
	var fight := _side(&"household", "Defender", 1, 1) + _side(&"invader", "Invader", 1)
	assert_str(CommandServer.verdict_of(fight)).is_equal("Invader")
	fight = _side(&"household", "Defender", 1, 1) + _side(&"invader", "Invader", 1, 1)
	assert_str(CommandServer.verdict_of(fight)).is_equal("draw")
	fight = _side(&"household", "Defender", 1) + _side(&"invader", "Invader", 1)
	assert_str(CommandServer.verdict_of(fight)).is_equal("none")


func test_two_sides_left_standing_after_a_third_falls_is_a_draw() -> void:
	var fight := (
		_side(&"household", "Defender", 2)
			+ _side(&"invader", "Invader", 2)
			+ _side(&"crew", "Crew", 2, 2)
	)
	assert_str(CommandServer.verdict_of(fight)).is_equal("draw")


func test_no_combatants_is_ongoing() -> void:
	assert_str(CommandServer.verdict_of([])).is_equal("none")


## A combatant as the verdict reads it: its `name`, `faction` and `is_dead`.
class Body:
	extends Node

	var faction: StringName
	var is_dead := false
