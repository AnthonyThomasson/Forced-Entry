extends GameTestSuite
## The art domain's game tests (tests/art/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_art(id: String, test_parameters := cases("art")) -> void:
	await run_case(id)
