extends GameTestSuite
## The character domain's game tests (tests/character/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_character(id: String, test_parameters := cases("character")) -> void:
	await run_case(id)
