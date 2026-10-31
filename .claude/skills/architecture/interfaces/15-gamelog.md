15. **Any domain → General (`GameLog`)** — `GameLog.say(message)` (`general/game_log.gd`, static holder) is how every domain prints its
    gameplay log (shots, punches, house seed, Von decisions, perf numbers); plain `print` is not used for it. `GameLog.enabled` is true in
    the game; a `tools/run_tests.sh` run sets it from `--verbose`, so test runs are quiet unless asked.
