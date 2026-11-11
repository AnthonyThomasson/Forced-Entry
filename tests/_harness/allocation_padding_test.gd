extends GameTest
## Harness self-test, first of an ordered pair: the `testing.allocation_padding` switch makes the
## world allocate loose nodes (the engine counts them) and physics RIDs before it is built.
## allocation_padding_off_test then checks the world's teardown freed them: freeing a RID or a node
## twice, or one the engine lost, would log an engine error, which fails the test.

# The engine's own count of nodes that are in no tree, the padding's kind.
const ORPHANS := Performance.OBJECT_ORPHAN_NODE_COUNT


func describe() -> Dictionary:
	return {
		"name": "Allocation padding allocates before the world (1/2)",
		"tags": ["harness", "switch", "padding"],
		"internal": true,
		"timeout": 3.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.switch(&"testing.allocation_padding", true)


func run(t: TestContext) -> void:
	await t.frames(2)
	var held: Dictionary = AllocationPadding.held()
	var orphans := int(Performance.get_monitor(ORPHANS))
	t.check(held["nodes"] >= 500, "the world held back a good number of nodes (%d)" % held["nodes"])
	t.check(held["rids"] >= 500, "and of physics RIDs (%d)" % held["rids"])
	t.check(
		orphans >= held["nodes"],
		"the engine counts them as nodes in no tree (%d orphans, %d held)"
			% [orphans, held["nodes"]],
	)
