extends GameTest
## A character's footsteps and the near-solid sweep its hands and legs share run on every physics
## frame, a walker's and one standing still (#192 rule 28: the per-NPC cost is cut elsewhere, never
## here). A walker crosses an arena beside a wall: on each frame, the footfalls it posts are exactly
## the landings its stride shows that frame (a foot's stride phase rising through the point its sole
## meets the floor, while it walks), and the shared near-solid query is made once; the idler's query
## too. The spec (`docs/hearing.md` H1, `character/body.md`): a step is heard on the frame it lands.

## The walk amount (0..1) below which a shuffle makes no steps.
const MIN_WALK := 0.2
## The stride's foot offset, per side (rad): the second foot lands half a stride after the first.
const FEET := [0.0, PI]
const FRAMES := 150


func describe() -> Dictionary:
	return {
		"name": "Footsteps and the near-solid sweep run every frame",
		"description": "A walking puppet posts a footfall on exactly the frames its stride lands a "
			+ "foot and makes its near-solid query every frame, as a standing one does.",
		"tags": ["footsteps", "legs", "hands", "walk"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 500))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"walker", &"puppet", Vector2(100, 400))
	s.actor(&"idler", &"puppet", Vector2(300, 100))


func run(t: TestContext) -> void:
	var walker: Node = t.actor(&"walker")
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.frames(3)
	var walker_watch := Watch.new(t, walker)
	var idler_watch := Watch.new(t, t.actor(&"idler"))
	if not t.require(walker_watch.sweep != null, "the bodies own a shared sweep"):
		return
	for frame in FRAMES:
		await t.frames(1)
		walker_watch.step()
		idler_watch.step()
	t.require(walker_watch.steps >= 6, "premise: the walker took steps (%d)" % walker_watch.steps)
	t.check(
		walker_watch.wrong_frames == 0,
		"%d frames posted other footfalls than the stride landed" % walker_watch.wrong_frames,
	)
	t.check(
		walker_watch.missed_queries == 0 and idler_watch.missed_queries == 0,
		"frames without exactly one near-solid query: walker %d, idler %d"
			% [walker_watch.missed_queries, idler_watch.missed_queries],
	)


## One character watched frame by frame: its landings by its own stride, the footfalls it posted
## and the near-solid queries its sweep made, each compared with the frame before.
class Watch:
	var steps := 0
	var wrong_frames := 0
	var missed_queries := 0
	var sweep: RefCounted
	var _t: TestContext
	var _body: Node
	var _cos: Array
	var _posted := 0
	var _queries := 0

	func _init(t: TestContext, body: Node) -> void:
		_t = t
		_body = body
		sweep = body.anatomy.get("sweep")
		_cos = _feet_cos()
		_posted = _footfalls()
		_queries = sweep.get("near_queries")

	## Compare this frame with the last.
	func step() -> void:
		var cos_now := _feet_cos()
		var landings := 0
		for foot in 2:
			if _cos[foot] < 0.0 and cos_now[foot] >= 0.0 and _walk_amount() >= MIN_WALK:
				landings += 1
		_cos = cos_now
		steps += landings
		var posted := _footfalls()
		if posted - _posted != landings:
			wrong_frames += 1
		_posted = posted
		var queries: int = sweep.get("near_queries")
		if queries - _queries != 1:
			missed_queries += 1
		_queries = queries

	## `cos` of each foot's stride phase, as the stride shows it now.
	func _feet_cos() -> Array:
		var phase: float = _body.anatomy.pose.gait.stride_phase()
		return [cos(phase + FEET[0]), cos(phase + FEET[1])]

	func _walk_amount() -> float:
		return _body.anatomy.pose.gait.walk_amount()

	## How many footfalls the body has posted so far.
	func _footfalls() -> int:
		return _t.events_of(&"footfall", func(data): return data["character"] == _body).size()
