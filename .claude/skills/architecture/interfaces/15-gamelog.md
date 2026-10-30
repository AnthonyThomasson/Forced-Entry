15. **Any domain → General (`GameLog`)** — `GameLog.say(message)` (`general/game_log.gd`, a `class_name` static
    holder) is how every domain prints its "what is happening" log (shots, punches, house seed, Von decisions,
    perf numbers). `GameLog.enabled` is true in the game; a `tools/run_tests.sh` run sets it from `--verbose`, so
    test runs are quiet unless asked. Plain `print` is not used for gameplay logs.
