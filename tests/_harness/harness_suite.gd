extends GameTestSuite
## The harness's own self-tests, run by `--self-test` (tests/_harness/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_harness(id: String, test_parameters := cases("_harness")) -> void:
	await run_case(id)
