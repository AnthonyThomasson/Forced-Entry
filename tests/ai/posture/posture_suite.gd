extends GameTestSuite
## The AI domain's posture game tests (tests/ai/posture/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ai_posture(id: String, test_parameters := cases("ai/posture")) -> void:
	await run_case(id)
