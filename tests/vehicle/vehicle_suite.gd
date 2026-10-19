extends GameTestSuite
## The vehicle domain's game tests (tests/vehicle/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_vehicle(id: String, test_parameters := cases("vehicle")) -> void:
	await run_case(id)
