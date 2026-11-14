extends RefCounted
## Shared helper for the tests that put a test world in the 3D render mode (not a test itself):
## `const RigProbe := preload("res://tests/_general/rig_probe.gd")`. `open` binds General's
## `CameraRig` to the world's own `Camera2D` and viewport, as Main's 3D view does, so Pointer
## converts the world's nodes through the orthographic camera; the rig and its picture are freed
## with the world.


## Make `camera` (current, in `world`) the sim's camera of a 3D view at `yaw` degrees; returns the
## rig. The picture's `SubViewport` and the control showing it go under `world`.
static func open(world: Node, camera: Camera2D, yaw: float) -> CameraRig:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world.add_child(view)
	var rect := TextureRect.new()
	rect.texture = view.get_texture()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(rect)
	var rig := CameraRig.new()
	rig.yaw = yaw
	view.add_child(rig)
	rig.bind(camera, view, rect)
	return rig
