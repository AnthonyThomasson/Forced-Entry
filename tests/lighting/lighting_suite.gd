extends GameTestSuite
## The lighting domain's game tests (tests/lighting/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_lighting(id: String, test_parameters := cases("lighting")) -> void:
	await run_case(id)
