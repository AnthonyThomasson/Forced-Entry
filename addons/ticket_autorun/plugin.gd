@tool
extends EditorPlugin
## Editor tooling (outside the game domains): shows which worktree this editor is open on (a label
## in the editor toolbar, also printed once), gives the game the editor's Play starts an engine log
## of its own and, when the editor was started by `tools/editor.sh --autorun` (`GAME_AUTORUN` set),
## runs the main scene once the editor has finished its first scan.

const GameLogArgument := preload("res://addons/ticket_autorun/game_log_argument.gd")
## Seconds the autorun waits for the editor's first filesystem scan.
const AUTORUN_DELAY := 2.0

## Toolbar label naming the worktree.
var _label: Label
## Seconds left before the autorun plays the main scene.
var _countdown := 0.0


func _enter_tree() -> void:
	var worktree := _worktree_name()
	print("[worktree] editor open on '%s'" % worktree)
	_label = Label.new()
	_label.text = "Worktree: %s" % worktree
	_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
	add_control_to_container(CONTAINER_TOOLBAR, _label)
	GameLogArgument.give()


func _ready() -> void:
	# READY enables processing for scripts with _process, so the autorun gate belongs here.
	set_process(false)
	if OS.get_environment("GAME_AUTORUN").is_empty():
		return
	# A beat later, so the first filesystem scan finishes before the game is launched.
	_countdown = AUTORUN_DELAY
	set_process(true)


func _exit_tree() -> void:
	GameLogArgument.forget()
	if _label:
		remove_control_from_container(CONTAINER_TOOLBAR, _label)
		_label.queue_free()


## Counts the autorun's delay down, then runs the main scene from here. Play opens a progress
## dialog, which the editor refuses inside a signal's callback, a timer's included (an engine
## error: the timer is erased twice, and the editor crashes now and then), and while the message
## queue is flushed (`call_deferred`).
func _process(delta: float) -> void:
	_countdown -= delta
	if _countdown <= 0.0:
		set_process(false)
		_play()


## The worktree's name: `GAME_TICKET` (set by `tools/editor.sh`), else the project directory's name.
func _worktree_name() -> String:
	var named := OS.get_environment("GAME_TICKET").strip_edges()
	if named.is_empty():
		named = ProjectSettings.globalize_path("res://").trim_suffix("/").get_file()
	return named


## Run the project's main scene in the editor, once.
func _play() -> void:
	print("[worktree] autorun: playing the main scene")
	EditorInterface.play_main_scene()
