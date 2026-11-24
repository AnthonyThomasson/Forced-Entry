extends GameTest
## The reads sight and the claim ledger keep (#194 perf3d) answer as a fresh read would, in a built
## match, every frame: each sight ask an NPC makes (`AgentVision.can_see_node_at`, which reads the
## kept posture points, exclude rids and looks-through of `SightRay`) is checked against a recompute
## that keeps nothing (`tests/_ai/fresh_sight_vision.gd`), and each frame every NPC's
## `ledger.claims`
## on each doorway it has heard of, and the `stack` laid on it, against the claims worked out from
## what it heard. A kept read gone stale (a claim heard or lapsed that the ledger did not lay again,
## a posture's points, a pane read once) fails it.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const FreshVision := preload("res://tests/_ai/fresh_sight_vision.gd")
const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const FRAMES := 300
const PER_SIDE := 3


func describe() -> Dictionary:
	return {
		"name": "Kept sight reads and the claim ledger match a fresh recompute every frame",
		"description": "In a small match, for 300 frames each NPC's sight asks and each ledger's "
			+ "claims and stacks equal what is worked out afresh.",
		"tags": ["ai", "perception", "match", "scripted"],
		"timeout": 60.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	Perf.warm_sounds()
	var characters: Array = t.world.match_handle.get("combatants", [])
	if not t.require(characters.size() == PER_SIDE * 2, "the combatants spawned"):
		return
	var visions: Array = []
	var ledgers: Array = []
	for character: Node in characters:
		var brain := TestContext.controller_of(character, &"debug_state")
		var perception: Node = brain.get("_perception") if brain != null else null
		if perception == null:
			continue
		perception.sight.vision.set_script(FreshVision)
		visions.append(perception.sight.vision)
		ledgers.append(perception.entry.ledger)
	if not t.require(visions.size() == characters.size(), "every NPC has a perception"):
		return
	await t.seconds(Perf.MATCH_WARMUP_S)
	var bad: Array[String] = []
	var tally := [0, 0]
	for _frame in FRAMES:
		await t.frames(1)
		for ledger: RefCounted in ledgers:
			var row := _check_ledger(ledger, bad)
			tally[0] += row[0]
			tally[1] += row[1]
		if bad.size() > 3:
			break
	var asked := 0
	var seen := 0
	for vision in visions:
		bad.append_array(vision.mismatches)
		asked += vision.asked
		seen += vision.seen
	t.check(bad.is_empty(), "kept reads equal fresh ones: %s" % str(bad.slice(0, 4)))
	t.check(
		seen > 0 and asked > seen,
		"premise: sight asks were made and both answered (%d of %d)" % [seen, asked],
	)
	t.check(tally[0] > 0, "premise: claims stood on a doorway at some frame (%d)" % tally[0])
	t.check(tally[1] > 0, "premise: a stack was laid with claims in it (%d)" % tally[1])


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
