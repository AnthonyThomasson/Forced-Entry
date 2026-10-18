extends RefCounted
## Fixture code the fixture tests call: alpha by t/alpha and t/both, beta by t/beta and t/both, heavy only by the
## perf test (which a coverage run skips), teardown by the runner after every test ends.


func alpha() -> int:
	return 1


func beta() -> int:
	return 2


func heavy() -> int:
	return 3


func teardown() -> int:
	return 4
