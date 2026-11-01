extends GameTestSuite
## The vision domain's game tests (tests/vision/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_vision(id: String, test_parameters := cases("vision")) -> void:
	await run_case(id)
