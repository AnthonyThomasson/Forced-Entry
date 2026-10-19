extends GameTestSuite
## The items domain's game tests (tests/items/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_items(id: String, test_parameters := cases("items")) -> void:
	await run_case(id)
