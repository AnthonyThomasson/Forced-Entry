extends GameTestSuite
## The worldgen domain's game tests (tests/worldgen/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_worldgen(id: String, test_parameters := cases("worldgen")) -> void:
	await run_case(id)
