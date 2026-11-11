extends GameTest
## The sight checks of a squad (`perception_sight.gd`, `SIGHT_EVERY_FRAMES`) are spread over the
## frames by spawn order (`WorldRng`), not by what the process allocated: of NPCs watching one
## another in a cluster, no frame carries every NPC's check (or more than half of them), every frame
## carries some, and worlds built after other allocations (shifted runs of instance ids) check the
## very same pairs on the very same frames.

const Probe := preload("res://tests/_ai/cadence_probe.gd")
const SightBody := preload("res://tests/_ai/sight_body_probe.gd")
const PerceptionSight := preload("res://scenes/ai/perception/perception_sight.gd")
## NPCs watching one another in each world.
const NPCS := 6
## Frames watched: two whole cadences.
const FRAMES := 6
## Worlds, each built after more nodes than the one before: their instance ids are shifted apart.
const WORLDS := 4


func describe() -> Dictionary:
	return {
		"name": "NPC sight checks are spread over the frames by spawn order",
		"description": "Six NPCs in a cluster each check the others on a cadence: no frame "
			+ "carries every check, none is idle, and two worlds, the second built after other "
			+ "allocations, check on the same frames.",
		"tags": ["ai", "perception", "sight", "determinism"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"lighting.enabled", false)


func run(t: TestContext) -> void:
	var worlds: Array = []
	var padding: Array[Node] = []
	for w in WORLDS:
		for i in w:
			var node := Node2D.new()
			t.world.add_child(node)
			padding.append(node)
		worlds.append(_world(t))
	await t.frames(1)
	var due: Array = []
	due.resize(WORLDS)
	for w in WORLDS:
		due[w] = []
	_checks(worlds)  # The first look of each pair is always due: not counted.
	for frame in FRAMES:
		await t.frames(1)
		var now := _checks(worlds)
		for w in WORLDS:
			due[w].append(now[w])
	var pairs := NPCS * (NPCS - 1)
	for w in WORLDS:
		for frame in FRAMES:
			var n: int = due[w][frame].size()
			t.check(n < pairs, "world %d: frame %d does not carry every check" % [w, frame])
			t.check(n * 2 <= pairs, "world %d: frame %d carries over half (%d)" % [w, frame, n])
			t.check(n > 0, "world %d: frame %d carries some checks" % [w, frame])
		t.expect_eq(
			due[w],
			due[0],
			"world %d, built after other allocations, checks the same pairs on the same frames" % w,
		)
	for node in padding:
		node.free()


## A world root, registered as one, with `NPCS` bodies close together, each with its perception.
func _world(t: TestContext) -> Array:
	var root := Node2D.new()
	t.world.add_child(root)
	WorldRng.register(root, 1)
	var seers: Array = []
	for i in NPCS:
		var body := SightBody.new()
		body.position = Vector2(10.0 * i, 0.0)
		var perception := Probe.perception_of(root, body)
		WorldRng.enrol(body)
		seers.append({ "sight": perception.sight, "body": body, "perception": perception })
	return seers


## Each world's sight checks due this frame: every NPC asked about every other, as the pairs
## ("seer>seen", by spawn order) that are due.
func _checks(worlds: Array) -> Array:
	var out: Array = []
	for seers: Array in worlds:
		var frame := WorldRng.frame_of(seers[0]["body"])
		var due: Array = []
		for i in seers.size():
			for j in seers.size():
				var sight: PerceptionSight = seers[i]["sight"]
				var at: Vector2 = seers[i]["body"].position
				if i != j and sight._due_for_sight(seers[j]["body"], at, Vector2.RIGHT, frame):
					due.append("%d>%d" % [i, j])
		out.append(due)
	return out
