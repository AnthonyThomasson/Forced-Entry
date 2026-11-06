extends RefCounted
## Testing domain: picks up engine errors and warnings as they are logged, so a test that causes one
## fails. Godot 4.4 has no in-process hook for them (`Logger` / `OS.add_logger` arrive in 4.5), but
## every error and warning — `push_error`/`push_warning`, script runtime errors, engine `ERROR:` /
## `WARNING:` output — is written to the log file (on by default on desktop, headless included).
## This tails that file from a marked offset and parses the new lines.
##
## Only a log this process owns is read: the one it was started with (`--log-file <file>`, which the
## engine strips from `OS.get_cmdline_args()`, so it is read off the process's own command line), or
## `path_override`. A start without one writes the project's default `user://logs/godot.log`, which
## every Godot start of the project writes (lint, editors, shard runs, another worktree's window)
## and which each start rotates by copying it and truncating it, so two live processes write the
## same bytes and no part of it is this process's alone. That log is never read: `available()` is
## false and the host says so.

## Header → severity. Longest first so "SCRIPT ERROR:" isn't read as "ERROR:".
const HEADERS := [
	["USER SCRIPT ERROR:", "error"], ["SCRIPT ERROR:", "error"], ["SHADER ERROR:", "error"],
	["USER ERROR:", "error"], ["ERROR:", "error"], ["USER SCRIPT WARNING:", "warning"],
	["SCRIPT WARNING:", "warning"], ["SHADER WARNING:", "warning"], ["USER WARNING:", "warning"],
	["WARNING:", "warning"],
]
## Lines no test is blamed for: engine noise outside any test's control.
const GLOBAL_ALLOWED := [
	# the Von launcher's diagnostics; a requires_von test is SKIPPED without a live server
	"[von] ",
]

## Set to watch a given log file instead of the one the process was started with.
var path_override := ""
## The log file being tailed, its open handle, and the byte offset read up to.
var _path := ""
var _file: FileAccess
var _offset := 0
## Up to the last 64 bytes before `_offset`; a changed tail means the log was rewritten in place.
var _tail := PackedByteArray()
## Test read: successful file opens (one at begin, none for appends, one after truncation/rewrite).
var opens := 0
## A trailing line not yet terminated by a newline (kept until the rest arrives).
var _partial := ""
## The last parsed entry, held back one line so a following "at: file:line" can be attached.
var _pending: Dictionary = {}


## Whether this process has a log file of its own to read (false = errors cannot be watched; callers
## should say so).
func available() -> bool:
	var path := _log_path()
	return path != "" and FileAccess.file_exists(path)


## Start watching. By default everything already in the log is ignored; `from_start` also takes in
## what the engine logged before this call (startup errors), for a run whose log file is fresh
## (`--log-file`).
func begin(from_start := false) -> void:
	_path = path_override if path_override != "" else _own_log()
	_open()
	_offset = 0 if from_start or _file == null else _file.get_length()
	_remember_tail()
	_partial = ""
	_pending = {}


## How many bytes of the log have been read so far: what a run reports as `log_end`, so the part of
## the log written after it (engine shutdown) can be checked by whoever started the process
## (tools/scan_godot_log.py).
func consumed() -> int:
	return _offset - _partial.length()


## The error/warning entries logged since the last poll: `{ severity, message, location, line }`.
## `flush` also releases an entry still waiting for its location line.
func poll(flush := false) -> Array:
	var out: Array = []
	if _path == "":
		return out
	if _file == null:
		_open()
	if _file == null:
		return out
	var length := _file.get_length()
	if length < _offset or _tail_changed():
		_open()  # Truncated or rewritten: judge the new contents from the start.
		if _file == null:
			return out
		_offset = 0
		_partial = ""
		length = _file.get_length()
	if length > _offset:
		_file.seek(_offset)
		var text := _partial + _file.get_buffer(length - _offset).get_string_from_utf8()
		_offset = length
		_remember_tail()
		var lines := text.split("\n")
		_partial = lines[lines.size() - 1]
		lines.remove_at(lines.size() - 1)
		for line in lines:
			_feed(line.trim_suffix("\r"), out)
	if flush and not _pending.is_empty():
		out.append(_pending)
		_pending = {}
	return out


## Whether `entry` matches one of `patterns` (regex strings) or the global allow-list.
static func matches_any(entry: Dictionary, patterns: Array) -> bool:
	var text: String = "%s %s" % [entry.get("message", ""), entry.get("location", "")]
	for p in GLOBAL_ALLOWED:
		if text.contains(p):
			return true
	for p in patterns:
		var re := RegEx.create_from_string(String(p))
		if re != null and re.search(text) != null:
			return true
	return false


## Parse one log line into `out`: a header opens an entry, its "at:" line completes it.
func _feed(line: String, out: Array) -> void:
	var stripped := line.strip_edges()
	if not _pending.is_empty() and stripped.begins_with("at:"):
		_pending["location"] = stripped.substr(3).strip_edges()
		out.append(_pending)
		_pending = {}
		return
	for h in HEADERS:
		if line.begins_with(h[0]):
			if not _pending.is_empty():
				out.append(_pending)
			_pending = {
				"severity": h[1],
				"message": line.substr(h[0].length()).strip_edges(),
				"location": "",
				"line": line,
			}
			return
	if not _pending.is_empty() and not line.begins_with(" ") and not line.begins_with("\t"):
		out.append(_pending)
		_pending = {}


## The log file being read, "" when the process has none of its own.
func _log_path() -> String:
	return _path if _path != "" else path_override


## The log file the process was started with (`--log-file <file>`, read off its own command line:
## `/proc/self/cmdline` where there is one, else `ps`), "" when it was started without one or the
## command line cannot be read (Windows).
func _own_log() -> String:
	var args := _process_args()
	var user_args := args.find("--")  # an argument after `--` is the game's, not the engine's
	if user_args >= 0:
		args = args.slice(0, user_args)
	var at := args.find("--log-file")
	if at < 0 or at + 1 >= args.size():
		return ""
	var path := args[at + 1]
	# `ps` joins the arguments with spaces: a path that has some is the next words put back.
	var next := at + 2
	while not FileAccess.file_exists(path) and next < args.size():
		path += " " + args[next]
		next += 1
	return path if FileAccess.file_exists(path) else ""


## This process's command-line words.
func _process_args() -> PackedStringArray:
	var proc := FileAccess.open("/proc/self/cmdline", FileAccess.READ)
	if proc != null:
		var bytes := PackedByteArray()
		while not proc.eof_reached():
			bytes.append_array(proc.get_buffer(4096))
		for i in bytes.size():
			if bytes[i] == 0:
				bytes[i] = 10  # the words are NUL-separated; the string decoder stops at a NUL
		return bytes.get_string_from_utf8().split("\n", false)
	var output := []
	if OS.execute("ps", ["-ww", "-o", "command=", "-p", str(OS.get_process_id())], output) != 0:
		return PackedStringArray()
	return String(output[0]).strip_edges().split(" ", false)


## Open the watched log for all subsequent polls, replacing any handle from an older incarnation.
func _open() -> void:
	_file = FileAccess.open(_path, FileAccess.READ) if _path != "" else null
	if _file != null:
		opens += 1


## Remember the bytes immediately before the read offset, so an in-place rewrite that leaves the
## file as long as before is still noticed without reopening it to query its length every frame.
func _remember_tail() -> void:
	var count := mini(64, _offset)
	_tail = PackedByteArray()
	if _file != null and count > 0:
		_file.seek(_offset - count)
		_tail = _file.get_buffer(count)


## Whether the bytes already consumed have changed under the open handle.
func _tail_changed() -> bool:
	if _offset == 0 or _tail.is_empty():
		return false
	_file.seek(_offset - _tail.size())
	return _file.get_buffer(_tail.size()) != _tail
