class_name Pointer
## General domain: the one place a screen point and a world point are converted, and where the
## pointer is read. Every method takes a context `node` (any node of the world) and reads that
## node's viewport, so two worlds in two viewports (the player's view's memory and mask, a test's
## sub-viewport) each convert by their own view. In 2D it is backed by the viewport's canvas
## transform: the active `Camera2D`'s view, the identity in a world with no camera.
##
## The `CameraRig` binds itself (`bind_3d`) and every node of the
## viewport the sim's `Camera2D` serves converts through the orthographic camera instead (no caller
## changes; the rig works the affine out once a frame, `refresh_3d`): a screen
## point is the camera ray that meets the ground plane y = 0, and the world's place on the screen is
## the exact ground-to-screen affine of that camera, read through the DISPLAYED rect of the 3D
## view (the control that shows the picture), never the picture's internal size, so the internal
## resolution changes nothing. A node of any other viewport still converts by its own canvas
## transform.
##
## `inject` stands a screen point in for the mouse wherever its position is polled
## (`screen_mouse`, `world_mouse`) until `release`. It never warps the real mouse, and an input
## event keeps the position it carries. The injected point is one static, released by
## `TestWorld.restore`, so no test leaks it into the next.

## How far (px) the cursor's line reaches each way from its ground point, how many solid twins it
## looks through (the player's own body and what the wall fade holds faded are looked through for
## free), and how many rays it casts at most in all.
const AIM_REACH := 4000.0
const AIM_WALK := 8
const AIM_RAYS := 32

## The injected screen point; meaningful only while `_injected` is set.
static var _injected_point := Vector2.ZERO
## Whether a screen point stands in for the mouse (`inject` sets it, `release` clears it).
static var _injected := false
## The 3D camera, the control that shows its picture and the viewport the sim's
## screen is (all null while no rig is bound). Untyped so a freed one is checked, not read.
static var _camera: Variant = null
static var _rect: Variant = null
static var _screen: Variant = null
## The ground-to-screen affine of the 3D camera, its inverse and the ground rect the screen shows,
## worked out once a frame by the rig (`refresh_3d`, after it has placed the camera and the
## picture), not on every call: a character asks for the visible rect each frame.
static var _affine := Transform2D.IDENTITY
static var _affine_inverse := Transform2D.IDENTITY
static var _ground_rect := Rect2()


## The world point under `screen`, a point of `node`'s viewport (the inverse of `screen_transform`).
static func world_of(node: Node, screen: Vector2) -> Vector2:
	return _screen_to_world(node) * screen


## Whether `node` is converted through the 3D camera (the rig is bound and `node` is in the viewport
## the sim's camera serves) rather than its viewport's canvas transform.
static func is_3d(node: Node) -> bool:
	return (
		is_instance_valid(_camera)
		and is_instance_valid(_screen)
		and (_camera as Camera3D).is_inside_tree()
		and node.get_viewport() == _screen
	)


## The world vector that `screen_vector`, a step on the screen, is a step along (the linear part of
## `screen_transform` inverted, so no origin): in 3D the ground vector that shows as that step, in
## 2D the canvas transform's own. A 3D controller turns a screen direction into a ground one by it.
static func world_vector(node: Node, screen_vector: Vector2) -> Vector2:
	return _screen_to_world(node).basis_xform(screen_vector)


## A screen direction as a world direction of the same length, for 3D's screen-relative controls:
## W up the screen is the ground direction that shows as up at any camera yaw. A 2D world, whose
## screen already is the world, gets `screen_dir` back untouched.
static func world_direction(node: Node, screen_dir: Vector2) -> Vector2:
	if screen_dir == Vector2.ZERO or not is_3d(node):
		return screen_dir
	return world_vector(node, screen_dir).normalized() * screen_dir.length()


## Bind the 3D camera (the `CameraRig` calls this in its `bind`): `camera` is the
## orthographic `Camera3D`, `rect` the control that shows its picture on the screen (null: the
## picture fills the screen) and `screen` the viewport the sim's `Camera2D` serves, whose nodes
## convert through it from now on. Left bound until `unbind_3d`.
static func bind_3d(camera: Camera3D, rect: Control, screen: Viewport) -> void:
	_camera = camera
	_rect = rect
	_screen = screen


## Work out the 3D camera's affine and the visible ground for this frame: the rig calls it once it
## has placed `camera` and the picture (a no-op for any camera but the bound one).
static func refresh_3d(camera: Camera3D) -> void:
	if _camera != camera or not is_instance_valid(_screen) or not camera.is_inside_tree():
		return
	_affine = _ground_to_screen()
	_affine_inverse = _affine.affine_inverse()
	# A turned view shows a diamond of ground: the rect that bounds the screen's four corners.
	var size: Vector2 = _screen.get_visible_rect().size
	var bounds := Rect2(_affine_inverse * Vector2.ZERO, Vector2.ZERO)
	for corner: Vector2 in [Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		bounds = bounds.expand(_affine_inverse * corner)
	_ground_rect = bounds


## Put the 2D body back, when `camera` is the one bound (the rig leaving the tree calls it).
static func unbind_3d(camera: Camera3D) -> void:
	if _camera == camera:
		_camera = null
		_rect = null
		_screen = null
		_affine = Transform2D.IDENTITY
		_affine_inverse = Transform2D.IDENTITY


## The screen point of `node`'s viewport that shows `world` (`screen_transform` applied to it).
static func screen_of(node: Node, world: Vector2) -> Vector2:
	return screen_transform(node) * world


## Where the pointer is on `node`'s viewport: the injected point while one is set (`inject`), else
## the real mouse. The camera's look-ahead and the command menu's non-mouse fallback read it.
static func screen_mouse(node: Node) -> Vector2:
	if _injected:
		return _injected_point
	var viewport := node.get_viewport()
	return viewport.get_mouse_position() if viewport != null else Vector2.ZERO


## The world point under the pointer (`world_of` the `screen_mouse`): the player's aim.
static func world_mouse(node: Node) -> Vector2:
	return world_of(node, screen_mouse(node))


## What the cursor's line of sight meets in the 3D render (`is_3d`), for the player's aim.
## The line is the camera's own, through the ground point under the mouse (an orthographic view's
## rays are parallel), cast into the twin space (`TwinSpace`, interface 29). It answers a dictionary
## of `kind`, `plan` (the 2D point) and `height` (px above the floor). Kind `&"body"`: the line
## meets a character's twin first (hovering a head is the head). Kind `&"cover"`: the first piece,
## wall, door or vehicle the line meets, with a character behind it or not (D8a): the point on it.
## Empty for neither (bare floor, or not in the 3D render): the player then shoots level at the
## muzzle's height toward the floor point. `ignore` (the player's own body) is looked through, and
## so is what the wall fade holds faded (`FadedTwins`): the twin stays solid while its mesh is
## dithered, and the cursor over floor seen through a faded wall is over that floor.
static func aim_hit(node: Node, ignore: Node = null) -> Dictionary:
	var space := TwinSpace.space_of(node) if is_3d(node) else null
	if space == null:
		return {}
	var look := -(_camera as Camera3D).global_transform.basis.z
	var through := PlanSpace.lift(world_mouse(node))
	var query := PhysicsRayQueryParameters3D.create(
		through - look * AIM_REACH, through + look * AIM_REACH, PhysicsLayers.TWIN_ALL
	)
	query.hit_from_inside = false
	var cover := {}
	var skip: Array[RID] = []
	var solid := 0
	for _i in AIM_RAYS:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		skip.append(hit.rid)
		query.exclude = skip
		var body := TwinSpace.owner_of(hit.collider)
		if body == null or body == ignore:
			continue
		if not body.is_in_group(TwinSpace.BODIES):
			break  # the floor: nothing was between the cursor and the ground
		var aimed := {
			"plan": PlanSpace.plan_of(hit.position), "height": PlanSpace.height_of(hit.position),
		}
		if FadedTwins.holds(body.get_instance_id(), aimed["plan"]):
			continue  # the wall fade shows it see-through: the cursor is over what is behind it
		solid += 1
		if (hit.collider as CollisionObject3D).collision_layer & PhysicsLayers.TWIN_CHARACTER != 0:
			aimed["kind"] = &"body"
			return aimed if cover.is_empty() else cover
		if cover.is_empty():
			cover = aimed
			cover["kind"] = &"cover"
		if solid >= AIM_WALK:
			break
	return cover


## The part of the world `node`'s viewport shows, as a rect of world points (its visible rect
## taken back through `screen_transform`). Empty when `node` is in no viewport.
static func visible_world_rect(node: Node) -> Rect2:
	var viewport := node.get_viewport()
	if viewport == null:
		return Rect2()
	if is_3d(node):
		return _ground_rect
	return screen_transform(node).affine_inverse() * viewport.get_visible_rect()


## The transform from world points to `node`'s viewport's screen points: its canvas transform (the
## active camera's view; the identity with no camera or no viewport). The player's view copies it
## into the viewports it renders the world through, so they show what the main one shows.
static func screen_transform(node: Node) -> Transform2D:
	if is_3d(node):
		return _affine
	var viewport := node.get_viewport()
	return viewport.get_canvas_transform() if viewport != null else Transform2D.IDENTITY


## The transform from `node`'s viewport's screen points to world points (`screen_transform`
## inverted; the 3D body keeps the inverse from `refresh_3d`).
static func _screen_to_world(node: Node) -> Transform2D:
	return _affine_inverse if is_3d(node) else screen_transform(node).affine_inverse()


## The exact affine of the orthographic camera from the ground plane (a 2D world point (x, y) is
## the 3D point (x, 0, y) times `RenderConfig.unit`) to the screen: the camera's right and up axes
## on the ground, scaled to the picture's pixels, then through where the control that shows the
## picture puts it. Built from the camera's own transform and size, in doubles, not from projected
## sample points, so it is exact far from the origin.
static func _ground_to_screen() -> Transform2D:
	var camera := _camera as Camera3D
	var picture := camera.get_viewport().get_visible_rect().size
	var rect := _rect as Control
	var shown: Vector2 = _screen.get_visible_rect().size if rect == null else rect.size
	var corner: Vector2 = Vector2.ZERO if rect == null else rect.global_position
	var in_picture := _ground_to_picture(camera, picture)
	var to_screen := shown / picture
	return Transform2D(
		in_picture.x * to_screen, in_picture.y * to_screen, corner + in_picture.origin * to_screen
	)


## The ground's place in the camera's picture, in picture pixels (y down): the camera's right and up
## axes on the ground times the pixels a 3D unit covers, about the picture's middle.
static func _ground_to_picture(camera: Camera3D, picture: Vector2) -> Transform2D:
	var pose := camera.global_transform
	var right := pose.basis.x
	var up := pose.basis.y
	var eye := pose.origin
	var depth := picture.y if camera.keep_aspect == Camera3D.KEEP_HEIGHT else picture.x
	var per_unit := depth / camera.size * RenderConfig.unit
	var lift := Vector2(eye.dot(right), eye.dot(up)) * depth / camera.size
	return Transform2D(
		Vector2(right.x, -up.x) * per_unit,
		Vector2(right.z, -up.z) * per_unit,
		Vector2(picture.x * 0.5 - lift.x, picture.y * 0.5 + lift.y),
	)


## Make `screen`, a point of the viewport, stand in for the mouse until `release`: `screen_mouse`
## and `world_mouse` return it, so the player's aim, the camera's look-ahead and the command menu's
## non-mouse fallback follow it. The real mouse is not moved, and an input event keeps its own
## position. `screen` is a point of the viewport the player plays in, so the context nodes of
## `screen_mouse` and `world_mouse` are nodes of that world (a node of a sub-viewport reads that
## viewport's own mouse while nothing is injected). A test calls it again each frame to hold a
## world point under the pointer while the camera eases.
static func inject(screen: Vector2) -> void:
	_injected_point = screen
	_injected = true


## End an `inject`: the real mouse is read again. A no-op while nothing is injected.
static func release() -> void:
	_injected = false
