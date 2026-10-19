extends GameTestSuite
## The objects domain's game tests (tests/objects/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_objects(id: String, test_parameters := cases("objects")) -> void:
	await run_case(id)
