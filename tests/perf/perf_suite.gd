extends GameTestSuite
## The perf domain's game tests (tests/perf/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_perf(id: String, test_parameters := cases("perf")) -> void:
	await run_case(id)
