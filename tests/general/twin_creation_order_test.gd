extends GameTest
## The twins of a world are made in tree order, pieces and physics bodies together, then the groups'
## (#194 del2d-c4): the order Jolt meets the bodies in (its solver order) is the order the twins are
## made in, so a piece, now a plan handle and no physics body, is twinned where it stands among the
## bodies, not after them all. A fight is the same fight only while this order is. No builder is
## registered here: each body is said `untwinned` as it is looked at, in the order it was.


func describe() -> Dictionary:
	return {
		"name": "Twins are made in tree order, pieces among the bodies",
		"description": "A space watching a root with a piece, a body, a piece and a body, in that "
			+ "order, looks at them in that order.",
		"tags": ["twins", "order"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var root := Node2D.new()
	t.world.add_child(root)
	var kinds: Array[Node2D] = [Node2D.new(), StaticBody2D.new(), Node2D.new(), StaticBody2D.new()]
	for i in kinds.size():
		kinds[i].name = "n%d" % i
		if kinds[i] is Node2D and not kinds[i] is PhysicsBody2D:
			kinds[i].add_to_group(TwinSpace.PIECES)
			kinds[i].add_to_group(TwinSpace.BODIES)
		root.add_child(kinds[i])
	var space := TwinSpace.new()
	t.world.add_child(space)
	var seen: Array[Node2D] = []
	space.untwinned.connect(func(body: Node2D) -> void: seen.append(body))
	space.watch(root)
	var ours: Array[Node2D] = []
	for body in seen:
		if body in kinds:
			ours.append(body)
	t.check(ours == kinds, "pieces and bodies are looked at in tree order (%s)" % [ours])
