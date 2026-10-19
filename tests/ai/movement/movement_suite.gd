extends GameTestSuite
## The AI domain's movement game tests (tests/ai/movement/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ai_movement(id: String, test_parameters := cases("ai/movement")) -> void:
	await run_case(id)
