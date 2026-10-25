extends GameTest
## Performance guard: the whole sound library renders from a cold cache within a generous budget.
## A budget is wall-clock ms, so it lives with the perf guards (the pre-commit hook leaves them
## out); what each clip sounds like is `audio/bank`'s.

const Perf := preload("res://tests/_perf/perf_probe.gd")
# Baseline: 2.3 s headless at a load of ~4.5 (24 October 2026); the budget is about 4x it.
const LIBRARY_BUDGET_MS := 9000.0


func describe() -> Dictionary:
	return {
		"name": "The sound library renders fast",
		"description": "Every profile the sound bank lists is rendered from a cold cache; the "
			+ "whole library's wall time stays within budget.",
		"tags": ["sound", "bank"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var profiles := SoundBank.profiles()
	if not t.require(profiles.size() > 100, "the bank lists its profiles (%d)" % profiles.size()):
		return
	SoundBank.clear_cache()
	var spent := Perf.time_ms(func(): _render(profiles))
	t.expect_eq(SoundBank.cached_count(), profiles.size(), "every profile was rendered")
	Perf.within(t, "sound library render ms", spent, LIBRARY_BUDGET_MS)


func _render(profiles: Array) -> void:
	for profile in profiles:
		SoundBank.sound(profile, 0)
