extends GameTest
## DR2 (docs/doors.md, issue #21): which doorways of a generated house get a door. The front and
## exit doorways always have one; an interior doorway's chance comes from its more private room's
## type (bathroom and netrunner den: always; bedroom, office, ripperdoc: mostly; kitchen, living
## spaces, studio: rarely); a floorplan may force or forbid a door on one opening and names the
## doors its exterior and interior doors draw from (the flats steel at the street, the houses solid
## wood, glass panes for a patio exit or an office); and the roll is a stream of its own, so a
## seed's furniture layout is the same with `worldgen.doors` on and off. Read through
## `WorldGen.get_openings` and `get_doors` over every floorplan and several seeds. Two hallways
## never share a door: `door_rules_suite` pins that rule, since no floorplan joins two hallways.

const Houses := preload("res://tests/_worldgen/door_house_probe.gd")
## The spec's tiers (DR2): the types whose more private room puts the door always, mostly or rarely.
const ALWAYS := ["bathroom", "netrunner_den"]
const MOSTLY := ["bedroom", "home_office", "ripperdoc"]
const RARELY := ["kitchen", "kitchenette", "living_room", "kitchen_living", "studio"]
## "Mostly" is more than half and "rarely" less than half of the doorways.
const HALF := 0.5
## The materials a door of each kind draws from (the door sets, DR2).
const STEEL := ["steel"]
const SOLID := ["solid"]
const HOLLOW := ["hollow"]
const GLASS := ["glass"]
## Plans checked for the furniture layout being the same with doors on and off, and their seeds.
const LAYOUT_SEEDS := 4


func describe() -> Dictionary:
	return {
		"name": "Doors are placed by the floorplan's and the room types' rules",
		"description": "DR2: front and exit doorways always have a door, a bathroom and a "
			+ "netrunner den always, bedrooms, offices and ripperdocs mostly, kitchens, "
			+ "living spaces and studios rarely; a forced and a forbidden opening hold; each "
			+ "house's doors draw from its sets; a seed's furniture is the same with "
			+ "worldgen.doors off.",
		"tags": ["worldgen", "house", "doors", "door-placement"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	# A hand-laid pair of rooms, one doorway with a door and the south entrance without.
	s.layout(
		[
			{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 300, 300) },
			{ "key": "east", "type": "bedroom", "rect": Rect2(300, 0, 300, 300) },
		],
		[
			{
				"pos": Vector2(300, 150),
				"width": 52.0,
				"door": {
					"material": "hollow",
					"style": "flush",
					"hinge": Vector2(300, 130),
					"swing_into": Vector2.LEFT,
					"name": "Hall door",
				},
			},
			{ "pos": Vector2(150, 300), "width": 60.0 },
		],
	)
	s.set_static(WorldGenDoorConfig, &"enabled", true)


## The tier name of the more private room of `types`, or "" when a type is in none of the tiers.
func _tier(types: Array) -> String:
	var best := -1
	for type: String in types:
		if not Houses.PRIVACY.has(type):
			return ""
		best = maxi(best, Houses.PRIVACY[type])
	for type: String in types:
		if Houses.PRIVACY[type] == best:
			if ALWAYS.has(type):
				return "always"
			if MOSTLY.has(type):
				return "mostly"
			if RARELY.has(type):
				return "rarely"
	return ""


func run(t: TestContext) -> void:
	# tier -> [doorways with a door, doorways]
	var counts := { "mostly": [0, 0], "rarely": [0, 0] }
	for plan_key in HouseDefinitions.get_all():
		for house_seed in range(1, Houses.SEEDS + 1):
			var built := Houses.generated(t, plan_key, house_seed)
			_check_house(t, "%s seed %d" % [plan_key, house_seed], plan_key, built, counts)
			built.queue_free()
			await t.frames(1)
	_check_shares(t, counts)
	_check_layout_flags(t)
	await _check_same_furniture(t)


## Every doorway of one generated house.
func _check_house(t: TestContext, where: String, plan_key: String, built: Node2D,
		counts: Dictionary) -> void:
	var authored := Houses.plan_openings(plan_key)
	var rooms := WorldGen.get_rooms(built)
	for opening: Dictionary in WorldGen.get_openings(built):
		var label := Houses.label(opening)
		var entry: Variant = Houses.door_in(built, opening)
		t.check(opening.get("door", false) == (entry != null),
				"%s %s: the opening's door flag says %s" % [where, label, entry != null])
		var here := {
			"where": "%s %s" % [where, label], "plan": plan_key, "authored": authored[label],
			"tier": _tier(Houses.types_of(rooms, opening)),
		}
		_check_opening(t, here, opening, entry, counts)


## One doorway: its door, or the lack of one, by the kind of doorway and the plan's say. `here`:
## `{ where, plan, authored, tier }`.
func _check_opening(t: TestContext, here: Dictionary, opening: Dictionary, entry: Variant,
		counts: Dictionary) -> void:
	var has_door := entry != null
	var authored: Dictionary = here["authored"]
	var tier: String = here["tier"]
	if authored.has("door"):
		t.check(has_door == authored["door"],
				"%s: the plan %s a door here, the house %s one" % [here["where"],
					"forces" if authored["door"] else "forbids", "has" if has_door else "lacks"])
	elif opening["front"] or opening["exit"]:
		t.check(has_door, "%s: a front or exit doorway has a door" % here["where"])
	elif tier == "always":
		t.check(has_door, "%s: a bathroom or netrunner den doorway has a door" % here["where"])
	elif tier != "":
		counts[tier][1] += 1
		counts[tier][0] += 1 if has_door else 0
	if has_door:
		_check_set(t, here["where"], here["plan"], opening, entry)


## A hand-laid layout reports a doorway's `door` as the layout declared it.
func _check_layout_flags(t: TestContext) -> void:
	var openings := WorldGen.get_openings(t.world.house)
	t.check(openings.size() == 2, "the layout has its two doorways")
	for opening: Dictionary in openings:
		var declared: bool = opening["pos"] == Vector2(300, 150)
		t.check(opening["door"] == declared,
				"the layout's doorway at %s reports door %s" % [opening["pos"], declared])


## "Mostly" is more than half of the bedroom, office and ripperdoc doorways, but not all of them;
## "rarely" is some of the kitchen, living space and studio ones, but under half.
func _check_shares(t: TestContext, counts: Dictionary) -> void:
	var mostly: Array = counts["mostly"]
	t.check(float(mostly[0]) > HALF * mostly[1] and mostly[0] < mostly[1],
			"a bedroom, office or ripperdoc doorway mostly has a door: %d of %d"
				% [mostly[0], mostly[1]])
	var rarely: Array = counts["rarely"]
	t.check(float(rarely[0]) < HALF * rarely[1] and rarely[0] > 0,
			"a kitchen, living space or studio doorway rarely has a door: %d of %d"
				% [rarely[0], rarely[1]])


## The door's material is from the set its floorplan names for that kind of doorway.
func _check_set(t: TestContext, where: String, plan_key: String, opening: Dictionary,
		entry: Dictionary) -> void:
	var want := HOLLOW
	if opening["front"]:
		want = STEEL if Houses.FLATS.has(plan_key) else SOLID
	elif opening["exit"]:
		want = GLASS if plan_key == "open_plan_home" else SOLID
	elif plan_key == "office_loft" and (opening["rooms"] as Array).has("home_office"):
		want = GLASS
	t.check(want.has(entry["material"]),
			"%s: the door is %s, expected %s" % [where, entry["material"], want])
	t.check(entry["node"] is Node and (entry["node"] as Node).is_in_group(&"doors"),
			"%s: the door is a door node" % where)


## A seed's furniture, clutter and neon are where they are with the doors off.
func _check_same_furniture(t: TestContext) -> void:
	for plan_key in HouseDefinitions.get_all():
		for house_seed in range(1, LAYOUT_SEEDS + 1):
			var where := "%s seed %d" % [plan_key, house_seed]
			var with := Houses.generated(t, plan_key, house_seed)
			WorldGenDoorConfig.enabled = false
			var without := Houses.generated(t, plan_key, house_seed)
			WorldGenDoorConfig.enabled = true
			var furniture := Houses.furnishing(with)
			t.check(not WorldGen.get_doors(with).is_empty(), "%s: built with doors" % where)
			t.check(WorldGen.get_doors(without).is_empty(),
					"%s: no doors with worldgen.doors off" % where)
			t.check(not furniture.is_empty() and Houses.furnishing(without) == furniture,
					"%s: the same furniture with doors on and off" % where)
			with.queue_free()
			without.queue_free()
			await t.frames(1)
