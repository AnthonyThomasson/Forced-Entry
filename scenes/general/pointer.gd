class_name Pointer
## General domain: the one place a screen point and a world point are converted, and where the
## pointer is read. Every method takes a context `node` (any node of the world) and reads that
## node's viewport, so two worlds in two viewports (the player's view's memory and mask, a test's
## sub-viewport) each convert by their own view. In 2D it is backed by the viewport's canvas
## transform: the active `Camera2D`'s view, the identity in a world with no camera. #193's 3D view
## swaps the bodies for a camera ray meeting the ground plane; no caller changes.
##
## `inject` stands a screen point in for the mouse wherever its position is polled
## (`screen_mouse`, `world_mouse`) until `release`. It never warps the real mouse, and an input
## event keeps the position it carries. The injected point is one static, released by
## `TestWorld.restore`, so no test leaks it into the next.

## The injected screen point; meaningful only while `_injected` is set.
static var _injected_point := Vector2.ZERO
## Whether a screen point stands in for the mouse (`inject` sets it, `release` clears it).
static var _injected := false


## The world point under `screen`, a point of `node`'s viewport (the inverse of `screen_transform`).
static func world_of(node: Node, screen: Vector2) -> Vector2:
	return screen_transform(node).affine_inverse() * screen


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


## The part of the world `node`'s viewport shows, as a rect of world points (its visible rect
## taken back through `screen_transform`). Empty when `node` is in no viewport.
static func visible_world_rect(node: Node) -> Rect2:
	var viewport := node.get_viewport()
	if viewport == null:
		return Rect2()
	return screen_transform(node).affine_inverse() * viewport.get_visible_rect()


## The transform from world points to `node`'s viewport's screen points: its canvas transform (the
## active camera's view; the identity with no camera or no viewport). The player's view copies it
## into the viewports it renders the world through, so they show what the main one shows.
static func screen_transform(node: Node) -> Transform2D:
	var viewport := node.get_viewport()
	return viewport.get_canvas_transform() if viewport != null else Transform2D.IDENTITY


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
