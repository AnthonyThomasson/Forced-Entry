extends GameTest
## Harness self-test: LogWatch's read positions. `begin(true)` takes in what the log already holds
## (start-up errors of a fresh log), a plain `begin()` ignores it, and `consumed()` reports how much
## has been judged so the part written after it (engine shutdown) can be checked by the process that
## launched the run.

const LogWatch := preload("res://scenes/testing/log_watch.gd")
const SCRATCH := "user://log_watch_offsets.log"


func describe() -> Dictionary:
	return {
		"name": "LogWatch read offsets",
		"tags": ["harness", "log"],
		"internal": true,
		"timeout": 4.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var before := "ERROR: early problem\n   at: setup (a.gd:1)\n"
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string(before)
	f.close()
	var path := ProjectSettings.globalize_path(SCRATCH)

	var ignoring := LogWatch.new()
	ignoring.path_override = path
	ignoring.begin()
	t.expect_eq(ignoring.poll(true).size(), 0, "a plain begin() ignores what the log already holds")

	var watch := LogWatch.new()
	watch.path_override = path
	watch.begin(true)
	var first := watch.poll(true)
	t.expect_eq(first.size(), 1, "begin(true) reads the entry logged before it")
	t.expect_eq(
		first[0]["message"] if not first.is_empty() else "",
		"early problem",
		"with its message",
	)
	t.expect_eq(watch.consumed(), before.length(), "and has consumed exactly the bytes it parsed")
	var opens = watch.get("opens")
	if not t.require(opens != null, "the watcher counts its file opens"):
		return
	t.expect_eq(opens, 1, "begin opens the log once")

	f = FileAccess.open(SCRATCH, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string("WARNING: late problem\n")
	f.store_string("ERROR: half writ")  # no newline yet: not parsed, not consumed
	f.close()
	var second := watch.poll(true)
	t.expect_eq(second.size(), 1, "a later poll sees only the new complete entry")
	t.check(
		watch.consumed() < FileAccess.get_file_as_string(SCRATCH).length(),
		"an unterminated last line is left unconsumed",
	)
	t.expect_eq(watch.get("opens"), 1, "an appended log keeps the same open handle")

	_rewrites(t, watch)
	watch = null
	ignoring = null
	DirAccess.remove_absolute(path)


func _rewrites(t: TestContext, watch: RefCounted) -> void:
	var f := FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string("WARNING: after truncation\n")
	f.close()
	var truncated: Array = watch.poll(true)
	t.expect_eq(truncated.size(), 1, "a truncated log is read again from its start")
	t.expect_eq(
		truncated[0]["message"] if not truncated.is_empty() else "",
		"after truncation",
		"the new warning is seen",
	)
	t.expect_eq(watch.get("opens"), 2, "truncation reopens the handle")

	f = FileAccess.open(SCRATCH, FileAccess.WRITE)
	f.store_string("ERROR: rewritten problem\n   at: rewrite (b.gd:2)\n")
	f.close()
	var rewritten: Array = watch.poll(true)
	t.expect_eq(rewritten.size(), 1, "an in-place rewrite is detected even when the log grows")
	t.expect_eq(
		rewritten[0]["message"] if not rewritten.is_empty() else "",
		"rewritten problem",
		"the rewritten entry is seen",
	)
	t.expect_eq(watch.get("opens"), 3, "a rewrite reopens the handle")
