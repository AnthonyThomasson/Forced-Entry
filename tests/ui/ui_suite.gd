extends GameTestSuite
## The ui domain's game tests (tests/ui/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ui(id: String, test_parameters := cases("ui")) -> void:
	await run_case(id)
