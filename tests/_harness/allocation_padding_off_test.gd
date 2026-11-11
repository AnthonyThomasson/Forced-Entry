extends GameTest
## Harness self-test, second of an ordered pair (runs after allocation_padding_test): a test that
## names no padding switch allocates none, and the earlier test's padding is gone.


func describe() -> Dictionary:
	return {
		"name": "Allocation padding is off unless asked (2/2)",
		"tags": ["harness", "switch", "padding"],
		"internal": true,
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await t.frames(2)
	t.check(AllocationPadding.held() == { "nodes": 0, "rids": 0 }, "nothing is held")
	t.check(not AllocationPadding.enabled, "the knob is back off")
