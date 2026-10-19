extends GameTestSuite
## The AI domain's flank game tests (tests/ai/flank/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ai_flank(id: String, test_parameters := cases("ai/flank")) -> void:
	await run_case(id)
