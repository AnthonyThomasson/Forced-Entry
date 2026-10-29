extends GameTest
## The ambush post shielded from the bang, against a real stack (LD15, D17, the defenders' ambush
## rule #128, rule 10): an ambusher at a post the stack's stun does not reach is not blinded when
## the stack bangs the room, and fires first, at the first of them to come in.
##
## The room of `ambush_post_shielded_from_bang` (600 x 400 over a hall, the doorway between at
## (100, 400), a wardrobe north of the door's wall east of the doorway). Two invaders, each carrying
## a stun, stand in the hall's west end by the doorway: a short route into a room they have not
## searched. A defender a little way into the room is ordered at once, by its squad's leader (a
## household puppet out in the street, out of the invaders' sight), to ambush the doorway from the
## room; its walk to its post is heard from the hall (footsteps heard there: a suspect room, so the
## stack's entry is a bang one, E17). Nobody is scripted: real Von at every level, the rest of the
## AI on.
##
## Required first (set-up findings otherwise): both invaders claim the doorway, the defender radios
## `in_position` before the point goes in, and a stun bursts in the room. Then: the defender is not
## blinded by it, and fires before any invader does.

const Order := preload("res://tests/_ai/order_probe.gd")
const OrderBrain := preload("res://tests/_ai/order_brain_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const ROOM := Rect2(0, 0, 600, 400)
const HALL := Rect2(0, 400, 600, 110)
const DOOR_ID := "door_100_400"
const IDS := [&"a", &"b"]


func describe() -> Dictionary:
	return {
		"name": "A shielded ambusher is not blinded by a real stack's stun entry and fires first",
		"description": "A defender ambushing a doorway from a post the stack's stun does not reach "
			+ "is posted before a real two-invader stun entry; the bang does not blind it and it "
			+ "fires first (LD15, D17, #128).",
		"tags": ["ai", "combat", "entry", "grenade", "leadership", "order", "ambush", "von"],
		"requires_von": true,
		"timeout": 100.0,
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
	s.actor(&"a", &"invader", Vector2(180, 440))
	s.actor(&"b", &"invader", Vector2(150, 460))
	s.actor(&"d", &"defender", Vector2(250, 250))
	s.actor(&"lead", &"puppet", Vector2(900, -300), { "faction": &"household" })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	var invaders: Array = IDS.map(func(id): return t.actor(id))
	for c in invaders:
		Probe.arm(c, 1, 0)
	var order := Order.issue(
		t.world.squad(&"household"),
		{ "kind": Order.AMBUSH, "to": [d], "opening": DOOR_ID, "room": "living_room" },
	)
	if not t.require(not order.is_empty(), "the squad posts the ambush order (%s)" % [order]):
		return
	var d_shot := func(): return t.happened(&"shot", func(e): return e.get("attacker") == d)
	var over := func(): return (
		d_shot.call() or not invaders.all(func(n): return is_instance_valid(n) and n.health > 0.0)
	)
	await t.until(over, 85.0)
	var acts := ", ".join((IDS + [&"d"]).map(
		func(id): return "%s %s" % [id, OrderBrain.brain(t, id).current_act()],
	))
	if not _set_up(t, d, acts):
		return
	var burst: Dictionary = _bangs(t)[0]
	var blinded := t.events_of(&"stun", func(e): return (
		e.get("character") == d and float(e.get("blind", 0.0)) > 0.0
	))
	t.check(
		blinded.is_empty(),
		"the stun bursting at %s does not blind the ambusher at its post (blinded %s)"
			% [(burst["position"] as Vector2).round(), blinded.map(func(e): return e.get("blind"))],
	)
	if not t.check(d_shot.call(), "the ambusher fires (%s)" % acts):
		return
	var d_first := float(Probe.raw(t, &"shot", func(e): return e.get("attacker") == d)[0]["time"])
	var theirs := Probe.raw(t, &"shot", func(e): return invaders.has(e.get("attacker")))
	t.check(
		theirs.is_empty() or float(theirs[0]["time"]) > d_first,
		"it fires first (its first shot %.2f s, the stack's %s)"
			% [d_first, "none" if theirs.is_empty() else "%.2f s" % float(theirs[0]["time"])],
	)


## The set-up, required: both invaders claimed the doorway, the defender was posted before the point
## went in, and a stun burst in the room.
func _set_up(t: TestContext, d: Node, acts: String) -> bool:
	if not t.require(
			IDS.all(func(id): return Entry.first_call_time(t, "claim", id, DOOR_ID) < INF),
			"both invaders chose the doorway into the room (claims there; %s)" % acts,
	):
		return false
	var going_at: float = IDS.map(
		func(id): return Entry.first_call_time(t, "going_in", id, DOOR_ID),
	).min()
	var posted := Order.first_time(t, &"callout", func(e): return (
		e.get("speaker") == d and String(e.get("order_step", "")) == "in_position"
	))
	if not t.require(
			posted < going_at,
			"the defender was posted before the point went in (posted %.2f s, going in %.2f s)"
				% [posted, going_at],
	):
		return false
	return t.require(not _bangs(t).is_empty(), "the stack banged the room (a stun burst in it)")


## The stun bursts in the room.
func _bangs(t: TestContext) -> Array:
	return t.events_of(&"explosion", func(e): return (
		StringName(e.get("kind", &"")) == &"stun" and ROOM.has_point(e.get("position", Vector2.INF))
	))
