extends GameTestSuite
## The physics domain's game tests (tests/physics/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_physics(id: String, test_parameters := cases("physics")) -> void:
	await run_case(id)
