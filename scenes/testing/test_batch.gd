extends RefCounted
## Testing domain: what one gdUnit run of the game tests shares across its suites
## (game_test_suite.gd, unit_suite.gd) and its session hook (test_report_hook.gd), all static, for
## the process. The options are the batch flags tools/run_tests.sh passes after `--`, which gdUnit
## leaves alone:
##   [filter words] [--domain=a,b] [--id=a,b] [--skip-domain=a,b] [--failed=<report>] [--self-test]
##   [--include-von] [--require-von] [--repeat=N] [--seed=N] [--fail-fast] [--summary] [--verbose]
##   [--json] [--shots] [--shard=I/N] [--costs=<json>] [--out=<dir>]
## The selection is made once per process from the catalog (test_catalog.gd), as the batch runner
## made it: `--domain` / `--id` keep exactly those, `--skip-domain` wins over all (each of the three
## a comma list, and a flag given again adds to it: `list_option`), the words are
## word prefixes (TestCatalog.matches), `--self-test` keeps only the harness's own tests and
## `--shard` one cost-balanced slice. Each wrapper suite lists the selected tests of its folder as
## its cases (`cases`), each `--repeat` times; a native suite runs whole or not at all
## (`native_selected`). With no options at all (gdUnit's editor panel, its own command line) every
## test of a folder is listed, the harness's own included, read from the file names. With
## `--out=<dir>` (a run that owns its engine log, `--log-file <dir>/godot.log`) the run keeps a
## verdict record per test (`add`), prints each as the batch runner printed it, and the session hook
## writes <dir>/report.json and prints the summary at the end (`finish`). Without it nothing is
## written.

const TestCatalog = preload("res://scenes/testing/test_catalog.gd")
const TestSessionScript = preload("res://scenes/testing/test_session.gd")
const LogWatch = preload("res://scenes/testing/log_watch.gd")
## Where bundles go without `--out` (a run from the editor panel).
const BUNDLE_DIR := "user://test_failures"
## A native suite's case id: `<its path under tests/, no .gd>::<test function>`
## (`general/weighted_pick_suite::test_x`).
const NATIVE_SEP := "::"

## The run's verdict records, in the order they ended.
static var records: Array = []
## The errors and warnings logged while no test was open.
static var stray_logs: Array = []
## A `--fail-fast` failure has ended the run: every case after it is skipped and leaves no record.
static var stopped := false
## Native suites this process has met (res:// path -> whether it was selected): the session hook
## makes records of the selected ones' cases.
static var native_suites: Dictionary = {}
## The selected catalog entries (null until first asked for).
static var _picked: Variant = null
## The engine log tail `watch` makes on first use (null until then).
static var _watch: LogWatch = null
## Whether `begin` has run: the run starts once, however many suites ask.
static var _begun := false


## The options after `--` (empty: no selection, every test listed).
static func args() -> PackedStringArray:
	return OS.get_cmdline_user_args()


## Whether this process runs a selection given by tools/run_tests.sh (false in the editor panel).
static func selecting() -> bool:
	return not args().is_empty()


## The value of a `--name=value` option, or `fallback`.
static func option(option_name: String, fallback := "") -> String:
	for a in args():
		if a.begins_with(option_name + "="):
			return a.substr(option_name.length() + 1)
	return fallback


## The items of a comma-list option (`--id`, `--domain`, `--skip-domain`), every time it is given:
## `--id=a --id=b` is `--id=a,b`.
static func list_option(option_name: String) -> Array:
	var out: Array = []
	for a in args():
		if a.begins_with(option_name + "="):
			out.append_array(TestCatalog.csv(a.substr(option_name.length() + 1)))
	return out


## Whether the bare option `flag_name` (`--summary`, `--self-test` ...) was given.
static func flag(flag_name: String) -> bool:
	return args().has(flag_name)


## Whether the run writes its report and prints its summary (`--out` given).
static func reporting() -> bool:
	return option("--out") != ""


## Whether only the non-passing tests and the totals are printed (`--summary`).
static func compact() -> bool:
	return flag("--summary")


## How many times each selected test is listed as a case (`--repeat`, at least 1).
static func repeat() -> int:
	return maxi(1, int(option("--repeat", "1")))


## Where the run's bundles (and `--shots` screenshots) go.
static func bundle_dir() -> String:
	return option("--out").path_join("failures") if reporting() else BUNDLE_DIR


## The filter words joined (the arguments that are not options).
static func filter() -> String:
	var words := PackedStringArray()
	for a in args():
		if not a.begins_with("--"):
			words.append(a)
	return " ".join(words)


## The log a run given `--out` writes: `--log-file <dir>/godot.log`, which the engine consumes, so
## `debug/file_logging/log_path` still names the project's own log.
static func run_log() -> String:
	return option("--out").path_join("godot.log")


## The engine log tail every suite routes to its tests, made on first use: a run given `--out`
## follows the log it was started with (`run_log`) from its start, so start-up errors count.
static func watch() -> LogWatch:
	if _watch == null:
		_watch = LogWatch.new()
		if reporting():
			_watch.path_override = run_log()
		_watch.begin(reporting())
	return _watch


## The ids a wrapper suite of `folder` (under tests/, e.g. "projectile" or "ai/entry") lists, as
## gdUnit test parameters (`[[id], ...]`): its selected tests, each `--repeat` times in a row.
static func cases(folder: String) -> Array:
	var dir := TestCatalog.ROOT.path_join(folder)
	var out: Array = []
	if not selecting():
		for id in _folder_ids(dir):
			out.append([id])
		return out
	for e in selection():
		if String(e["path"]).get_base_dir() == dir:
			for i in repeat():
				out.append([e["id"]])
	return out


## The catalog entries this run selected, in id order (made once, then kept: gdUnit evaluates each
## case list again for every case it runs).
static func selection() -> Array:
	if _picked != null:
		return _picked
	var self_test := flag("--self-test")
	var text := filter()
	TestCatalog.show_internal = self_test
	var domains := list_option("--domain")
	var skipped := list_option("--skip-domain")
	var keep := func(e): return (e["internal"] or not self_test) and TestCatalog.matches(e, text)
	var picked := TestCatalog.discover(TestCatalog.ROOT, domains, ids(), skipped).filter(keep)
	TestCatalog.show_internal = false
	var spec := option("--shard")
	if spec != "":
		picked = TestCatalog.shard(picked, spec, TestCatalog.load_costs(option("--costs")),
			flag("--include-von") or flag("--require-von"))
	_picked = picked
	return picked


## The exact ids asked for: `--id`, plus those that FAILED or TIMED OUT in the `--failed` report (a
## placeholder when it names none, so that `--failed` selects nothing rather than everything).
static func ids() -> Array:
	var out := list_option("--id")
	var failed_from := option("--failed")
	if failed_from != "":
		out.append_array(_failed_ids(failed_from))
		if out.is_empty():
			out.append("<no failed test in the last report>")
	return out


## Whether the native suite at `path` (res://tests/<domain>/…_suite.gd) runs: never in a self-test
## run, after a `--fail-fast` stop or in a shard but the first; else when its domain is selected
## (`--domain`, `--skip-domain`), an `--id` names it or one of its cases (`--failed` reruns the
## whole suite), and the filter words match its path and name.
static func native_selected(path: String) -> bool:
	if not selecting():
		return true
	if _natives_held():
		return false
	return _native_wanted(native_entry(path))


## Whether no native suite runs in this process at all: a self-test run, after a `--fail-fast`
## stop, or a shard but the first.
static func _natives_held() -> bool:
	if stopped or flag("--self-test"):
		return true
	var spec := option("--shard")
	return spec != "" and int(spec.get_slice("/", 0)) != 0


## Whether the selection names the native suite `entry` (`native_entry`): its domain selected
## (`--domain`, `--skip-domain`), an `--id` naming it or one of its cases, and the filter words
## matching its path and name.
static func _native_wanted(entry: Dictionary) -> bool:
	var domains := list_option("--domain")
	if not domains.is_empty() and not domains.has(entry["domain"]):
		return false
	if list_option("--skip-domain").has(entry["domain"]):
		return false
	var wanted := ids()
	var names_it := func(i: String):
		return i == entry["id"] or i.begins_with(entry["id"] + NATIVE_SEP)
	if not wanted.is_empty() and not wanted.any(names_it):
		return false
	return TestCatalog.matches(entry, filter())


## A native suite as a catalog-like entry: its id (path under tests/, no .gd), name and domain (the
## first folder).
static func native_entry(path: String) -> Dictionary:
	var rel := path.trim_prefix(TestCatalog.ROOT + "/").trim_suffix(".gd")
	return {
		"id": rel, "name": rel.get_file().capitalize(),
		"domain": rel.get_slice("/", 0) if "/" in rel else "general", "description": "", "tags": [],
	}


## The run starts (the session hook's startup): gdUnit pointed at the run's log, the game's own log
## off unless `--verbose`, the `--seed` pin, and the banner the batch runner printed.
static func begin() -> void:
	if _begun:
		return
	_begun = true
	# gdUnit's log monitor (made per suite, after this) reads `debug/file_logging/log_path`: without
	# this it reads the project's own log, missing in a fresh user:// and another process's
	# otherwise. Set in memory only, never saved, so project.godot keeps its value.
	ProjectSettings.set_setting("debug/file_logging/log_path", run_log())
	GameLog.enabled = flag("--verbose")  # a batch run shows verdicts only unless asked
	TestSetup.seed_override = int(option("--seed", "0"))
	if flag("--shots") and DisplayServer.get_name() == "headless":
		print("NOTE  --shots needs a rendering run; tools/run_tests.sh --shots drops --headless")
	if not watch().available():
		print("NOTE  log file not found — errors/warnings cannot fail tests this run")
	if compact():
		return
	var include_von := flag("--include-von")
	var require_von := flag("--require-von")
	print("Godot %s  fixed-fps %d  Von tests: %s%s%s" % [
		Engine.get_version_info()["string"], Engine.physics_ticks_per_second,
		"required" if require_von else ("included" if include_von else "skipped"),
		"" if repeat() == 1 else "  repeat x%d" % repeat(),
		"" if TestSetup.seed_override == 0 else "  seed %d" % TestSetup.seed_override,
	])
	var domain := ",".join(list_option("--domain"))
	var text := filter()
	var spec := option("--shard")
	var natives := native_suites_under(TestCatalog.ROOT).filter(native_selected).size()
	print("Running %d test(s)%s%s%s%s" % [
		selection().size(), "" if natives == 0 else " and %d native suite(s)" % natives,
		"" if domain == "" else " in domain '%s'" % domain,
		"" if text == "" else " matching '%s'" % text, "" if spec == "" else "  shard " + spec,
	])


## Keep a test's verdict record and print it; a FAIL or TIMEOUT under `--fail-fast` stops the run.
static func add(r: Dictionary) -> void:
	records.append(r)
	TestSessionScript.print_result(r, bundle_dir(), compact())
	if flag("--fail-fast") and (r["status"] == "FAIL" or r["status"] == "TIMEOUT"):
		stopped = true


## Whether `id` already ran this process and was SKIPPED: a repeat of it would skip again, so it is
## not run.
static func skipped_before(id: String) -> bool:
	return records.any(func(r): return r["id"] == id and r["status"] == "SKIPPED")


## Route what is left in the log to the stray lines (no test is open now).
static func poll_strays(flush := false) -> void:
	for e in watch().poll(flush):
		if not LogWatch.matches_any(e, []):
			stray_logs.append(e)


## The run is over (the session hook's shutdown): the strays, the FLAKY / FAILING lines of a
## repeated run, the slowest tests and the totals, as the batch runner printed them; then
## <out>/report.json and, with `--json`, the `JSON:` line.
static func finish() -> void:
	poll_strays(true)
	var counts := { "PASS": 0, "FAIL": 0, "TIMEOUT": 0, "SKIPPED": 0, "GAP": 0 }
	for r in records:
		counts[r["status"]] = counts.get(r["status"], 0) + 1
	if not stray_logs.is_empty():
		print("Logged outside any test (%d):" % stray_logs.size())
		for e in stray_logs:
			print("        ✗ %s: %s %s" % [e["severity"], e["message"], e["location"]])
	if repeat() > 1:
		var tally := {}
		for r in records:
			if r["status"] == "SKIPPED":
				continue
			var t: Array = tally.get(r["id"], [0, 0])
			t[0] += 1 if r["status"] == "PASS" or r["status"] == "GAP" else 0
			t[1] += 1
			tally[r["id"]] = t
		for id in tally:
			if tally[id][0] != tally[id][1]:
				print("%s  %d/%d passed%s" % [
					"FLAKY  " if tally[id][0] > 0 else "FAILING",
					tally[id][0],
					tally[id][1],
					"  " + id,
				])
	if not compact():
		var timed := records.filter(func(r): return r["status"] != "SKIPPED" and r.has("wall_ms"))
		timed.sort_custom(func(a, b): return a["wall_ms"] > b["wall_ms"])
		if timed.size() > 1:
			print("Slowest: " + ", ".join(timed.slice(0, 5).map(
				func(r): return "%s %d ms" % [r["id"], r["wall_ms"]],
			)))
	print("%d passed, %d failed, %d timed out, %d skipped, %d gap"
			% [counts["PASS"], counts["FAIL"], counts["TIMEOUT"], counts["SKIPPED"], counts["GAP"]])
	var report_path := option("--out").path_join("report.json")
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f != null:
		# `log_end`: how much of the engine log this run has judged; what the engine writes after it
		# (gdUnit's own reports, shutdown) is checked by tools/run_tests.sh through
		# tools/scan_godot_log.py.
		f.store_string(JSON.stringify(
			{ "results": records, "stray_logs": stray_logs, "log_end": watch().consumed() },
			"  ",
		))
		f.close()
		print("Report: %s" % ProjectSettings.globalize_path(report_path))
	if flag("--json"):
		print("JSON: " + JSON.stringify({ "results": records, "stray_logs": stray_logs }))


## The ids that FAILED or TIMED OUT in the report at `path` (empty when it is missing or
## unreadable).
static func _failed_ids(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for r in data.get("results", []):
			if r["status"] == "FAIL" or r["status"] == "TIMEOUT":
				out.append(r["id"])
	return out


## The native suites (scripts extending unit_suite.gd) under `dir`, sorted.
static func native_suites_under(dir: String) -> Array:
	# not preloaded: it preloads this script
	var unit_suite: Script = load("res://scenes/testing/unit_suite.gd")
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for sub in d.get_directories():
		out.append_array(native_suites_under(dir.path_join(sub)))
	for file in d.get_files():
		if file.ends_with("_suite.gd"):
			var script := load(dir.path_join(file)) as Script
			while script != null and script != unit_suite:
				script = script.get_base_script()
			if script != null:
				out.append(dir.path_join(file))
	out.sort()
	return out


## The ids of the tests directly in `dir`, from their file names, sorted.
static func _folder_ids(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for file in d.get_files():
		var f := file.trim_suffix(".remap")
		if f.ends_with(TestCatalog.SUFFIX):
			out.append(dir.path_join(f).trim_prefix(TestCatalog.ROOT + "/").trim_suffix(
				TestCatalog.SUFFIX,
			))
	out.sort()
	return out
