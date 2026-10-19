extends GameTestSuite
## The audio domain's game tests (tests/audio/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_audio(id: String, test_parameters := cases("audio")) -> void:
	await run_case(id)
