extends RefCounted
## AI BEHAVIOUR sub-domain — LOCOMOTION's doors, its part `doors`: a walk the entry guard covers
## keeps out of the view of every doorway into a room not clear for passing when it can (E18), on
## the Navigation domain's avoid map, which has those views carved out too, when the route round
## them is within the cap the perception works out (`update`). Built once with its Locomotion, it
## holds it (a node, so no reference cycle) for the walk's goal and way.

## Seconds between looks at the route a door-avoiding walk takes (the views change as rooms are
## cleared and expire, and the avoid map is only kept for a walk that keeps asking for it).
const RECHECK := 2.0
## The perception's doorway views part (`views`), whose walks this part asks about.
const PerceptionViews := preload("res://scenes/ai/perception/perception_views.gd")

## The Locomotion it belongs to.
var loco: Node
## The perception's views part (`AgentPerception.views`: `walk_route(to)`), asked whether a walk
## goes round the doorway views.
var views: PerceptionViews
## The walk under way is one that keeps out of the doorway views (set each tick by `Behavior`: the
## walks the entry guard covers).
var avoid_doors := false
## The entry the walk is the approach of (`"<opening id>><room key>"`, "" for none): it keeps out of
## that room and of that doorway's view (`AgentPerception.views.walk_route`). Another one is another
## walk: its way is decided afresh.
var avoid_entering := "":
	set(v):
		if v != avoid_entering:
			decided = false
		avoid_entering = v
## The room a held stack's member's walks keep out of, the one its stack is held to enter ("" for
## none; set each tick by `Behavior` with its doorway, `keep_out_of`, D38): a walk whose plain way
## goes into it goes round it, and round that doorway's view, as that stack's approach would; any
## other walk is left as it is.
var held_room := ""
## The held stack's entry, `"<opening id>><room key>"` ("" for none), as `walk_route` takes it.
var _held_entry := ""
## The goal `_out_enters` was worked out for.
var _out_goal := Vector2.INF
## Whether the plain way to `_out_goal` goes into `held_room`.
var _out_enters := false
## The walk has been checked against the doorway views: it goes round them (`map`) or needs no way
## round.
var decided := false
## The avoid map the walk goes round the doorway views on (invalid: the walk is not door-avoiding).
var map := RID()
## Seconds until the door-avoiding walk next looks at its route.
var _doors_in := 0.0


func _init(locomotion: Node) -> void:
	loco = locomotion


## Keep the walk out of the doorway views (E18) when it is a walk that does (`avoid_doors`): ask the
## perception's views part for the route to the goal (`walk_route`: the plain one unless it goes
## into a view of a doorway into a room not clear for passing and a route round the views is within
## the cap) and put the walk on the avoid map it names, or leave it plain. Asked each frame until it
## is decided (while the avoid map is being baked the walk goes the plain way), then every `RECHECK`
## s for a walk that is round the views, which keeps the map alive and follows the views as rooms
## are cleared and their clear lapses. A body in the way still has its way (`Locomotion._check`):
## the walk goes round it by the steering map or is held, and the guard secures what views that
## crosses.
func update(delta: float) -> void:
	if views == null or not (avoid_doors or _keeps_out()):
		_drop_doors()
		return
	if decided and not map.is_valid():
		return  # Needs no way round.
	if decided:
		_doors_in -= delta
		if _doors_in > 0.0:
			return
	_doors_in = RECHECK
	if avoid_entering == "" and _keeps_out():
		var held_walk := true
		_take_route(views.walk_route(loco._goal, _held_entry, Vector2.INF, held_walk))
	else:
		_take_route(views.walk_route(loco._goal, avoid_entering))


## Whether the walk stands where it is for now: it keeps out of the held stack's room
## (`held_room`, D38) and its way round is not decided yet (its map is being baked), so the plain
## way meanwhile would take it into that room, from that room's doorway at once.
func waiting() -> bool:
	return not decided and avoid_entering == "" and views != null and _keeps_out()


## The held stack the walks keep out of (D38): its doorway `opening` and the room `room` it is held
## to enter ("" for none). Another one is another walk: its way is decided afresh.
func keep_out_of(opening: String, room: String) -> void:
	var entry := "%s>%s" % [opening, room] if opening != "" and room != "" else ""
	if entry == _held_entry:
		return
	decided = false
	_held_entry = entry
	held_room = room if entry != "" else ""
	_out_goal = Vector2.INF


## Whether the walk's way to the goal stands clear, on the avoid map round the doorway views it is
## on (none: false), of every known body at rest (`resting`): `Locomotion._clear_on` from `from`.
func clear_way(from: Vector2, resting: Array) -> bool:
	return map.is_valid() and loco._clear_on(map, from, resting)


## Whether the walk keeps out of the held stack's room (`held_room`): its plain way to the goal
## goes into it, worked out once per goal.
func _keeps_out() -> bool:
	if held_room == "":
		return false
	if loco._goal != _out_goal:
		_out_goal = loco._goal
		_out_enters = (loco._goal != Vector2.INF
				and views.walk_enters(loco._goal, held_room))
	return _out_enters


## Whether the walk's way to the goal on navigation map `on` (the steering map round bodies) goes
## into the held stack's room it keeps out of (`held_room`, D38): no way round a body that does is
## taken.
func enters_kept_out(on: RID) -> bool:
	return held_room != "" and views.walk_enters(loco._goal, held_room, on)


## A walk that does not keep out of the doorway views: it forgets the avoid map, and one on it goes
## the plain way.
func _drop_doors() -> void:
	decided = false
	if map.is_valid():
		map = RID()
		if loco._way == loco.Way.DOORS:
			loco._set_way(loco.Way.PLAIN)


## Put the walk on the way the perception's views part's `route` (`walk_route`) names: the avoid map
## round the views, or the plain way; while that map is being baked, ask again next frame.
func _take_route(route: Dictionary) -> void:
	if bool(route["doors"]):
		decided = true
		map = route["map"]
		if loco._way == loco.Way.PLAIN or loco._way == loco.Way.DOORS:
			loco._set_way(loco.Way.DOORS)
	elif not bool(route["pending"]):
		decided = true
		map = RID()
		if loco._way == loco.Way.DOORS:
			loco._set_way(loco.Way.PLAIN)
	else:
		_doors_in = 0.0  # The avoid map is being baked: ask again next frame.
