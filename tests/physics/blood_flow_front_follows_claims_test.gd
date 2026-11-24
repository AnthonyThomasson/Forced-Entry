extends GameTest
## A bleed-out pool's front sweeps while its cells are still being claimed (#194 perf-spike), but
## never past the cheapest cell not yet claimed: no cell is claimed already filled, the claimed
## cells and the fills after the sweep are exactly what claiming everything first gives, and the
## first blood shows within a couple of frames whatever the claim rate.

const FLOWS := 6
const BUDGET := 225.0
const FRAME := 1.0 / 60.0

## The twin space, where the flow is tried, and the flow under test's sweep seconds and name.
var _space: PhysicsDirectSpaceState3D
var _duration := 1.0
var _label := ""


func describe() -> Dictionary:
	return {
		"name": "A pool's front sweeps over the cells claimed and waits for the rest",
		"description": "Claiming a few cells a frame while the front advances: the front never "
			+ "passes the cheapest unclaimed cell, a newly claimed cell is dry, the cells and the "
			+ "settled fills equal claiming all up front, and the first cell shows at once.",
		"tags": ["blood", "flow", "pool"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(225, 165))


func run(t: TestContext) -> void:
	await t.frames(2)
	_space = TwinSpace.space_of(t.world)
	var held := 0
	for i in FLOWS:
		var at := Vector2(180 + (i % 3) * 15, 130 + (i % 4) * 12)
		var aim := Vector2.from_angle(i * 1.1)
		# Slow claims on a quick sweep make the front wait; fast claims on a slow one never do.
		_duration = 0.5 if i % 2 == 0 else 10.0
		_label = "flow %d" % i
		seed(194_020 + i)
		var live := BloodFlow.new(aim, [])
		seed(194_020 + i)
		var whole := BloodFlow.new(aim, [])
		whole.step(100_000, _space, at, BUDGET)
		held += _claim_sweeping(t, live, at, 1 + i % 3)
		t.check(
			_claims(live) == _claims(whole),
			"flow %d: the same cells at the same costs as claiming them all first" % i,
		)
		_settle(live, _duration)
		_settle(whole, _duration)
		t.check(live.settled() and whole.settled(), "flow %d: both settle" % i)
		t.expect_near(live.front, whole.front, 0.00001, "flow %d: the same final front" % i)
		t.expect_eq(_differing(live, whole), 0, "flow %d: cells whose settled fill differs" % i)
	t.check(held > 0, "premise: the front waited for a claim at least once (%d frames)" % held)


## Claim `per_frame` cells a frame, advancing the front each frame, until claiming is over. Returns
## the frames the front waited at the cheapest unclaimed cell.
func _claim_sweeping(t: TestContext, flow: BloodFlow, at: Vector2, per_frame: int) -> int:
	var waited := 0
	var shown := -1
	var frame := 0
	var claiming := true
	while claiming:
		frame += 1
		var old := flow.cells.size()
		flow.step(per_frame, _space, at, BUDGET)
		var seen := 0
		for c in flow.cells:
			seen += 1
			if seen > old and flow.fill(c) > 0.0:
				t.check(false, "%s: cell %s was claimed already filled" % [_label, c])
		claiming = flow.budget_used() < BUDGET and not flow.done()
		flow.advance(FRAME, _duration, claiming)
		if claiming and flow.front >= flow.next_cost():
			waited += 1
		if claiming and flow.front > flow.next_cost() + 0.000001:
			t.check(false, "%s: the front passed the cheapest unclaimed cell" % _label)
			break
		if shown < 0 and flow.fill(Vector2i.ZERO) > 0.0:
			shown = frame
	t.check(shown >= 1 and shown <= 2, "%s: the first blood shows (frame %d)" % [_label, shown])
	return waited


func _differing(a: BloodFlow, b: BloodFlow) -> int:
	var differing := 0
	for c in b.cells:
		if not is_equal_approx(a.fill(c), b.fill(c)):
			differing += 1
	return differing


func _settle(flow: BloodFlow, duration: float) -> void:
	for i in int(duration / FRAME) + 60:
		if flow.settled():
			return
		flow.advance(FRAME, duration)


func _claims(flow: BloodFlow) -> Array:
	var out: Array = []
	for cell in flow.cells:
		out.append([cell, flow.cells[cell]])
	return out
