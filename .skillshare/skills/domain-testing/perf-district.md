# Performance guards on the district (#182)

Side file of `domain-testing` (`perf.md`). The match guards moved from a lone house to a downtown district (`Perf.configure_match`),
and the standard of `perf.md` stands (`SMOOTH_*` is untouched; no guard is skipped or tagged). The exceptions are the five gates below, which moved on the district premise with the user's sign-off (recorded in the brief of the review-fix task), and each test header says why it is heavier than the house.

## Gates moved on the district premise

A district match is a different load from a house (nine towers and their streets, a nav map of about 800 polygons against 130, the
invaders starting in the street), so five gates moved. Each was signed off by the user.

- `Perf.MATCH_CONTACT_WITHIN` 20 → 30 s: the sides are in contact 6 to 30 s into a district match (the invaders walk in from the street).
- `perf/match_5v5_stress` timeout 40 → 50 s, for the same wait.
- `perf/bake_and_path_stress` `REBAKE_BUDGET_MS` 12 → 150 and `QUERY_BUDGET_MS` 10 → 60: it measures the planning re-bake of a district whole
  (~57 ms, a house ~2.5) and 300 queries on a map of ten times the polygons. The synchronous re-bake is now a test seam; what a frame
  pays is held by the new `ASYNC_BUDGET_MS` (60, starting an async re-bake) and `STEERING_BUDGET_MS` (15, a steering re-bake of the one to
  four tiles a character stops in).
- `perf/bake_and_path_stress` `STEERING_BUDGET_MS` 15 → 10 (#192, 2026-11-07): the steering re-bake of a tick read about 5.5 ms and now reads
  2.52 and 2.58 ms (a tick cuts only the pieces that moved), so the budget is set again at about 4x.
- `SMOOTH_AVG_MS`, `SMOOTH_P95_MS`, `SMOOTH_MAX_MS`, every vision budget and the house budgets of `perf/generate_houses_stress` did not move.

The dated runs, profiles and spikes that followed (#190, #192 and its extensions) are history: [ADR 0017](../../../docs/adr/0017-district-perf-measurement-history.md).
