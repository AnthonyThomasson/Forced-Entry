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
