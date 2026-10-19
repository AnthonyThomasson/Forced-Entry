extends "res://scenes/ai/debug/debug_overlay.gd"
## AI domain: an optional debug overlay that draws the NPC's *actual* visible area — the portions
## of the forward FOV cone and the 360° near-awareness bubble that have a direct, unobstructed line
## of sight back to the NPC. A ray fan asks the controller each frame where the NPC's sight ends
## (`debug_sight_end`, the perception's own rule: walls and TALL furniture block, low pieces are
## seen over) and builds a visibility polygon from the answers, so the shadows are exactly the
## sense's and show only the area that would trigger a detection. Toggle with `show_vision`.
## Draw-only — it senses nothing and feeds nothing back (follows the "draw on its own child Node2D"
## convention).

## Rays cast across the forward FOV arc (higher = smoother wall edges, more cost).
const CONE_RAYS := 64
## Rays cast for the 360° awareness-bubble sweep.
const BUBBLE_RAYS := 48

## Whether to draw the vision overlay at all.
@export var show_vision: bool = true
## Fill colour for the forward view cone's line-of-sight area.
@export var cone_color: Color = Color(0.3, 0.8, 1.0, 0.12)
## Fill colour for the near-awareness bubble's line-of-sight area.
@export var bubble_color: Color = Color(1.0, 0.9, 0.3, 0.5)

## The view cone's visible area, local points (rebuilt each frame).
var _cone_poly: PackedVector2Array = PackedVector2Array()
## The awareness bubble's visible area, local points.
var _bubble_poly: PackedVector2Array = PackedVector2Array()
## The triangle arrays the last paint drew (`drawn()`).
var _drawn: Array = []


## Rebuild the visibility polygons every frame so they track the NPC's movement and facing (the base
## runs PROCESS_MODE_ALWAYS, so they are still built while the spectator inspector holds a
## Space-pause).
func _process(delta: float) -> void:
	if show_vision:
		_rebuild_visibility()
	super(delta)


## Whether this overlay's toggle is on.
func _on() -> bool:
	return show_vision


## Draw the cached visibility polygons built in _process, each as the fan of triangles it is by
## construction: every corner is where a ray from the eye ends, in the order the rays were cast, so
## the triangles from the eye to each pair of neighbouring corners cover it exactly. Handing the
## engine the polygon to cut again (`draw_polygon`) fails on a run of ray ends along one wall, which
## lie on one line only up to float noise (some read as reflex corners), and that frame's area would
## not be drawn.
func _paint() -> void:
	_drawn.clear()
	if _bubble_poly.size() >= 3:
		_fill_fan(&"bubble", Vector2.ZERO, _bubble_poly, true, bubble_color)
	if _cone_poly.size() >= 3:
		_fill_fan(&"cone", _cone_poly[0], _cone_poly.slice(1), false, cone_color)


## What the last paint drew: `[{ kind, points, indices }]`, one triangle array per area (`kind`
## `bubble` / `cone`), local points.
func drawn() -> Array:
	return _drawn


## Fill the fan of triangles from `eye` to each pair of neighbouring `corners` (local px, in ray
## order; `closed`: the last corner back to the first too, a sweep all the way round) in `color`, as
## one triangle array.
func _fill_fan(
	kind: StringName,
	eye: Vector2,
	corners: PackedVector2Array,
	closed: bool,
	color: Color,
) -> void:
	var points := PackedVector2Array([eye])
	points.append_array(corners)
	var indices := PackedInt32Array()
	var n := corners.size()
	for k in (n if closed else n - 1):
		indices.append_array([0, 1 + k, 1 + (k + 1) % n])
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(color)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)
	_drawn.append({ "kind": kind, "points": points, "indices": indices })


## Where the NPC's sight from `from` in `dir` ends: the first sight-blocking hit within `max_dist`,
## or the full-distance endpoint when the path is clear (the controller's `debug_sight_end`).
func _cast(from: Vector2, dir: Vector2, max_dist: float) -> Vector2:
	return _controller.debug_sight_end(from + dir * max_dist)


## Rebuild the LoS-masked visibility polygons for both the cone and the bubble.
## When vision is disabled (omniscient fallback) the bubble is drawn as a plain circle; the cone
## is skipped because the NPC sees everything regardless of facing.
func _rebuild_visibility() -> void:
	_cone_poly.clear()
	_bubble_poly.clear()
	if _controller == null or _character == null:
		return

	var facing: Vector2 = _character.facing
	var awareness: float = _controller.awareness_radius

	# Omniscient fallback: no raycasts, just plain geometry to mark the awareness bubble.
	if not _controller.vision_enabled:
		for i in range(BUBBLE_RAYS):
			_bubble_poly.append(Vector2.from_angle((float(i) / float(BUBBLE_RAYS)) * TAU)
					* awareness)
		return

	var from_pos: Vector2 = _character.global_position

	# Awareness bubble: 360° ray sweep clipped by LoS — walls reduce the radius in each direction.
	for i in range(BUBBLE_RAYS):
		var angle := (float(i) / float(BUBBLE_RAYS)) * TAU
		_bubble_poly.append(to_local(_cast(from_pos, Vector2.from_angle(angle), awareness)))

	# FOV cone: ray fan from left edge to right edge, each ray clipped at the first wall it hits.
	if facing == Vector2.ZERO:
		return
	var dist: float = _controller.view_distance
	var half_fov := deg_to_rad(_controller.fov_degrees) * 0.5
	var base := facing.angle()
	_cone_poly.append(Vector2.ZERO)
	for i in range(CONE_RAYS + 1):
		var t := float(i) / float(CONE_RAYS)
		var ray_angle := base - half_fov + t * deg_to_rad(_controller.fov_degrees)
		_cone_poly.append(to_local(_cast(from_pos, Vector2.from_angle(ray_angle), dist)))
