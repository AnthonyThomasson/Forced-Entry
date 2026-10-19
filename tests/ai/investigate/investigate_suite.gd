extends GameTestSuite
## The AI domain's investigate game tests (tests/ai/investigate/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ai_investigate(id: String, test_parameters := cases("ai/investigate")) -> void:
	await run_case(id)
