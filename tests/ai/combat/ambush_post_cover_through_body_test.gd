extends GameTest
## A body never takes an ambush post's cover (`docs/leadership.md` LD15, D17, #128): every line of
## the ranking looks through the characters' bodies, so a bystander standing between a post and the
## low furniture on its line to the threshold leaves the post its low-cover rank.
##
## A room 600 x 160 over a hall along its south side, a doorway between them (60 px, centred at
## (100, 160)) and the front door at the hall's west end. The posts hidden from every slot and pie
## step outside lie east of the doorway, 40, 70 and 100 px back from its wall; the room is shallow
## enough that an entry's grenade comes down at two spots only (the bang's landings, G18: at least
## 120 px from the door and 30 inside the walls), each reaching every one of them alike, and none is
## in a funnel, so among them low cover on the line to the threshold ranks first, then the depth
## nearest 110 px. A shoe rack (20 tall: seen over, and no shield for a crouched body from a burst)
## stands on the line of the post 70 px back only, and a household bystander stands on that line
## between the post and the rack. Were the bystander to take the post's cover, the post 100 px back
## would win on its depth.
##
## A defender in the room is ordered (by its squad's leader, a household puppet in the hall, by the
## doorway's id) to ambush the doorway from the room, its ranking the one every NPC on the map
## shares. Its post (the ORDER leaf's `spot`) has the rack as the first thing on its line to the
## threshold, bodies looked through (the test's own ray, as D17 words the rank), though the
## bystander stands on that line (a premise: the line, bodies not looked through, meets the
## bystander first). With the ranking's bodies left out of its lines, the defender takes the post
## 100 px back instead and the check fails.
## Scripted Von (the order is taken without asking); nobody fights.

const Order := preload("res://tests/_ai/order_probe.gd")
const OrderBrain := preload("res://tests/_ai/order_brain_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const ROOM := Rect2(0, 0, 600, 160)
const HALL := Rect2(0, 160, 600, 110)
const DOOR := Vector2(100, 160)
const DOOR_ID := "door_100_160"
const DOOR_WIDTH := 60.0
const FRONT_DOOR := Vector2(0, 215)
const RACK_AT := Vector2(300, 108)
const BYSTANDER_AT := Vector2(360, 96)
## Where a post's line to the threshold ends: 8 px into the room from the doorway's centre (D2's
## sight line to a doorway).
const THRESHOLD := Vector2(100, 152)


func describe() -> Dictionary:
	return {
		"name": "An ambush post keeps its cover with a body in front of it",
		"description": "Ordered to ambush a doorway, a defender takes a post with a shoe rack "
			+ "on its line to the threshold, though a bystander stands between the post and the "
			+ "rack: a body never takes a post's cover (LD15, D17, #128).",
		"tags": ["ai", "combat", "leadership", "order", "ambush", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(
		[
			{ "key": "living_room", "type": "living_room", "rect": ROOM, "floor": "oak_planks" },
			{ "key": "hall", "type": "hallway", "rect": HALL, "floor": "oak_planks" },
		],
		[{ "pos": DOOR, "width": DOOR_WIDTH }, { "pos": FRONT_DOOR, "width": 80.0 }],
	)
	s.object(&"rack", "shoe_rack", RACK_AT)
	s.von_script([])
	s.actor(&"a", &"defender", Vector2(520, 50))
	s.actor(&"by", &"puppet", BYSTANDER_AT, { "faction": &"household" })
	s.actor(&"lead", &"puppet", Vector2(400, 220), { "faction": &"household" })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	await t.seconds(0.5)
	var order := Order.issue(
		t.world.squad(&"household"),
		{ "kind": Order.AMBUSH, "to": [a], "opening": DOOR_ID, "room": "living_room" },
	)
	if not t.require(not order.is_empty(), "the squad posts the ambush order (%s)" % [order]):
		return
	var brain := OrderBrain.brain(t, &"a")
	if not t.require(
			await t.until(func(): return OrderBrain.primitive(brain) == "ambush", 5.0),
			"the defender takes the ambush (primitive %s)" % OrderBrain.primitive(brain),
	):
		return
	# (The debug read gives a point as [x, y].)
	var at: Variant = OrderBrain.params(brain).get("spot")
	if not t.require(
			at is Array and (at as Array).size() == 2,
			"its leaf names its post (%s)" % [OrderBrain.params(brain)],
	):
		return
	var post := Vector2(at[0], at[1])
	var through := _first_hit(t, post, GrenadeAi.character_rids(t))
	t.check(
		through == t.object(&"rack"),
		"the post %s has the shoe rack on its line to the threshold, bodies looked through "
			% [post.round()] + "(met %s)" % [_name(through)],
	)
	var plain := _first_hit(t, post, [])
	t.require(
		plain == t.actor(&"by"),
		"premise: the bystander is the first thing on the post %s's line to the threshold, "
			% [post.round()] + "bodies not looked through (met %s)" % [_name(plain)],
	)


## The first solid thing on the line from `post` to the threshold, the bodies of `exclude` passed
## through; null for none.
func _first_hit(t: TestContext, post: Vector2, exclude: Array) -> Object:
	var query := PhysicsRayQueryParameters2D.create(post, THRESHOLD, PhysicsLayers.SOLID)
	query.exclude = exclude
	return t.world.get_world_2d().direct_space_state.intersect_ray(query).get("collider")


## A name for what a line met.
func _name(o: Object) -> String:
	return "nothing" if o == null else String((o as Node).name)
