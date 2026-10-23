extends Node2D
## UI domain: the squad-leaders debug overlay (`docs/leadership.md` LD12), a global toggle of the
## overlay bar (`OverlayRegistry.LEADERS`, `show_leaders`, off by default). A crown over each side's
## leader, in any match (a played one or Watch / Endless), so who leads, and who leads next once a
## leader falls, can be seen. The match builder (`MatchBuilder`) builds one with the squads, under
## the match's `World` node or a test world (world space), drawn at `DrawLayers.ABOVE` (interface
## 11) so a character never hides its crown.
##
## With the crown it draws how the squad follows its leader, per squad: the leash ring round the
## living leader (the view's `leash`, how far a follower fights from it), each follower's follow
## spot with a thin line from the follower to it (each member's `follow_spot`, none at INF), and the
## leader's trail as a dotted line (the view's `trail`, oldest point first).
##
## A decoupled observer like the order markers: `watch(views)` takes the squads' `view()` callables
## (`{ leader, members, trail, leash }`, interface 21), polled each frame while shown; it reads the
## leader and the members through the Character API only (`global_position`, `is_dead`).
## `PROCESS_MODE_ALWAYS`: it stays on the squad while the match is paused.

## The colours of the crown, the leash ring, a follow spot (its ring and its line) and the trail.
const CROWN_COLOR := Color(1.0, 0.82, 0.25, 0.95)
const LEASH_COLOR := Color(1.0, 0.82, 0.25, 0.35)
const SPOT_COLOR := Color(0.55, 0.9, 1.0, 0.8)
const TRAIL_COLOR := Color(1.0, 0.82, 0.25, 0.6)
## How far above the body the crown floats, and its size.
const LIFT := 30.0
const SIZE := 9.0
## A follow spot's ring (px).
const SPOT_RADIUS := 6.0
## The trail's dots: dash and gap (px).
const DOT := 3.0

## Whether the crowns are drawn (the overlay bar's `show_leaders`).
var show_leaders := false:
	set(on):
		show_leaders = on
		queue_redraw()
## The squads' `view()` callables.
var _views: Array = []
## What is drawn now (`drawn()`).
var _drawn: Array = []


func _init() -> void:
	z_index = DrawLayers.ABOVE  # Over the floor and the standing world.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var now := _squad_marks() if show_leaders else []
	if now != _drawn:
		_drawn = now
		queue_redraw()


func _draw() -> void:
	for c: Dictionary in _drawn:
		match String(c["kind"]):
			"leash":
				draw_arc(to_local(c["point"]), c["radius"], 0.0, TAU, 96, LEASH_COLOR, 1.5)
			"spot":
				draw_arc(to_local(c["point"]), SPOT_RADIUS, 0.0, TAU, 16, SPOT_COLOR, 1.5)
			"line":
				draw_line(to_local(c["from"]), to_local(c["to"]), SPOT_COLOR, 1.0)
			"trail":
				var points: Array = c["points"]
				for i in points.size() - 1:
					draw_dashed_line(
						to_local(points[i]),
						to_local(points[i + 1]),
						TRAIL_COLOR,
						1.5,
						DOT,
					)
			"crown":
				_draw_crown(to_local(c["point"]) + Vector2(0, -LIFT))


## A crown with its top at `top` (local).
func _draw_crown(top: Vector2) -> void:
	var crown := PackedVector2Array([
		top + Vector2(-SIZE, SIZE * 0.6), top + Vector2(-SIZE, -SIZE * 0.4),
		top + Vector2(-SIZE * 0.5, 0), top + Vector2(0, -SIZE), top + Vector2(SIZE * 0.5, 0),
		top + Vector2(SIZE, -SIZE * 0.4), top + Vector2(SIZE, SIZE * 0.6),
	])
	draw_colored_polygon(crown, CROWN_COLOR)
	draw_polyline(crown + PackedVector2Array([crown[0]]), Color(0, 0, 0, 0.8), 1.5)


## Watch the squads through their `view()` callables.
func watch(views: Array) -> void:
	_views = views.duplicate()


## What is drawn right now, [] while hidden: per squad, `{ kind: "crown", point, node }` (the crown
## over its living leader), `{ kind: "leash", point, radius, node }` (the ring round it),
## `{ kind: "spot", point, node }` and `{ kind: "line", from, to, node }` per follower with a follow
## spot, and `{ kind: "trail", points }` (the leader's trail, two points or more).
func drawn() -> Array:
	return _drawn


## Everything each squad's view shows: its leader's crown and leash, its followers' spots and lines,
## its trail. A view without `leash` / `trail` / `follow_spot` gives crowns alone.
func _squad_marks() -> Array:
	var out: Array = []
	for view_of in _views:
		var view: Dictionary = (view_of.call()
				if view_of is Callable and (view_of as Callable).is_valid()
				else {})
		var leader = view.get("leader")
		if not _alive(leader):
			continue
		var at: Vector2 = leader.global_position
		out.append({ "kind": "crown", "point": at, "node": leader })
		if float(view.get("leash", 0.0)) > 0.0:
			out.append({
				"kind": "leash",
				"point": at,
				"radius": float(view["leash"]),
				"node": leader,
			})
		for row: Dictionary in view.get("members", []):
			var spot: Vector2 = row.get("follow_spot", Vector2.INF)
			var member = row.get("node")
			if spot == Vector2.INF or not _alive(member):
				continue
			out.append({ "kind": "spot", "point": spot, "node": member })
			out.append({
				"kind": "line",
				"from": member.global_position,
				"to": spot,
				"node": member,
			})
		var trail := Array(view.get("trail", []))
		if trail.size() >= 2:
			out.append({ "kind": "trail", "points": trail })
	return out


## Whether `who` is a living character in the world.
func _alive(who) -> bool:
	return who is Node2D and is_instance_valid(who) and who.get("is_dead") != true
