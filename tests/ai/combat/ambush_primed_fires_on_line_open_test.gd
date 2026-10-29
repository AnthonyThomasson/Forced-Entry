extends GameTest
## The primed ambusher (LD15, D18): an ambusher on its post, holding its ambush, fires on the very
## physics frame an entrant's step opens a line between them. An entrant's controller acts before
## its own body moves that frame, so the earliest it can fire back is the next one: a same-frame
## tie goes to the ambusher.
##
## The room of `ambush_post_shielded_from_bang` (600 x 400 over a hall, the doorway between at
## (100, 400), a wardrobe north of the door's wall east of the doorway). A defender in the room is
## ordered (by its squad's leader, a household puppet in the street, by the doorway's id) to ambush
## the doorway from the room; once it radios `in_position`, an invader puppet walks along the hall
## and up through the doorway into the room. The ambusher is spawned before the puppet, so with no
## priority of its own it would act before the puppet's step each frame and see it a frame late.
## The test samples the puppet at the top of every physics frame: the first sample with a clear line
## between the two is the frame after the step that opened it, and by then the ambusher has fired.
## Scripted Von (the order is taken without asking). Premise: the puppet is unkillable and never
## shoots (the entrant whose step opens the line).

const Order := preload("res://tests/_ai/order_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const ROOM := Rect2(0, 0, 600, 400)
const HALL := Rect2(0, 400, 600, 110)
const DOOR_ID := "door_100_400"
## The puppet's walk: along the hall to below the doorway, then up through it into the room.
const WALK := [Vector2(100, 455), Vector2(100, 300)]


func describe() -> Dictionary:
	return {
		"name": "A posted ambusher fires on the frame an entrant's step opens the line",
		"description": "An ambusher holding its post fires on the physics frame an entrant's own "
			+ "step opens a line between them, before the entrant can (LD15, D18).",
		"tags": ["ai", "combat", "leadership", "order", "ambush", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(
		[
			{ "key": "living_room", "type": "living_room", "rect": ROOM, "floor": "oak_planks" },
			{ "key": "hall", "type": "hallway", "rect": HALL, "floor": "oak_planks" },
		],
		[{ "pos": Vector2(100, 400), "width": 80.0 }, { "pos": Vector2(0, 455), "width": 80.0 }],
	)
	s.object(&"wardrobe", "wardrobe", Vector2(360, 300))
	s.von_script([])
	s.actor(&"d", &"defender", Vector2(250, 250))
	s.actor(&"inv", &"puppet", Vector2(450, 455), { "faction": &"invader", "max_health": 1e6 })
	s.actor(&"lead", &"puppet", Vector2(900, -300), { "faction": &"household" })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var inv := t.actor(&"inv")
	await t.seconds(0.5)
	var order := Order.issue(
		t.world.squad(&"household"),
		{ "kind": Order.AMBUSH, "to": [d], "opening": DOOR_ID, "room": "living_room" },
	)
	if not t.require(not order.is_empty(), "the squad posts the ambush order (%s)" % [order]):
		return
	var posted := func(): return not Order.progress(t, "in_position", d).is_empty()
	if not t.require(await t.until(posted, 15.0), "the ambusher reaches its post (in_position)"):
		return
	var walker := t.puppet(&"inv")
	walker.walk_to(WALK[0])
	var leg := { "i": 0 }
	var d_shot := func(): return t.happened(&"shot", func(e): return e.get("attacker") == d)
	var open := func():
		if walker.has_arrived() and leg["i"] == 0:
			leg["i"] = 1
			walker.walk_to(WALK[1])
		return GrenadeAi.line_clear(t, d.global_position, inv.global_position)
	if not t.require(await t.until(open, 15.0), "the puppet's walk opens a line to the post"):
		return
	var at := [inv.global_position.round(), d.global_position.round()]
	var late := await _frames_until(t, d_shot)
	t.check(
		late == 0,
		"the ambusher has fired by the first frame the line is open (the puppet at %s, the post "
			% at[0] + "%s; it fired %s)" % [at[1], "never" if late < 0 else "%d frames on" % late],
	)


## How many physics frames from now until `fired` holds (0: it holds now), or -1 when it does not
## within a second.
func _frames_until(t: TestContext, fired: Callable) -> int:
	for n in 60:
		if fired.call():
			return n
		await t.frames(1)
	return -1
