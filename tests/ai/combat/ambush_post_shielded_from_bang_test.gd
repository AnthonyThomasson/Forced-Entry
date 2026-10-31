extends GameTest
## The ambush post shielded from the bang (LD15, D17, the defenders' ambush rule #128, rule 10):
## among the hidden posts of an `ambush` order, the one fewest landings of an entry's grenade into
## the room by that doorway reach wins, a frag's burst counted first: an ambusher holding it is not
## caught by a frag thrown in first.
##
## The ambush tests' room (`ambush_maps.gd`): a room 600 x 400 (the "living room") over a hall
## along its south side, a doorway between them (80 px, centred at (100, 400)) and the front door at
## the hall's west end. A wardrobe (95 tall, above a crouched body) stands in the room north of the
## door's wall, east of the doorway. The hidden posts are tucked against the door's wall well along
## from the doorway (the candidate ring of LD15: 40 to 160 px back, 30 to 260 px past the jamb); the
## wardrobe stands between some of them and where a grenade comes down, and a post west of it is in
## the open.
##
## A defender in the room is ordered (by its squad's leader, a household puppet in the hall, by the
## doorway's id) to ambush the doorway from the room. Its post (the ORDER leaf's `spot`): unseen
## from every slot and pie step outside (the test's own copy of the entry geometry, as
## `ambush_door_post`), and shielded from every landing of a frag thrown in by the doorway: the
## test's own copy of the bang's landings (`docs/grenades.md` G18: `BANG_DEPTHS` 0.85 / 0.7 / 0.55
## of the room's depth from the doorway by `BANG_ACROSS` 0 / 0.2 / -0.2 of its width, at least 120
## px from the door and 30 inside the walls), each within the frag's blast radius of the post
## stopped by the blast's own cover rule (`Explosion.shields`, interface 3) for a crouched body.
## The frag only: furniture stops a stun's flash only within its `flash_cover_reach` (30 px) of the
## post, and the navmesh keeps every post 24 px clear of a piece's face, so a piece shields a post
## from a stun only on lines nearly along its face's normal; no post here has that on every
## landing's line (a wall would). A stun entry against a shielded ambusher is
## `ambush_survives_stun_entry` (real Von).
## Scripted Von (the order is taken without asking); nobody fights.

const Order := preload("res://tests/_ai/order_probe.gd")
const OrderBrain := preload("res://tests/_ai/order_brain_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const AmbushMap := preload("res://tests/_ai/ambush_maps.gd")
## The test's copy of the entry geometry (the defaults of the NPC's `tuning.entry_geometry`).
const SLOT_STANDOFF := 28.0
const SLOT_FIRST := 18.0
const SLOT_SPACING := 44.0
const SLOTS_A_SIDE := 6
const PIE_RADIUS := 100.0
const PIE_STEPS := 5
## The test's copy of the bang's landings (G18).
const DEPTHS := [0.85, 0.7, 0.55]
const ACROSS := [0.0, 0.2, -0.2]
const MIN_DEPTH := 120.0
const INSET := 30.0


func describe() -> Dictionary:
	return {
		"name": "An ambush post is shielded from a frag thrown in by the doorway",
		"description": "Ordered to ambush a doorway of a room with a wardrobe in it, a defender "
			+ "takes a hidden post that no landing of a frag thrown in by that doorway reaches, "
			+ "the wardrobe between (LD15, D17, #128).",
		"tags": ["ai", "combat", "leadership", "order", "ambush", "grenade", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	AmbushMap.room(s)
	s.von_script([])
	s.actor(&"a", &"defender", Vector2(200, 150))
	s.actor(&"lead", &"puppet", Vector2(400, 455), { "faction": &"household" })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	await t.seconds(0.5)
	var order := Order.issue(
		t.world.squad(&"household"),
		{ "kind": Order.AMBUSH, "to": [a], "opening": AmbushMap.DOOR_ID, "room": "living_room" },
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
	var seen_from := _observers().filter(func(o): return GrenadeAi.line_clear(t, o, post))
	t.check(
		seen_from.is_empty(),
		"the post %s is unseen from every slot and pie step outside (seen from %s)"
			% [post.round(), seen_from.map(func(o): return (o as Vector2).round())],
	)
	var reached := _frag_reaches(t, post)
	t.check(
		reached.is_empty(),
		"no landing of a frag thrown in by the doorway reaches the post %s crouched (from %s)"
			% [post.round(), reached],
	)


## The landings of a frag thrown in by the doorway (the test's copy) whose burst reaches `post`:
## within the frag's blast radius and not shielded from it, crouched, by the blast's own cover rule.
func _frag_reaches(t: TestContext, post: Vector2) -> Array:
	var space := t.world.get_world_2d().direct_space_state
	var radius := float(GrenadeConfig.row(&"frag")["blast_radius"])
	var cover := CoverRule.new()
	cover.height = float(CharacterPostureConfig.postures[&"crouch"]["coverage"])
	cover.exclude = GrenadeAi.character_rids(t)
	return _landings().filter(
		func(l): return (
			(l as Vector2).distance_to(post) <= radius
			and not Explosion.shields(space, l, post, cover)
		),
	)


## Where a grenade thrown in by the doorway comes down, the test's own copy of the bang's rule.
func _landings() -> Array:
	var door := AmbushMap.DOOR
	var room := AmbushMap.ROOM
	var along := AmbushMap.OUT.orthogonal()
	var depth := room.size.y  # the farthest corner, straight back from the door's wall
	var out: Array = []
	for d: float in DEPTHS:
		for k: float in ACROSS:
			var p: Vector2 = door - AmbushMap.OUT * depth * d + along * room.size.x * k
			if room.grow(-INSET).has_point(p) and p.distance_to(door) >= MIN_DEPTH:
				out.append(p)
	return out


## The slots and pie steps of an entry into the room by the doorway, the test's own copy: where the
## stack and the point stand.
func _observers() -> Array:
	var door := AmbushMap.DOOR
	var outward := AmbushMap.OUT
	var along := outward.orthogonal()
	var out: Array = []
	for side in [1, -1]:
		for k in SLOTS_A_SIDE:
			out.append(door + outward * SLOT_STANDOFF
					+ along * side * (AmbushMap.DOOR_WIDTH * 0.5 + SLOT_FIRST + k * SLOT_SPACING))
		for i in PIE_STEPS:
			var theta := deg_to_rad(lerpf(55.0, 25.0, float(i) / float(PIE_STEPS - 1)))
			out.append(door + outward * cos(theta) * PIE_RADIUS
					+ along * side * sin(theta) * PIE_RADIUS)
	return out
