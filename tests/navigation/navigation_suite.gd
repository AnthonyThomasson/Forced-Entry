extends GameTestSuite
## The navigation domain's game tests (tests/navigation/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_navigation(id: String, test_parameters := cases("navigation")) -> void:
	await run_case(id)
