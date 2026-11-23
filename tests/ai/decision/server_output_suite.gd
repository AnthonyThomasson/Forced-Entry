extends UnitSuite
## Native unit suite for `ServerOutput`, what the launcher reads of the Von boot script: `finish`
## must not hang the game's close on a pipe that stays open (a process the server left behind
## holds it), and `reap` joins the readers it left once the pipe closes.

const ServerOutput := preload("res://scenes/ai/decision/server_output.gd")
const LOG := "user://server_output_suite.log"
## A process that holds its pipes open for far longer than any test runs.
const SLEEP_S := 60


func test_finish_leaves_a_reader_whose_pipe_stays_open_and_reap_joins_it_once_it_closes() -> void:
	var process := _sleeper()
	assert_bool(process.is_empty()).is_false()
	var output := ServerOutput.new()
	output.echo = false
	output.start(process, LOG)
	var began := Time.get_ticks_msec()
	output.finish()
	var took_ms := Time.get_ticks_msec() - began
	assert_int(took_ms).is_less(int(ServerOutput.JOIN_WAIT_S * 1000.0) + 2000)
	assert_bool(output.alive()).is_true()  # left running, not joined
	OS.kill(process["pid"])
	var waited := 0
	# Ends as soon as the reader does; the bound is generous because a killed PowerShell on a loaded Windows machine
	# takes several seconds to let go of its pipe.
	while output.alive() and waited < 30_000:
		OS.delay_msec(50)
		waited += 50
	assert_bool(output.alive()).is_false()
	ServerOutput.reap()
	assert_bool(ServerOutput._stragglers.has(output)).is_false()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))


func test_finish_after_the_pipes_closed_joins_at_once() -> void:
	var process := _sleeper()
	var output := ServerOutput.new()
	output.echo = false
	output.start(process, LOG)
	OS.kill(process["pid"])
	var began := Time.get_ticks_msec()
	output.finish()
	assert_int(Time.get_ticks_msec() - began).is_less(int(ServerOutput.JOIN_WAIT_S * 1000.0) + 2000)
	ServerOutput.reap()
	assert_bool(output.alive()).is_false()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG))


## A process that sleeps with its pipes open, on this OS.
func _sleeper() -> Dictionary:
	if OS.get_name() == "Windows":
		return OS.execute_with_pipe(
			"powershell.exe",
			PackedStringArray([
				"-NoProfile", "-NonInteractive", "-Command", "Start-Sleep -Seconds %d" % SLEEP_S,
			]),
		)
	return OS.execute_with_pipe("/bin/sleep", PackedStringArray([str(SLEEP_S)]))
