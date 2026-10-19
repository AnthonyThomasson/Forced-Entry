extends GameTestSuite
## The projectile domain's game tests (tests/projectile/*_test.gd),
## one gdUnit case each, named by its id (game_test_suite.gd).


@warning_ignore("unused_parameter")  # gdUnit reads test_parameters by name; the body never does
func test_projectile(id: String, test_parameters := cases("projectile")) -> void:
	await run_case(id)
