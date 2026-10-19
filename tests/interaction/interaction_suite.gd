extends GameTestSuite
## The interaction domain's game tests (tests/interaction/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_interaction(id: String, test_parameters := cases("interaction")) -> void:
	await run_case(id)
