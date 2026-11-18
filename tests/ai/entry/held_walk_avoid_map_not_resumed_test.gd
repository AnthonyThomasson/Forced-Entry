extends GameTest
## D38 rule 9 (`docs/leadership.md`, `docs/tactical-entry.md`): a held stack's member's walk never
## goes through the room its stack is to enter, and the avoid map it was given far off is not
## taken up again from where that map would route it through that room. The bare Terrace house; a
## member far off to the south asks the way to its staging point north of the back door, along the
## lane outside the east wall: the avoid map round the doorway views has it go all the way round
## the house (the lane is carved by the back door's view). It later stands in the lane at the back
## door's front, where the walk's way round a body is done and `Locomotion` would take the avoid
## map back up (`LocoDoors.enters_kept_out`): from there that map's route goes in at the back door
## and through the kitchen, while the way asked afresh from there is the plain one, along the lane.
## The map is not resumed from there: `enters_kept_out` is true on it and false on the plain map.
##
## No NPC: the subject is the answer the views give (`agent_door_views.gd`).

const Maps := preload("res://tests/_ai/flank_maps.gd")
const VIEWS_SCRIPT := "res://scenes/ai/perception/agent_door_views.gd"
## Where the walker stands: in the back door's view, on the lane outside the east wall.
const START := Vector2(869, 194)
## Where it first asks the way from: the lane's south end, far from the door.
const FAR := Vector2(873, 386)
## Where it walks to: the lane's north end, past the doorway.
const GOAL := Vector2(870, 23)
## The entry the walk is part of: into the kitchen by the back door.
const ENTERING := "door_840_190>kitchen"
## How long (frames) the avoid maps the routes are on may take to bake.
const BAKE_FRAMES := 600


func describe() -> Dictionary:
	return {
		"name": "A held walk does not resume an avoid map that goes through the held room",
		"description": "A held member standing in the back door's view with no way north round it "
			+ "does not walk through the kitchen: it takes the plain way along the lane (D38).",
		"tags": ["ai", "entry", "leadership", "stack", "movement", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)


func run(t: TestContext) -> void:
	var views: RefCounted = (load(VIEWS_SCRIPT) as GDScript).new()
	views.set_house(t.world.openings, t.rooms)
	# The room its stack holds is passed through (D20).
	views.pass_clear = func(key: String) -> bool: return key == "kitchen"
	views.ordered_approach = true
	var world := t.world.get_world_2d()
	var far := await _route(t, views, FAR)
	var near := await _route(t, views, START)
	if not t.require(
			not far.is_empty() and not near.is_empty(),
			"premise: both ways were worked out once their maps baked",
	):
		return
	t.check(bool(far["doors"]), "premise: from far off the way is the avoid map's, round the house")
	t.check(
		(
			not bool(near["doors"])
			and not views.plain_enters(START, GOAL, world.navigation_map, "kitchen")
		),
		"asked afresh from the lane the way is the plain one and keeps out of the kitchen",
	)
	t.check(
		views.plain_enters(START, GOAL, far["map"], "kitchen"),
		"the avoid map given from far off routes the walk from the lane through the kitchen",
	)


## The held route to `GOAL` from `from` once its avoid maps have baked; {} when they never did.
func _route(t: TestContext, views: RefCounted, from: Vector2) -> Dictionary:
	for i in BAKE_FRAMES:
		var way: Dictionary = views.walk_route(from, GOAL, t.world.get_world_2d(), ENTERING, true)
		if not bool(way["pending"]):
			return way
		await t.frames(1)
	return {}
