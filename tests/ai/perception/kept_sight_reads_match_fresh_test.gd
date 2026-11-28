extends GameTest
## The reads sight and the claim ledger keep (#194) answer as a fresh read would, in a built
## match, every frame: each sight ask an NPC makes (`AgentVision.can_see_node_at`, which reads the
## kept posture points, exclude rids and looks-through of `SightRay`) is checked against a recompute
## that keeps nothing (`tests/_ai/fresh_sight_vision.gd`), and each frame every NPC's
## `ledger.claims`
## on each doorway it has heard of, and the `stack` laid on it, against the claims worked out from
## what it heard. A kept read gone stale (a claim heard or lapsed that the ledger did not lay again,
## a posture's points, a pane read once) fails it.

## The branches of the cone test a pair of characters falls on, in `_check_cone`'s tally order.
enum Branch {
	OUTSIDE_BY_RANGE,
	OUTSIDE_BY_ANGLE,
	INSIDE_BUBBLE,
	INSIDE_CONE,
}

const Perf := preload("res://tests/_perf/perf_probe.gd")
const FreshVision := preload("res://tests/_ai/fresh_sight_vision.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const Sight := preload("res://scenes/ai/perception/perception_sight.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const FRAMES := 300
const PER_SIDE := 3
## The branches this match reaches, each with the fewest pairs it must hold (premises: a branch the
## test never reaches checks nothing). Measured over the 300 frames at `Perf.MATCH_SEED`, 9000
## pairs: 4374 outside by the angle, 4338 inside the cone, 288 inside the bubble. None is outside by
## range (the district is smaller than the view distance of 2520): `_check_outside_view_by_hand`
## holds that branch.
const REACHED := {
	Branch.OUTSIDE_BY_ANGLE: 2000,
	Branch.INSIDE_CONE: 2000,
	Branch.INSIDE_BUBBLE: 100,
}

## How many pairs fell on each `Branch`, over the run.
var _branches: Array[int] = [0, 0, 0, 0]


func describe() -> Dictionary:
	return {
		"name": "Kept sight reads and the claim ledger match a fresh recompute every frame",
		"description": "In a small match, for 300 frames each NPC's sight asks and each ledger's "
			+ "claims and stacks equal what is worked out afresh, and the pass's cone test "
			+ "answers on hand-made vectors as the vision's rule does.",
		"tags": ["ai", "perception", "match", "scripted"],
		"timeout": 60.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	_check_outside_view_by_hand(t)
	Perf.warm_sounds()
	var characters: Array = t.world.match_handle.get("combatants", [])
	if not t.require(characters.size() == PER_SIDE * 2, "the combatants spawned"):
		return
	var sights: Array = []
	var ledgers: Array = []
	for character: Node in characters:
		var brain := TestContext.controller_of(character, &"debug_state")
		var perception: Node = brain.get("_perception") if brain != null else null
		if perception == null:
			continue
		perception.sight.vision.set_script(FreshVision)
		sights.append(perception.sight)
		ledgers.append(perception.entry.ledger)
	if not t.require(sights.size() == characters.size(), "every NPC has a perception"):
		return
	await t.seconds(Perf.MATCH_WARMUP_S)
	var bad: Array[String] = []
	var tally := [0, 0]
	for _frame in FRAMES:
		await t.frames(1)
		var counted := _check_cone(characters, sights, bad)
		for k in _branches.size():
			_branches[k] += counted[k]
		for ledger: RefCounted in ledgers:
			var row := _check_ledger(ledger, bad)
			tally[0] += row[0]
			tally[1] += row[1]
		if bad.size() > 3:
			break
	var asks := _collect_asks(sights, bad)
	t.check(bad.is_empty(), "kept reads equal fresh ones: %s" % str(bad.slice(0, 4)))
	t.check(
		asks[1] > 0 and asks[0] > asks[1],
		"premise: sight asks were made and both answered (%d of %d)" % [asks[1], asks[0]],
	)
	_check_branches(t)
	t.check(tally[0] > 0, "premise: claims stood on a doorway at some frame (%d)" % tally[0])
	t.check(tally[1] > 0, "premise: a stack was laid with claims in it (%d)" % tally[1])


## What each NPC's sight checked: how many asks and how many answered true, the disagreements
## added to `bad`.
func _collect_asks(sights: Array, bad: Array[String]) -> Array[int]:
	var asks: Array[int] = [0, 0]
	for sight in sights:
		var vision: RefCounted = sight.vision
		bad.append_array(vision.mismatches)
		asks[0] += vision.asked
		asks[1] += vision.seen
	return asks


## The sight pass's own cone test (`PerceptionSight._outside_view`) against the vision's
## (`AgentVision.in_view`), from the numbers its last pass took, for every pair of characters this
## frame: they agree on every one, so the pass drops exactly the characters `in_view` would have.
## Disagreements added to `bad`. Returns how many pairs fell on each `Branch`, the branch read off
## the vision's numbers apart from both tests.
func _check_cone(characters: Array, sights: Array, bad: Array[String]) -> Array[int]:
	var counted: Array[int] = [0, 0, 0, 0]
	for i in characters.size():
		var vision: RefCounted = sights[i].vision
		var from: Node2D = characters[i]
		for other: Node2D in characters:
			if other == from:
				continue
			var sight: RefCounted = sights[i]
			var to := other.global_position - from.global_position
			var outside: bool = sight._outside_view(to, from.facing)
			if outside == vision.in_view(from.global_position, from.facing, other.global_position):
				bad.append("frame %d cone: pass %s, vision in_view %s" % [
					Engine.get_physics_frames(), str(outside), str(not outside),
				])
			counted[_branch_of(vision, to, from.facing)] += 1
	return counted


## Which branch the offset `to` from an NPC facing `facing` falls on, by the vision's numbers.
func _branch_of(vision: RefCounted, to: Vector2, facing: Vector2) -> int:
	var dist := to.length()
	if dist > vision.view_distance:
		return Branch.OUTSIDE_BY_RANGE
	if dist <= vision.awareness_radius:
		return Branch.INSIDE_BUBBLE
	if facing == Vector2.ZERO or absf(facing.angle_to(to)) > vision.half_fov():
		return Branch.OUTSIDE_BY_ANGLE
	return Branch.INSIDE_CONE


## Premises: the branches the match reaches were reached by enough pairs (the test said nothing
## about a branch with none), logged with the counts of every branch.
func _check_branches(t: TestContext) -> void:
	for branch: int in Branch.values():
		t.trace("cone pairs, %s" % Branch.find_key(branch), _branches[branch])
	for branch: int in REACHED:
		t.check(
			_branches[branch] >= REACHED[branch],
			"premise: the cone test's %s branch was reached by %d pairs, at least %d"
				% [Branch.find_key(branch), _branches[branch], REACHED[branch]],
		)


## `PerceptionSight._outside_view` on hand-made vectors, a vision set by hand (view distance 1000,
## bubble 50, a cone 90 degrees wide) and read by `_read_cone`: just over and just under the view
## distance (and on it: not outside), behind and to the side, the bubble behind, facing ZERO outside
## the bubble (outside) and inside it (not), and a vision not enabled (nothing is outside, whatever
## the vector). Then a cone and a view distance the vision's doubles tell from their float32
## rounding: a vector at an angle just over, and just under, the half-fov, and one just over the
## view distance.
func _check_outside_view_by_hand(t: TestContext) -> void:
	var sight: RefCounted = Sight.new(null)
	var vision: RefCounted = AgentVision.new()
	vision.view_distance = 1000.0
	vision.awareness_radius = 50.0
	vision.fov_degrees = 90.0
	sight.vision = vision
	sight._read_cone()
	var ahead := Vector2.RIGHT
	var cases := [
		["on the view distance", Vector2(1000, 0), ahead, false],
		["just under the view distance", Vector2(999.5, 0), ahead, false],
		["just over the view distance", Vector2(1000.5, 0), ahead, true],
		["just over the view distance, behind", Vector2(-1000.5, 0), ahead, true],
		["inside the cone", Vector2(500, 100), ahead, false],
		["inside the cone, at its edge", Vector2(500, 499), ahead, false],
		["just outside the cone", Vector2(500, 501), ahead, true],
		["behind", Vector2(-500, 0), ahead, true],
		["to the side, past the edge", Vector2(0, 500), ahead, true],
		["in the bubble, behind", Vector2(-49, 0), ahead, false],
		["on the bubble, behind", Vector2(-50, 0), ahead, false],
		["just past the bubble, behind", Vector2(-51, 0), ahead, true],
		["facing ZERO, outside the bubble", Vector2(500, 0), Vector2.ZERO, true],
		["facing ZERO, inside the bubble", Vector2(30, 0), Vector2.ZERO, false],
	]
	for row: Array in cases:
		t.expect_eq(
			sight._outside_view(row[1], row[2]), row[3], "_outside_view, %s" % row[0],
		)
	_check_cone_in_doubles(t, sight, vision)


## The part of the hand-made checks that tells doubles from float32 (a `Vector3` read): a half-fov
## a hair under the angle of a vector (the angle is a float32 already) puts it outside, a hair over
## inside; a view distance a hair under a vector's length puts it outside, and a vision not
## enabled puts nothing outside (`INF`), whatever the vector.
func _check_cone_in_doubles(t: TestContext, sight: RefCounted, vision: RefCounted) -> void:
	var ahead := Vector2.RIGHT
	var to := Vector2(500, 300)
	var angle := absf(ahead.angle_to(to))
	vision.fov_degrees = rad_to_deg((angle - 1e-9) * 2.0)
	sight._read_cone()
	t.expect_eq(sight._outside_view(to, ahead), true, "a cone a hair under the angle: outside")
	vision.fov_degrees = rad_to_deg((angle + 1e-9) * 2.0)
	sight._read_cone()
	t.expect_eq(sight._outside_view(to, ahead), false, "a cone a hair over the angle: inside")
	var far := Vector2(900.5, 0)
	vision.view_distance = far.length() - 1e-6
	sight._read_cone()
	t.expect_eq(sight._outside_view(far, ahead), true, "a view distance a hair under: outside")
	vision.enabled = false
	sight._read_cone()
	t.expect_eq(
		sight._outside_view(Vector2(1e9, 0), Vector2.ZERO),
		false,
		"disabled: never outside",
	)
	t.expect_eq(sight._outside_view(Vector2(-5000, 7), ahead), false, "disabled, behind: inside")


## `ledger`'s claims and stacks on every doorway it has heard from against a fresh recompute,
## texts of what differs added to `bad`; how many claims stood and how many stacks held a claim.
func _check_ledger(ledger: RefCounted, bad: Array[String]) -> Array[int]:
	var openings := {}
	for rec: Dictionary in ledger._heard.values():
		openings[rec["claim"]["opening"]] = true
	var claimed := 0
	var stacked := 0
	for opening: String in openings:
		var held: Array = ledger.claims(opening)
		var fresh := _fresh_claims(ledger, opening)
		if held != fresh:
			bad.append("frame %d %s: claims %s, fresh %s" % [
				Engine.get_physics_frames(), opening, str(held), str(fresh),
			])
		claimed += held.size()
		var stack: RefCounted = ledger.stack(opening)
		if stack.team != fresh:
			bad.append("frame %d %s: stack of %s, fresh claims %s" % [
				Engine.get_physics_frames(), opening, str(stack.team), str(fresh),
			])
		if not stack.team.is_empty():
			stacked += 1
	return [claimed, stacked]


## The live claims on `opening`, worked out from what `ledger` has heard, as `claims` words them.
func _fresh_claims(ledger: RefCounted, opening: String) -> Array:
	var now := GameClock.seconds()
	var out: Array = []
	for rec: Dictionary in ledger._heard.values():
		var claim: Dictionary = rec["claim"]
		var speaker = rec["speaker"]
		if (claim["opening"] != opening
				or StackClaim.ENDED.has(claim["step"])
				or now - float(rec["at"]) > ledger.ttl
				or not is_instance_valid(speaker)
				or speaker.get("is_dead") == true):
			continue
		var copy := claim.duplicate()
		copy["age"] = now - float(rec["at"])
		out.append(copy)
	out.sort_custom(StackClaim.by_slot)
	return out
