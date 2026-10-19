extends GameTestSuite
## The AI domain's gaze game tests (tests/ai/gaze/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_ai_gaze(id: String, test_parameters := cases("ai/gaze")) -> void:
	await run_case(id)
