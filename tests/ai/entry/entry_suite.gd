extends GameTestSuite
## The AI domain's entry game tests (tests/ai/entry/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ai_entry(id: String, test_parameters := cases("ai/entry")) -> void:
	await run_case(id)
