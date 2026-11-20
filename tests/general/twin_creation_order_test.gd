extends GameTest
## The twins of a world are made in tree order, pieces and characters together, then the groups'
## (#194 del2d-c4): the order Jolt meets the bodies in (its solver order) is the order the twins are
## made in, so a piece, a plan handle, is twinned where it stands among the characters, not after
## them all. A fight is the same fight only while this order is. No builder is
## registered here: each body is said `untwinned` as it is looked at, in the order it was.


func describe() -> Dictionary:
	return {
		"name": "Twins are made in tree order, pieces among the characters",
		"description": "A space watching a root with a piece, a character, a piece, a character "
			+ "in that order, looks at them in that order.",
		"tags": ["twins", "order"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var root := Node2D.new()
	t.world.add_child(root)
	var kinds: Array[Node2D] = [Node2D.new(), Node2D.new(), Node2D.new(), Node2D.new()]
	for i in kinds.size():
		kinds[i].name = "n%d" % i
		kinds[i].add_to_group(TwinSpace.BODIES)
		kinds[i].add_to_group(TwinSpace.PIECES if i % 2 == 0 else &"characters")
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
	t.check(ours == kinds, "pieces and characters are looked at in tree order (%s)" % [ours])
