extends Node
## Fixture stand-in for scenes/main.gd: the setup window's start_requested starts a match, the MatchHUD's
## match_ended ends it, and an endless run (mode "endless") plays the next one after a short delay.

const STALEMATE_SEED := 9000
const LOGIC := "res://scenes/game/match_logic.gd"

## Seconds before an undecided match is called, read by the probe as on the real Main.
@export var endless_time_limit: float = 600.0
## Endless run: physics frames between a match ending and the next one starting.
@export var endless_delay_frames: int = 2

var _endless := false
var _seed := 0
var _matches := 0
var _by_name_calls := 0


func _ready() -> void:
	$SetupMenu.start_requested.connect(_on_setup_chosen)
	var touch := OS.get_environment("FIXTURE_TOUCH")
	if touch != "":
		FileAccess.open(touch, FileAccess.WRITE).store_string("written by a coverage run\n")


func _on_setup_chosen(config: Dictionary) -> void:
	_endless = str(config.get("mode", "watch")) == "endless"
	_seed = int(config.get("seed", 0))
	load(LOGIC).new().side_count(_count(config.get("defenders")))
	call("_by_name")
	_play()


## A side's count: `{ count, ... }` as the setup window sends it, or a bare count.
func _count(side: Variant) -> int:
	if side is Dictionary:
		return int(side.get("count", 0))
	return int(side)


func _play() -> void:
	_new_world()
	var logic = load(LOGIC).new()
	logic.every_match()
	logic.seed_parity(_seed)
	load("res://scenes/constructs/forms.gd").new().run(3)
	load("res://scenes/constructs/edge.gd").new().run()
	load("res://scenes/constructs/unsure.gd").new().run()
	var tool_node = load("res://scenes/constructs/tool_script.gd").new()
	tool_node.touched()
	tool_node.free()
	if _seed >= STALEMATE_SEED:
		$Worker.stall()
	else:
		$Worker.start(3)


## Reached only through the `pinged` connection in main.tscn.
func _on_worker_pinged() -> void:
	$MatchHUD.finish("INVADER WINS")
	if _endless:
		for _i in endless_delay_frames:
			await get_tree().physics_frame
		load(LOGIC).new().endless_teardown()
		_play()


## Reached only through call("_by_name").
func _by_name() -> void:
	_by_name_calls += 1


## A match's world, in the group `match_world` as on the real Main (a fresh one per match, the last one freed):
## the probe times a match from it.
func _new_world() -> void:
	_matches += 1
	for old in get_tree().get_nodes_in_group(&"match_world"):
		old.queue_free()
	var world := Node.new()
	world.add_to_group(&"match_world")
	add_child(world)
