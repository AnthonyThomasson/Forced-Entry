extends GameTestSuite
## The general domain's game tests (tests/general/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_general(id: String, test_parameters := cases("general")) -> void:
	await run_case(id)
