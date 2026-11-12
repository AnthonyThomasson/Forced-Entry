extends UnitSuite
## Native unit suite (pure logic) for `DecisionServerLauncher.serve_command`, the shell line that
## starts `von serve`. On macOS the server runs under background QoS (`taskpolicy -b`), because
## PyTorch on CPU otherwise bursts to several cores at fight start and starves the game; every other
## platform, and the flag off, launches the bare `exec '<von>' serve ...`. The pid the launcher
## keeps must still be the server's, so every form begins with `exec`.

const Launcher := preload("res://scenes/ai/decision/decision_server_launcher.gd")
const VON := "/opt/von/bin/von"
const SERVE := "serve --host 127.0.0.1 --port 8000 --device cpu 2>&1"


func test_macos_with_background_qos_runs_von_under_taskpolicy() -> void:
	assert_str(Launcher.serve_command(VON, 8000, "cpu", "macOS", true)).is_equal(
		"exec /usr/sbin/taskpolicy -b '%s' %s" % [VON, SERVE])


func test_macos_with_the_flag_off_is_the_bare_launch() -> void:
	assert_str(Launcher.serve_command(VON, 8000, "cpu", "macOS", false)).is_equal(
		"exec '%s' %s" % [VON, SERVE])


func test_other_platforms_are_the_bare_launch_whatever_the_flag() -> void:
	for os_name in ["Linux", "Windows", "FreeBSD"]:
		assert_str(Launcher.serve_command(VON, 8000, "cpu", os_name, true)).is_equal(
			"exec '%s' %s" % [VON, SERVE])


func test_port_and_device_are_passed_through() -> void:
	assert_str(Launcher.serve_command(VON, 9001, "mps", "Linux", true)).contains(
		"--port 9001 --device mps")
