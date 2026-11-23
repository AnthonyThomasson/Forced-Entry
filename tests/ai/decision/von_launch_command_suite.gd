extends UnitSuite
## Native unit suite (pure logic) for `DecisionServerLauncher.qos_args`, the `taskpolicy` arguments
## that move the running Von server to background QoS once it has answered. They apply on macOS,
## with the flag on and a server of ours (a pid); every other case is empty: another platform, the
## flag off, no pid (a reused server or none started). `qos_failure_line` is the log line for the
## `taskpolicy` exit code: none on 0, "QoS not applied" on any other (a dead pid's 70, a failed
## launch's -1).

const Launcher := preload("res://scenes/ai/decision/decision_server_launcher.gd")


func test_macos_with_background_qos_moves_the_running_pid() -> void:
	assert_array(Array(Launcher.qos_args(4242, "macOS", true))).is_equal(["-b", "-p", "4242"])


func test_macos_with_the_flag_off_is_empty() -> void:
	assert_bool(Launcher.qos_args(4242, "macOS", false).is_empty()).is_true()


func test_other_platforms_are_empty_whatever_the_flag() -> void:
	for os_name in ["Linux", "Windows", "FreeBSD"]:
		assert_bool(Launcher.qos_args(4242, os_name, true).is_empty()).is_true()


func test_no_server_of_ours_is_empty() -> void:
	for pid in [-1, 0]:
		assert_bool(Launcher.qos_args(pid, "macOS", true).is_empty()).is_true()


func test_a_zero_exit_logs_nothing() -> void:
	assert_str(Launcher.qos_failure_line(0)).is_empty()


func test_a_non_zero_exit_logs_its_code() -> void:
	assert_str(Launcher.qos_failure_line(70)).is_equal("[von] QoS not applied (exit 70).")


func test_a_failed_launch_of_taskpolicy_logs_too() -> void:
	assert_str(Launcher.qos_failure_line(-1)).is_equal("[von] QoS not applied (exit -1).")


func test_windows_runs_the_boot_script_through_powershell_bypassing_the_policy() -> void:
	var command := Launcher.boot_command(
		"Windows",
		"C:/proj/Forced Entry",
		8000,
		"cpu",
		"C:/Windows",
	)
	assert_str(command["program"]).is_equal(
		"C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
	)
	assert_array(Array(command["args"])).is_equal([
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", "C:/proj/Forced Entry/tools/von/boot.ps1",
		"-Port", "8000", "-BindHost", NpcDecisionTuning.SERVER_HOST, "-Device", "cpu",
	])
	assert_str(command["script"]).is_equal("C:/proj/Forced Entry/tools/von/boot.ps1")


func test_windows_without_a_system_root_finds_powershell_on_the_path() -> void:
	var command := Launcher.boot_command("Windows", "C:/p", 1, "cpu")
	assert_str(command["program"]).is_equal("powershell.exe")


func test_a_mac_runs_the_boot_script_through_bash_so_it_needs_no_exec_bit() -> void:
	var command := Launcher.boot_command("macOS", "/Users/me/Forced-Entry", 8123, "mps")
	assert_str(command["program"]).is_equal("/bin/bash")
	assert_str(command["script"]).is_equal("/Users/me/Forced-Entry/tools/von/boot.sh")
	assert_array(Array(command["args"])).is_equal([
		"/Users/me/Forced-Entry/tools/von/boot.sh",
		"--host", NpcDecisionTuning.SERVER_HOST, "--port", "8123", "--device", "mps",
	])


func test_linux_runs_it_the_same_way_as_a_mac() -> void:
	var command := Launcher.boot_command("Linux", "/home/me/fe", 8000, "cpu")
	assert_str(command["program"]).is_equal("/bin/bash")
	assert_str(Array(command["args"])[0]).is_equal("/home/me/fe/tools/von/boot.sh")


func test_a_von_line_from_the_boot_script_becomes_the_warning_naming_cause_and_fix() -> void:
	var line := "von: no Von venv at C:/h/von/venv. Fix: tools/setup/bootstrap.sh"
	var text := Launcher.exit_warning(3, line, PackedStringArray(["noise"]), 8000)
	assert_str(text).contains("no Von venv at C:/h/von/venv")
	assert_str(text).contains("Fix: tools/setup/bootstrap.sh")
	assert_str(text).contains("NPCs hold steady")
	assert_str(text).not_contains("noise")


func test_a_server_that_stopped_without_a_von_line_names_its_last_output_and_the_port() -> void:
	var text := Launcher.exit_warning(
		1, "", PackedStringArray(["ERROR: [Errno 10048] address already in use"]), 8000,
	)
	assert_str(text).contains("exit 1")
	assert_str(text).contains("address already in use")
	assert_str(text).contains("port 8000")


func test_a_server_that_stopped_in_silence_says_so() -> void:
	assert_str(Launcher.exit_warning(1, "", PackedStringArray(), 8000)).contains("printed nothing")
