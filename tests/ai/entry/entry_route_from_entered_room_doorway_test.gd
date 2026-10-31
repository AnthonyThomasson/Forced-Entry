extends GameTest
## E18 with D38's rule 9 (`docs/tactical-entry.md`, `docs/leadership.md`): the doorway rule of a
## held stack's walk reaches no other walk. The bare Terrace house; a walker stands in the doorway
## between the hall and the kitchen, just on the kitchen's side of the wall plane (within the wall
## and a body's reach of it), on a walk that is part of an entry into the kitchen by the back door,
## to a point in the living room: its plain way runs on through the kitchen and in by the
## living-kitchen doorway. The walk is asked of the AI's doorway views (`agent_door_views.gd`,
## loaded by path as `slots_probe.gd` loads the entry geometry: `set_house`, `walk_route`) over the
## world's house and maps, as an ordered stack's (`ordered_approach`, D4: its way round the room it
## enters taken however long it is):
## - not held: it is in the kitchen already, so the entry keeps it out of nothing, and its way goes
##   on through the kitchen;
## - held (a held stack's member keeping out of the kitchen, D38): standing in the doorway it is not
##   in the kitchen yet, so its way keeps out of it, round by the hall.
##
## No NPC: the subject is the route the mechanism gives. No NPC walk reaches the unheld case: an
## entry into the room the NPC stands in has its approach's waypoints in that room.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const VIEWS_SCRIPT := "res://scenes/ai/perception/agent_door_views.gd"
## Where the walker stands: in the hall-kitchen doorway, 5 px on the kitchen's side of its plane.
const START := Vector2(690, 355)
## Where it walks to: the living room, west of the living-kitchen doorway.
const GOAL := Vector2(300, 150)
## How deep (px) into a room a walker still stands in the doorway it is by: half the wall's
## thickness (12 px) and a body's radius (14 px), the spec's measure.
const DOORWAY := 20.0
## The entry the walk is part of: into the kitchen by the back door.
const ENTERING := "door_840_190>kitchen"
## How long (frames) the avoid maps the routes are on may take to bake.
const BAKE_FRAMES := 600


func describe() -> Dictionary:
	return {
		"name": "Only a held walk from the entered room's doorway keeps out of it",
		"description": "From the hall-kitchen doorway, on the kitchen's side, a walk of an entry "
			+ "into the kitchen goes on through the kitchen; held for its leader's go it goes "
			+ "round by the hall (E18, D38).",
		"tags": ["ai", "entry", "leadership", "stack", "movement", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)


func run(t: TestContext) -> void:
	if not t.require(
			Maps.HOUSE_KITCHEN.has_point(START) and not _past_doorway(START),
			"premise: the walker stands in the doorway, on the kitchen's side of its plane",
	):
		return
	var views: RefCounted = (load(VIEWS_SCRIPT) as GDScript).new()
	views.set_house(t.world.openings, t.rooms)
	views.pass_clear = func(_key: String) -> bool: return false
	views.ordered_approach = true
	var plain := await _route(t, views, false)
	var held := await _route(t, views, true)
	if not t.require(
			not plain.is_empty() and not held.is_empty(),
			"premise: both routes were worked out once their avoid maps baked",
	):
		return
	t.check(
		_through_kitchen(plain["path"]),
		"the walk not held goes on through the kitchen it stands in (%d px, round the views: %s)"
			% [int(plain["len"]), str(plain["doors"])],
	)
	t.check(
		not _through_kitchen(held["path"]) and Maps.HOUSE_LIVING.has_point(_end(held["path"])),
		"the held walk keeps out of the kitchen it stands in the doorway of, to the living room "
			+ "(%d px, round the views: %s)" % [int(held["len"]), str(held["doors"])],
	)


## The route from `START` to `GOAL` on a walk of `ENTERING`, `held` or not, once its avoid maps have
## baked; {} when they never did.
func _route(t: TestContext, views: RefCounted, held: bool) -> Dictionary:
	for i in BAKE_FRAMES:
		var way: Dictionary = views.walk_route(START, GOAL, t.world.get_world_2d(), ENTERING, held)
		if not bool(way["pending"]):
			return way
		await t.frames(1)
	return {}


## Where `path` ends (`START` for an empty one).
func _end(path: PackedVector2Array) -> Vector2:
	return path[-1] if not path.is_empty() else START


## Whether `path` (from `START`) comes into the kitchen past the hall-kitchen doorway.
func _through_kitchen(path: PackedVector2Array) -> bool:
	var pts: Array = [START] + Array(path)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var steps := maxi(int(a.distance_to(b) / 8.0), 1)
		for k in steps + 1:
			if _past_doorway(a.lerp(b, float(k) / float(steps))):
				return true
	return false


## Whether `p` is in the kitchen and clear of the hall-kitchen doorway (deeper than `DOORWAY`).
func _past_doorway(p: Vector2) -> bool:
	return Maps.HOUSE_KITCHEN.grow(-2.0).has_point(p) and p.y < Maps.DOOR_HALL_KITCHEN.y - DOORWAY
