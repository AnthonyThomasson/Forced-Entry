extends RefCounted
## Editor tooling (outside the game domains): the `--log-file` argument the editor's Play gives the
## game it starts, `GAME_LOG_FILE` (set by `tools/editor.sh`), through the project setting the
## editor appends to the game's command line. Play reads the setting before any hook of a plugin
## runs, so it holds the argument for as long as the plugin is on. A saved project leaves out a
## setting equal to its initial value, so the argument is also made the setting's initial value:
## no save of the project settings writes it into the tracked `project.godot`.

## The project setting the editor appends to the game's command line on Play.
const RUN_ARGS := "editor/run/main_run_args"


## Set the argument, in memory only; nothing without `GAME_LOG_FILE`.
static func give() -> void:
	var log_file := OS.get_environment("GAME_LOG_FILE").strip_edges()
	if not log_file.is_empty():
		_hold("--log-file " + log_file)


## Put the setting back to its default, an empty argument list. Never erased: a setting that is
## missing when Play reads it is a `Property not found` warning and a game started without the
## argument.
static func forget() -> void:
	if not OS.get_environment("GAME_LOG_FILE").strip_edges().is_empty():
		_hold("")


## The setting and its initial value both `value`.
static func _hold(value: String) -> void:
	ProjectSettings.set_initial_value(RUN_ARGS, value)
	ProjectSettings.set_setting(RUN_ARGS, value)
