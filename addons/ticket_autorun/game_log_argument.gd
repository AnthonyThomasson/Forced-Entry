extends RefCounted
## Editor tooling (outside the game domains): the `--log-file` argument the editor's Play gives the
## game it starts, `GAME_LOG_FILE` (set by `tools/editor.sh`), through the project setting the
## editor appends to the game's command line. The setting is a project setting the editor itself
## reads and the project file would save, so it is held only while the editor is open.

## The project setting the editor appends to the game's command line on Play.
const RUN_ARGS := "editor/run/main_run_args"


## Set the argument, in memory only; nothing without `GAME_LOG_FILE`.
static func give() -> void:
	var log_file := OS.get_environment("GAME_LOG_FILE").strip_edges()
	if not log_file.is_empty():
		ProjectSettings.set_setting(RUN_ARGS, "--log-file " + log_file)


## Put the setting back to its default, an empty argument list, which a saved project omits. Never
## erased: a setting that is missing when Play reads it is a `Property not found` warning and a
## game started without the argument.
static func forget() -> void:
	if not OS.get_environment("GAME_LOG_FILE").strip_edges().is_empty():
		ProjectSettings.set_setting(RUN_ARGS, "")


## What the editor's save hook does, which runs just before Play reads the setting: set the argument
## again, in the same call, so it is there for that read.
static func after_save() -> void:
	give()
