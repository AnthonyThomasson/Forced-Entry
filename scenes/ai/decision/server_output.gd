extends RefCounted
## AI domain: what the Von boot script prints. The launcher runs the script with its output piped
## back (`OS.execute_with_pipe`: stdout and stderr are two pipes), and this drains both, one thread
## each, into the server log file (and Output, with `echo`). It keeps what explains a server that
## stopped at once: the script's own `von: <cause>. Fix: <command>` line and the last few lines.

## How many of the last lines are kept.
const TAIL_LINES := 4

## Also print each line to the Output panel as `[von] …`.
var echo := true
var _threads: Array[Thread] = []
var _log_file: FileAccess
var _mutex := Mutex.new()
var _von_line := ""
var _tail := PackedStringArray()


## Start draining the `stdio` and `stderr` pipes of `process` (the dictionary `OS.execute_with_pipe`
## returns) into the file at `log_path`.
func start(process: Dictionary, log_path: String) -> void:
	_log_file = FileAccess.open(log_path, FileAccess.READ_WRITE)
	if _log_file == null:
		_log_file = FileAccess.open(log_path, FileAccess.WRITE)
	if _log_file != null:
		_log_file.seek_end()
	for key in ["stdio", "stderr"]:
		var thread := Thread.new()
		thread.start(_read.bind(process[key]))
		_threads.append(thread)


## Whether a reader still waits for its pipe to close.
func alive() -> bool:
	for thread in _threads:
		if thread.is_alive():
			return true
	return false


## The script's `von:` line, `""` when it printed none.
func von_line() -> String:
	_mutex.lock()
	var line := _von_line
	_mutex.unlock()
	return line


## The last lines it printed, oldest first.
func tail() -> PackedStringArray:
	_mutex.lock()
	var lines := _tail.duplicate()
	_mutex.unlock()
	return lines


## Wait for the readers to see their pipes close (the process is ended), then close the log.
func finish() -> void:
	for thread in _threads:
		if thread.is_started():
			thread.wait_to_finish()
	_threads.clear()
	_log_file = null


## Reader thread: copy each line of `pipe` into the log file (and Output) until it closes.
func _read(pipe: FileAccess) -> void:
	while pipe.is_open() and pipe.get_error() == OK:
		var line := pipe.get_line()
		if line.is_empty() and pipe.get_error() != OK:
			break
		line = line.strip_edges(false, true)
		_mutex.lock()
		if _log_file != null:
			_log_file.store_line(line)
			_log_file.flush()
		if line.begins_with("von: ") and _von_line == "":
			_von_line = line
		if not line.is_empty():
			_tail.append(line)
			if _tail.size() > TAIL_LINES:
				_tail.remove_at(0)
		_mutex.unlock()
		if echo:
			GameLog.say("[von] " + line)
