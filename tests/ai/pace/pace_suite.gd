extends GameTestSuite
## The AI domain's beat game tests (tests/ai/pace/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ai_pace(id: String, test_parameters := cases("ai/pace")) -> void:
	await run_case(id)
