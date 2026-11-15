class_name WallFade
extends Node3D
## Art domain, the wall fade of the 3D render (#193 rule 9, interface 27,
## `domain-art/wall-fade.md`): a wall, a door or a tall piece that stands between the camera and a
## character, within `WallFadeConfig.radius`, thins out (`MeshNodes.fade`: a dither of the picture's
## pixels, so it stays opaque pixels and reads as pixel art) so the character is never hidden; the
## rest of the world stays whole. The characters it looks after are the camera's focus: the player,
## or every live character of the match while spectating (`focus_targets()` of the sim's `Camera2D`,
## General).
##
## Each frame, for each focus, it asks the units in the grid cells the focus's reach touches
## (`FadeGrid`) which the line along the ground from the focus toward the camera first meets near
## enough, and under their top there (the camera's ray rises with its pitch). A unit in the way
## fades in `WallFadeConfig.fade_time`, one that is not comes back in the same time, and an
## instance is written only when its level (a step of `steps`) changes, so a still view costs the
## lookups and no writes; nothing is allocated per frame.
##
## What it fades it is told by the mirror: `listen(mirror)` takes every mesh a builder makes for a
## wall, a door or a furniture body (`WorldMirror.built`), whenever the builder was registered, and
## `FadeBook` makes units of them (a wall's segments, or a piece's instances; a rebuilt segment or
## a piece built again keeps its fade).

## The camera rig (its yaw is the line's direction) and the sim's camera (it names the focus).
var rig: CameraRig
var source: Node
## The grid the units are found in, how many units are kept and not whole now, how many instances
## the last step wrote and how many units it asked.
var grid := FadeGrid.new()
var fading := 0
var written := 0
var looked := 0
var _listed: Array[FadeUnit] = []
var _book := FadeBook.new(grid, _listed)
var _frame := 0
var _probe := 0
var _foci := PackedVector2Array()


func _init() -> void:
	name = "WallFade"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 60  # after the rig (50) turned the camera this frame


func _process(delta: float) -> void:
	_gather()
	step(delta, rig.yaw if rig != null else RenderConfig.yaw_degrees, _foci)


## Take the meshes `mirror` builds for walls, doors and furniture from now on. Call it before the
## mirror starts: every builder, registered before or after, is then looked after.
func listen(mirror: WorldMirror) -> void:
	if not mirror.built.is_connected(on_built):
		mirror.built.connect(on_built)


## A builder made `mesh` for `body` (`WorldMirror.built`): a wall, a door or a piece of furniture is
## looked after, a movable one (a rigid body, a door: not a plain `StaticBody2D`) polled for a move.
func on_built(body: Node, mesh: Node3D) -> void:
	var kind := MirrorProxy.kind_of(body)
	if kind == MirrorProxy.WALL or kind == MirrorProxy.DOOR or kind == MirrorProxy.FURNITURE:
		watch(mesh, body.get_instance_id(), not body is StaticBody2D or body is AnimatableBody2D)


## Look after `mesh`, the 3D mesh of the body `key` (its instance id): from the next frame it is in
## the tree. `movable` for a piece that can be shoved or swung.
func watch(mesh: Node3D, key: int, movable := false) -> void:
	_book.watch(mesh, key, movable)


## How many units it keeps.
func count() -> int:
	return _book.count


## The unit of segment `index` of the mesh watched under `key` (a piece is index 0), or null.
func unit_of(key: int, index := 0) -> FadeUnit:
	return _book.unit_of(key, index)


## One frame of the fade: `delta` seconds, the camera at `yaw_degrees`, `foci` the 2D world points
## (px) of the characters it looks after. Called by `_process`; a test calls it by hand.
func step(delta: float, yaw_degrees: float, foci: PackedVector2Array) -> void:
	_frame += 1
	_book.admit()
	grid.poll()
	var yaw := deg_to_rad(yaw_degrees)
	var back := Vector2(sin(yaw), cos(yaw))  # the ground direction toward the camera
	var rise := tan(deg_to_rad(RenderConfig.pitch_degrees))
	var factor := RenderConfig.unit
	var reach := WallFadeConfig.radius * factor
	looked = 0
	for focus in foci:
		_probe += 1
		_look_in_grid(focus * factor, back, reach, rise)
	_advance(delta)


## The point each of the camera's focus targets stands at, in px (what `step` is given).
func _gather() -> void:
	_foci.clear()
	if not is_instance_valid(source) or not source.has_method(&"focus_targets"):
		return
	for target: Variant in source.call(&"focus_targets"):
		if is_instance_valid(target) and target.get("is_dead") != true:
			_foci.append((target as Node2D).global_position)


## Look at every unit filed in a cell the focus's reach touches, each once.
func _look_in_grid(from: Vector2, back: Vector2, reach: float, rise: float) -> void:
	for cx in range(grid.cell_of(from.x - reach), grid.cell_of(from.x + reach) + 1):
		for cz in range(grid.cell_of(from.y - reach), grid.cell_of(from.y + reach) + 1):
			for unit: FadeUnit in grid.at(cx, cz):
				if unit.probe != _probe:
					unit.probe = _probe
					looked += 1
					_look(unit, from, back, reach, rise)


## Mark `unit` as in the way when the strip of the character's width from `from` toward the camera
## meets it within `reach` and under its top.
func _look(unit: FadeUnit, from: Vector2, back: Vector2, reach: float, rise: float) -> void:
	if unit.hit_frame == _frame:
		return
	var width := WallFadeConfig.half_width * RenderConfig.unit
	var box := unit.box
	var near := reach + box.bound + width
	if from.distance_squared_to(box.centre) > near * near:
		return
	var along := box.strip_entry(from, back, width)
	if along < 0.0 or along > reach or along * rise > box.top:
		return
	_mark(unit)


## `unit` is in the way this frame, and so is every piece hung on it: they fade with their wall.
func _mark(unit: FadeUnit) -> void:
	unit.hit_frame = _frame
	if not unit.listed:
		unit.listed = true
		_listed.append(unit)
	for piece in unit.hang.followers:
		piece.hit_frame = _frame
		if not piece.listed:
			piece.listed = true
			_listed.append(piece)


## Step every listed unit toward faded (in the way this frame) or whole, writing the ones whose
## level changed; a unit that is whole and not in the way leaves the list.
func _advance(delta: float) -> void:
	written = 0
	var rate := delta / maxf(WallFadeConfig.fade_time, 0.001)
	var i := 0
	while i < _listed.size():
		var unit := _listed[i]
		var wanted := 1.0 if unit.hit_frame == _frame else 0.0
		unit.faded = move_toward(unit.faded, wanted, rate)
		if unit.apply():
			written += 1
		if unit.faded <= 0.0 and wanted == 0.0:
			unit.listed = false
			_listed[i] = _listed.back()
			_listed.pop_back()
			continue
		i += 1
	fading = _listed.size()
