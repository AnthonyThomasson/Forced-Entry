extends GameTest
## G17 with G3: what an NPC judges a lob (`AgentThrow.lob_clear`, which the throw-spot search and
## the GRENADE offer ask) is what the throw then flies, because both are the one planner
## (`GrenadeArc`, in the twin space): a lob it calls clear lands a thrown grenade past the cover,
## near the aim, and one it calls blocked does not get through. Four lanes of a hall and a doorway
## to the next room, each thrown as the NPC judged it: over bare floor, over a desk (31 px), over a
## wardrobe (78 px), through the doorway, and at a point behind a wall with no door.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
## The thrower stands apart; each lane's grenade is thrown from its own start point.
const THROWER_AT := Vector2(40, 760)
const WALL_X := 700.0
## How far from its aim (px) a clear lob may end: the roll past it.
const NEAR := 110.0
## Each lane: where the hand is, the aim, and what stands in the way (the pieces are made in
## `configure`). `clear` is what the planner must say; `through` is the x a grenade that gets past
## the cover rests beyond.
const LANES := {
	"bare floor": {
		"from": Vector2(60, 650),
		"to": Vector2(380, 650),
		"clear": true,
		"past": 300.0,
	},
	"over a desk": {
		"from": Vector2(60, 250),
		"to": Vector2(400, 250),
		"clear": true,
		"past": 315.0,
	},
	"over a wardrobe": {
		"from": Vector2(60, 450),
		"to": Vector2(430, 450),
		"clear": true,
		"past": 300.0,
	},
	"through a doorway": {
		"from": Vector2(450, 150),
		"to": Vector2(850, 150),
		"clear": true,
		"past": WALL_X,
	},
	"behind a wall": {
		"from": Vector2(450, 350),
		"to": Vector2(850, 350),
		"clear": false,
		"past": WALL_X,
	},
}


func describe() -> Dictionary:
	return {
		"name": "The NPC's lob judgment is the flight the throw then flies",
		"description": "Over bare floor, a desk, a wardrobe and through a doorway the NPC calls "
			+ "the lob clear and a thrown stun lands past the cover near the aim; at a point "
			+ "behind a wall the NPC calls it blocked and the stun does not get through.",
		"tags": ["ai", "grenade", "throw", "lob", "3d"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, WALL_X, 800) },
		{ "key": "east", "type": "kitchen", "rect": Rect2(WALL_X, 0, 700, 800) },
	], [{ "pos": Vector2(WALL_X, 150), "width": 80.0 }])
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", Vector2(250, 250))
	# Close to the thrower: the highest arc (90 px) is over its 78 only near the start.
	s.object(&"wardrobe", "wardrobe", Vector2(160, 450))
	s.actor(&"thrower", &"puppet", THROWER_AT, { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var thrower := t.actor(&"thrower")
	await t.frames(3)
	var npc := AgentThrow.new()
	npc.bind(thrower)
	for lane: String in LANES:
		var spec: Dictionary = LANES[lane]
		var judged := npc.lob_clear(spec["from"], spec["to"], &"stun")
		t.check(judged == spec["clear"], "%s: the NPC calls it %s" % [lane, _word(judged)])
		var rest := await _throw(t, thrower, spec["from"], spec["to"])
		if rest == Vector2.INF:
			t.check(false, "%s: the grenade was thrown and came to rest" % lane)
			continue
		var got_past := rest.x > float(spec["past"]) and rest.distance_to(spec["to"]) < NEAR
		t.check(
			got_past == judged,
			"%s: and the thrown grenade %s (rest %s, %.0f px from the aim)"
				% [lane, "lands near the aim" if got_past else "does not", str(rest.round()),
					rest.distance_to(spec["to"])],
		)


## Throw a stun from `from` onto `to` as an NPC's would be thrown (standing release height) and
## return where it comes to rest; `Vector2.INF` when it never does.
func _throw(t: TestContext, thrower: Node, from: Vector2, to: Vector2) -> Vector2:
	var throw := GrenadeThrow.new()
	throw.kind = &"stun"
	throw.from = from
	throw.release = BodyHeights.release(BodyHeights.STAND)
	throw.to = to
	throw.thrower = thrower
	ThrownGrenade.spawn(throw, thrower.world_root())
	var flight := await Probe.track(t, 4.0)
	if flight.is_empty():
		return Vector2.INF
	var rests := Probe.raw(t, &"grenade", func(d): return d.get("stage") == &"rest")
	return flight.back()["at"] if not rests.is_empty() else Vector2.INF


func _word(clear: bool) -> String:
	return "clear" if clear else "blocked"
