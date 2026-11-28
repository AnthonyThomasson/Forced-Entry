extends GameTest
## A frag dents a room's worth of furniture in one frame. A piece is a plan handle with no collider
## (#194): a dent is cut again for what is built from it, so each dented piece says it was
## `reshaped` (its mesh is built again) in a deferred call that the hits of one frame share, and its
## twin keeps the outline it was built with (a dent is a few px). This checks that after a frag and
## its fragments every dented piece was reshaped, once the hits of a frame are done, and that no
## piece holds a 2D shape.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const CENTRE := Vector2(500, 350)
const PIECES := [
	["sofa", Vector2(0, -110)], ["armchair", Vector2(-120, -70)], ["armchair", Vector2(120, -70)],
	["bookshelf", Vector2(-150, 60)], ["wardrobe", Vector2(150, 70)], ["desk", Vector2(0, 120)],
	["coffee_table", Vector2(-60, 40)], ["side_table", Vector2(70, 30)],
]

var _reshaped := {}


func describe() -> Dictionary:
	return {
		"name": "Furniture dented by a blast is reshaped, and holds no 2D shape",
		"description": "After a frag among eight pieces, every dented upright piece said it was "
			+ "reshaped (its mesh is built again from its dents) and none holds a collision shape.",
		"tags": ["deformation", "frag", "grenade", "plan-handle"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"physics.blood", false)
	s.switch(&"nav.rebake", false)
	for i in PIECES.size():
		s.object(StringName("piece%d" % i), PIECES[i][0], CENTRE + PIECES[i][1])
	s.actor(
		&"thrower",
		&"puppet",
		Vector2(120, 350),
		{ "max_health": 1_000_000.0, "movement:aim_point": CENTRE },
	)


func run(t: TestContext) -> void:
	for i in PIECES.size():
		var piece := t.object(StringName("piece%d" % i))
		piece.reshaped.connect(func() -> void: _reshaped[piece] = _reshaped.get(piece, 0) + 1)
	Probe.arm(t.actor(&"thrower"), 0, 1)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, CENTRE)
	if not t.require(
			await t.until(func() -> bool: return not Probe.booms(t).is_empty(), 6.0),
			"the frag went off",
	):
		return
	await t.seconds(1.0)  # the fragments land and every rebuild has run
	var dented := 0
	var upright := 0
	var missed: Array = []
	var shaped: Array = []
	for i in PIECES.size():
		var piece := t.object(StringName("piece%d" % i))
		if not piece.find_children("*", "CollisionShape2D", true, false).is_empty():
			shaped.append("piece%d" % i)
		if piece.hit_marks().is_empty():
			continue
		dented += 1
		if piece.is_tipped():
			continue  # a tipped piece is reshaped when it is upright again
		upright += 1
		if not _reshaped.has(piece):
			missed.append("piece%d" % i)
	t.check(
		dented >= 4,
		"the blast dented the furniture (%d of %d pieces)" % [dented, PIECES.size()],
	)
	t.check(upright >= 2, "pieces the blast left standing were dented (%d)" % upright)
	t.check(missed.is_empty(), "every dented upright piece was reshaped: %s were not" % [missed])
	t.check(shaped.is_empty(), "no piece holds a 2D shape: %s do" % [shaped])
