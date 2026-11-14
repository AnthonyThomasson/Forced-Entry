extends Node
## Spike of #193's showroom: owns the 3D view, the picker and the screen-relative walk. The sets
## (`IsoConfig.SETS`) are a post and a pitch each; a pick sets both on the view. The 2D world under
## it is hidden (it still runs: the player collides with the room's walls and furniture, which the
## view mirrors). WASD walks relative to the screen at any yaw (the sandbox's own input: the
## production job reads it properly); hold Q / E to turn the camera.
##
## Two headless-friendly user arguments: `--showroom-cycle=<s>` presses Next every `s` seconds
## through every set and back, then quits; `--showroom-shots=<dir>` saves a PNG of each set and
## one mid-turn (a windowed run), then quits.

const IsoConfig := preload("res://sandboxes/showroom/iso_render/iso_config.gd")
const IsoView := preload("res://sandboxes/showroom/iso_render/iso_view.gd")
const IsoPicker := preload("res://sandboxes/showroom/iso_render/iso_picker.gd")

var view: Node
var _picker: CanvasLayer
var _walker: Node2D
var _index := 0


func _physics_process(_delta: float) -> void:
	if _walker == null or not is_instance_valid(_walker):
		return
	var screen_x := _axis(KEY_D, KEY_A)
	var screen_y := _axis(KEY_W, KEY_S)
	var up: Vector2 = view.screen_up_on_ground()
	var world := Vector2(-up.y, up.x) * screen_x + up * screen_y
	_drive(Keybinds.MOVE_RIGHT, world.x)
	_drive(Keybinds.MOVE_LEFT, -world.x)
	_drive(Keybinds.MOVE_DOWN, world.y)
	_drive(Keybinds.MOVE_UP, -world.y)


func _exit_tree() -> void:
	for action: String in [
		Keybinds.MOVE_RIGHT, Keybinds.MOVE_LEFT, Keybinds.MOVE_DOWN, Keybinds.MOVE_UP,
	]:
		Input.action_release(action)


## Hold `action` at `strength` (released at none), whatever the real key's own event says.
func _drive(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _axis(positive: Key, negative: Key) -> float:
	var plus := float(Input.is_physical_key_pressed(positive))
	return plus - float(Input.is_physical_key_pressed(negative))


## Build the view over `world`, following `walker`, with the furniture `heights` (by name prefix).
func setup(world: Node2D, walker: Node2D, heights: Dictionary) -> void:
	_walker = walker
	view = IsoView.new()
	view.follow = walker
	add_child(view)
	view.mirror_world(world, heights)
	world.visible = false
	_picker = IsoPicker.new()
	var titles: Array[String] = []
	var notes: Array[String] = []
	for i in IsoConfig.SETS.size():
		titles.append(IsoConfig.title_of(i))
		notes.append(IsoConfig.POSTS[IsoConfig.SETS[i]["post"]]["note"])
	_picker.setup(titles, notes)
	_picker.picked.connect(_show)
	add_child(_picker)
	process_physics_priority = -100
	_show(0)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--showroom-cycle="):
			_cycle(float(argument.get_slice("=", 1)))
		elif argument == "--showroom-walk":
			_walk_check()
		elif argument.begins_with("--showroom-shots="):
			_shots(argument.get_slice("=", 1))


func _show(index: int) -> void:
	_index = index
	var row: Dictionary = IsoConfig.SETS[index]
	view.set_post(row["post"])
	view.set_pitch(row["pitch"])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Press W, then D, as real key events at two yaws and print where the player went against the
## screen's up and right on the ground (`ok` when within about 25 degrees), then quit.
func _walk_check() -> void:
	await _frames(40)
	for yaw in [45.0, 120.0]:
		view.yaw = yaw
		await _frames(5)
		var up: Vector2 = view.screen_up_on_ground()
		for key: Key in [KEY_W, KEY_D]:
			var wanted := up if key == KEY_W else Vector2(-up.y, up.x)
			var start := _walker.global_position
			_key(key, true)
			await _frames(30)
			_key(key, false)
			await _frames(10)
			var moved := _walker.global_position - start
			var along := moved.normalized().dot(wanted) if moved.length() > 1.0 else 0.0
			print("showroom walk: yaw %d key %s moved %s cos %.2f %s" % [
				int(yaw), OS.get_keycode_string(key), moved.round(), along,
				"ok" if along > 0.9 else "WRONG",
			])
	get_tree().quit()


func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _cycle(seconds: float) -> void:
	for _step in IsoConfig.SETS.size() + 1:
		await get_tree().create_timer(seconds).timeout
		_picker.step(1)
	get_tree().quit()


func _shots(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	# The runner's own banner and overlay bar are left out of the pictures.
	for layer: CanvasLayer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		if layer != _picker and layer != view.get_node("IsoLayer"):
			layer.visible = false
	await _frames(40)
	for i in IsoConfig.SETS.size():
		_picker.show_index(i)
		_show(i)
		await _frames(30)
		_save(directory, "set%d_%s" % [i + 1, IsoConfig.title_of(i)])
	_picker.show_index(1)
	_show(1)
	view.auto_turn = IsoConfig.TURN_SPEED
	await _frames(25)
	_save(directory, "mid_turn_%s" % IsoConfig.title_of(1))
	get_tree().quit()


func _save(directory: String, label: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var file := "%s/%s.png" % [
		directory,
		label.validate_filename().replace(" ", "_").replace(",", "").replace("\u00b0", ""),
	]
	print("showroom shot: ", file, " ", image.save_png(file))
