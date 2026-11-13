extends UnitSuite
## Native unit suite (pure logic) for `DecisionServerLauncher.qos_args`, the `taskpolicy` arguments
## that move the running Von server to background QoS once it has answered. They apply on macOS,
## with the flag on and a server of ours (a pid); every other case is empty: another platform, the
## flag off, no pid (a reused server or none started).

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
