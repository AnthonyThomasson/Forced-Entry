extends GameTestSuite
## The AI domain's debug game tests (tests/ai/debug/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ai_debug(id: String, test_parameters := cases("ai/debug")) -> void:
	await run_case(id)
