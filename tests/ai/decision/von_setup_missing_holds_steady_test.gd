extends GameTest
## The Von setup is missing (nothing installed under the Forced-Entry home): the launcher runs the
## project's boot script for this OS, which exits with its `von: <cause>. Fix: <command>` line,
## and the launcher settles with no server within `ready_timeout`, saying what is missing and the
## bootstrap command that fixes it, so the setup window opens and the NPCs hold steady. The home is
## an empty folder the test makes, through FORCED_ENTRY_HOME; the real one is never read.

const LAUNCHER := preload("res://scenes/ai/decision/decision_server_launcher.gd")
## An unused port, so a Von running on the developer's own port is never probed.
const PORT := 18_731
## Wall-clock seconds the launcher may take (it runs a real boot script: PowerShell starts slowly).
const WALL_LIMIT_S := 85.0


func describe() -> Dictionary:
	return {
		"name": "Von setup missing: no server, a warning with the fix",
		"description": "An empty Forced-Entry home: the launcher resolves false at once, naming "
			+ "the missing venv and the bootstrap command.",
		"tags": ["ai", "decision", "von", "launcher", "setup"],
		"timeout": 120.0,
		"allowed_logs": ["\\[von\\] "],
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var home := ProjectSettings.globalize_path("user://von_setup_missing_home")
	DirAccess.make_dir_recursive_absolute(home)
	var home_was := OS.get_environment("FORCED_ENTRY_HOME")
	OS.set_environment("FORCED_ENTRY_HOME", home)
	var launcher: Node = LAUNCHER.new()
	launcher.port = PORT
	launcher.echo_to_output = false
	var verdict := { "live": true }
	launcher.resolved.connect(func(is_live: bool): verdict["live"] = is_live)
	(Engine.get_main_loop() as SceneTree).root.add_child(launcher)
	var started := Time.get_ticks_msec()
	while not launcher.is_resolved() and Time.get_ticks_msec() - started < WALL_LIMIT_S * 1000.0:
		OS.delay_msec(20)  # Real time: the sim outpaces a process that has to start.
		await t.frames(1)
	var secs := (Time.get_ticks_msec() - started) / 1000.0
	var problem: String = launcher.problem
	var limit: float = launcher.ready_timeout
	launcher.free()
	OS.set_environment("FORCED_ENTRY_HOME", home_was)
	t.require(
		secs < limit,
		"the launcher settled within ready_timeout (%.1fs)" % secs,
	)
	t.check(not verdict["live"], "no server is coming")
	t.check(
		problem.contains("no Von venv"),
		"it names what is missing: " + problem,
	)
	t.check(problem.contains("Fix: "), "it names the fix: " + problem)
	t.check(problem.contains("bootstrap"), "the fix is the bootstrap command")
