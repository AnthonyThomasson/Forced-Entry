extends GameTest
## Spike of #193: 3D runs under the headless test runner. An orthographic Camera3D, a MeshInstance3D
## and a shadow-casting DirectionalLight3D go into a SubViewport (the shape the 3D render will take
## under a CanvasLayer), enter the tree, process for a few frames and project a ground point through
## the camera without the engine logging an error or a warning (the log gate fails the test if it
## does). The projection is the isometric ground (x, 0, y) the mirror of #193 will rely on: the
## world's origin at the viewport's centre, +x down-right and +z down-left, at the 2:1 diamond's
## slope.

const SIZE := Vector2i(320, 180)
const PITCH_DEG := 35.264
const YAW_DEG := 45.0
const DISTANCE := 400.0


func describe() -> Dictionary:
	return {
		"name": "3D renders headless: an orthographic camera, a mesh and a shadowed light",
		"description": "A SubViewport with an orthographic Camera3D, a box MeshInstance3D and a "
			+ "shadow-casting DirectionalLight3D enters the tree and processes with no engine "
			+ "error; the camera projects the ground (x, 0, y) as an isometric view.",
		"tags": ["spike", "3d", "render"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	t.world.add_child(viewport)
	var camera := _camera(viewport)
	var box := _scene(viewport)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	viewport.add_child(sun)

	await t.frames(5)

	t.require(camera.is_inside_tree(), "the camera entered the tree")
	t.require(
		box.is_inside_tree() and sun.is_inside_tree(),
		"the mesh and the light entered the tree",
	)
	t.check(viewport.get_camera_3d() == camera, "the SubViewport's current camera is ours")
	t.check(sun.shadow_enabled and box.is_visible_in_tree(), "the light shadows a visible mesh")
	t.check(
		viewport.world_3d != t.world.get_viewport().world_3d,
		"the SubViewport has a 3D world of its own (nothing leaks into the game's)",
	)
	_check_ground(t, camera)


func _camera(viewport: SubViewport) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 200.0
	camera.near = 1.0
	camera.far = 2000.0
	viewport.add_child(camera)
	camera.rotation_degrees = Vector3(-PITCH_DEG, YAW_DEG, 0.0)
	camera.position = camera.basis.z * DISTANCE
	camera.make_current()
	return camera


## A shadow-casting box standing on a floor plane; returns the box.
func _scene(viewport: SubViewport) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(40, 40, 40)
	box.mesh = mesh
	box.position = Vector3(0, 20, 0)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	viewport.add_child(box)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	floor_mesh.mesh = plane
	viewport.add_child(floor_mesh)
	return box


## At yaw 45 and the true isometric pitch the ground's +x runs down-and-right on the screen and +z
## (the 2D y) down-and-left, each at tan 30 = 0.577 of a pixel down per pixel across.
func _check_ground(t: TestContext, camera: Camera3D) -> void:
	var centre := camera.unproject_position(Vector3.ZERO)
	var middle := Vector2(SIZE) * 0.5
	t.expect_near(centre.x, middle.x, 1.0, "the ground origin projects to the centre x")
	t.expect_near(centre.y, middle.y, 1.0, "the ground origin projects to the centre y")
	var along_x := camera.unproject_position(Vector3(50, 0, 0)) - centre
	var along_z := camera.unproject_position(Vector3(0, 0, 50)) - centre
	t.check(along_x.x > 0.0 and along_x.y > 0.0, "ground +x runs down-right (%s)" % along_x)
	t.check(along_z.x < 0.0 and along_z.y > 0.0, "ground +z runs down-left (%s)" % along_z)
	t.expect_near(absf(along_x.y / along_x.x), 0.577, 0.05, "the ground's slope is isometric")
