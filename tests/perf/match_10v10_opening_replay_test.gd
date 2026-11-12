extends GameTest
## The fight of `perf/match_10v10_opening` is the same on every play (#203): the guard is played
## three times in this process (`Replay.check_same_fight`), plain, plain again some frames later and
## with allocation padding on, and the fingerprints (`fight_fingerprint.gd`, perf-fingerprint.md)
## must match line for line through the warm-up and the whole window. A match must not follow what
## the process allocated or ran before it. The guard's own budgets are not asked for here, only its
## fight.

const Perf := preload("res://tests/_perf/perf_probe.gd")
const Replay := preload("res://tests/_perf/guard_replay.gd")
const GUARD := "perf/match_10v10_opening"


func describe() -> Dictionary:
	return {
		"name": "The 10v10 opening plays the same fight on every play",
		"description": "The guard is played plain, again some frames later and with allocation "
			+ "padding on: the three fight fingerprints are identical.",
		"tags": ["match", "determinism", "fingerprint"],
		"timeout": 240.0,
		"allowed_logs": Perf.MATCH_LOGS,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	await Replay.check_same_fight(t, GUARD)
