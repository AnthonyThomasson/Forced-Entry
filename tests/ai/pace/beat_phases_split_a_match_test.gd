extends GameTest
## The beat's phases (`npc_pace.gd`) split a real 10v10 match evenly: on any frame the NPCs on
## their beat and those coasting differ by at most two of the twenty, so the frame's control work is
## level (the phase is the spawn order, and a match's spawn order runs through the district's
## other characters too). The same two phases, on the frame after, swap.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const PER_SIDE := 10
## The most the two phases' NPC counts may differ by.
const MOST_APART := 2


func describe() -> Dictionary:
	return {
		"name": "The beat's two phases split a 10v10 match's NPCs within two",
		"description": "In a 10v10 match the NPCs on their beat and those off it differ by at "
			+ "most two on a frame, and the two phases swap on the next.",
		"tags": ["ai", "pace", "match", "scripted"],
		"timeout": 40.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	Perf.configure_match(s, PER_SIDE)


func run(t: TestContext) -> void:
	var characters: Array = t.world.match_handle.get("combatants", [])
	if not t.require(
		characters.size() == PER_SIDE * 2,
		"twenty combatants (%d)" % characters.size(),
	):
		return
	await t.frames(3)
	var paces: Array = []
	for c in characters:
		paces.append(TestContext.controller_of(c).get("_reflexes").pace)
	var frame: int = WorldRng.frame_of(characters[0])
	var now := _on(paces, frame)
	var next := _on(paces, frame + 1)
	t.check(
		absi(now - (paces.size() - now)) <= MOST_APART,
		"the phases split the twenty within %d (%d on the beat, %d off)"
			% [MOST_APART, now, paces.size() - now],
	)
	t.expect_eq(now + next, paces.size(), "the next frame the phases swap")


## How many of `paces` are on their beat on `frame`.
func _on(paces: Array, frame: int) -> int:
	return paces.filter(func(p): return p.on_beat(frame)).size()
