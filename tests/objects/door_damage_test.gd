extends GameTest
## DR9: a door has its material's hit points and each kind of hit counts against them by the
## material's factor for it: rounds, punches, kicks and blasts. A hollow-core door (80 HP) takes a
## round, a punch at 1.0 and a kick at 1.5; a solid wood door (250 HP) a frag's blast at 1.2 and its
## fragments at 0.8; a steel door (1200 HP) takes a kick at
## 0.05. A glass-panel door's first round shatters its panes, and the frame stays. The factors are
## the spec's (`docs/doors.md` DR9), kept here; the damage each hit does is read off the world (the
## `hit` and `hit_landed` events).

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const JAMB := 20.0
const HOLLOW_HP := 80.0
const STEEL_HP := 1200.0
## The hollow door's factors by kind of hit, and the steel door's for a kick.
const ROUND := 1.0
const MELEE := 1.0
const KICK := 1.5
## The solid door's, which the frag's blast and fragments strike: it lasts them.
const SOLID_HP := 250.0
const SOLID_ROUND := 0.8
const BLAST := 1.2
const STEEL_KICK := 0.05
const BLAST_DOOR := Vector2(1600, 200)


func describe() -> Dictionary:
	return {
		"name": "Hits count against a door's HP by their factors",
		"description": "Rounds, a punch, a kick and a frag's blast lower a hollow door's HP each "
			+ "by its factor; a kick barely marks a steel door; a glass-panel door's first round "
			+ "shatters its panes and the frame stays.",
		"tags": ["door", "objects", "damage", "projectile", "grenade"],
		"timeout": 16.0,
	}


func _doorway(at: Vector2, material: String, style: String, id: String) -> Dictionary:
	return {
		"pos": at, "width": 52.0,
		"door": {
			"name": id, "material": material, "style": style,
			"hinge": at - Vector2(0, JAMB), "swing_into": Vector2.RIGHT,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 1000) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 1000) },
		{ "key": "west_b", "type": "living_room", "rect": Rect2(1200, 0, 400, 400) },
		{ "key": "east_b", "type": "bedroom", "rect": Rect2(1600, 0, 400, 400) },
	], [
		_doorway(Vector2(400, 100), "hollow", "flush", "rounds"),
		_doorway(Vector2(400, 250), "hollow", "flush", "kicked"),
		_doorway(Vector2(400, 400), "hollow", "flush", "punched"),
		_doorway(Vector2(400, 550), "glass", "panes", "panes"),
		_doorway(Vector2(400, 700), "steel", "riveted", "steel"),
		_doorway(BLAST_DOOR, "solid", "panelled", "blasted"),
	])
	s.switch(&"projectile.flyover", false)
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.von_down()
	s.actor(&"round_shooter", &"puppet", Vector2(300, 100), { "start_slot": 3 })
	s.actor(&"pane_shooter", &"puppet", Vector2(300, 550), { "start_slot": 3 })
	# the doors swing east, so these stand on the side the leaf swings toward: a kick from there
	# only damages the door
	s.actor(&"kicker", &"puppet", Vector2(425, 250))
	s.actor(&"puncher", &"puppet", Vector2(431, 400), { "start_slot": 2 })
	s.actor(&"steel_kicker", &"puppet", Vector2(425, 700))
	s.actor(&"thrower", &"puppet", Vector2(1980, 200), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	var panes = t.object(&"panes")
	var intact_art: PackedByteArray = panes.visuals.texture().get_image().get_data()
	t.check(not panes.look.broken, "the panes are whole at the start")
	Probe.arm(t.actor(&"thrower"), 0, 1)
	t.puppet(&"round_shooter").aim_at(Vector2(400, 100))
	t.puppet(&"pane_shooter").aim_at(Vector2(400, 550))
	t.puppet(&"kicker").aim_at(Vector2(300, 250))
	t.puppet(&"puncher").aim_at(Vector2(300, 400))
	t.puppet(&"steel_kicker").aim_at(Vector2(300, 700))
	await t.seconds(0.6)
	t.puppet(&"round_shooter").shoot()
	t.puppet(&"pane_shooter").shoot()
	t.puppet(&"kicker").kick()
	t.puppet(&"puncher").punch()
	t.puppet(&"steel_kicker").kick()
	await t.seconds(0.5)
	t.check(panes.look.broken, "the first round shatters the glass-panel door's panes")
	t.check(not panes.is_down(), "the frame stays: the door is still standing")
	t.check(
		panes.visuals.texture().get_image().get_data() != intact_art,
		"and it is drawn without its glass",
	)
	t.puppet(&"round_shooter").shoot()
	await t.seconds(0.5)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, BLAST_DOOR + Vector2(50, 0))
	if not t.require(await Probe.wait_boom(t, &"frag", 6.0), "the frag goes off"):
		return
	await t.seconds(0.6)
	var blasted = t.object(&"blasted")
	t.check(
		t.happened(
			&"hit",
			func(d: Dictionary) -> bool: return d["victim"] == blasted and d["outcome"] == &"blast",
		),
		"the frag's blast struck the door",
	)

	_expect_hp(t, &"rounds", HOLLOW_HP, { "round": ROUND }, "rounds")
	_expect_hp(t, &"kicked", HOLLOW_HP, { "melee": KICK }, "a kick")
	_expect_hp(t, &"punched", HOLLOW_HP, { "melee": MELEE }, "a punch")
	_expect_hp(t, &"steel", STEEL_HP, { "melee": STEEL_KICK }, "a kick on steel")
	_expect_hp(t, &"blasted", SOLID_HP, { "round": SOLID_ROUND, "blast": BLAST }, "a frag blast")


## The door `id` has lost what the hits on it were worth: the damage of each `hit` event on it
## times `factors.round` (a round, a fragment) or `factors.blast` (outcome `blast`), and of each
## `hit_landed` of an actor's melee on it (a hand code, not a shot's -1) times `factors.melee`. It
## must have lost something.
func _expect_hp(t: TestContext, id: StringName, full: float, factors: Dictionary,
		what: String) -> void:
	var door = t.object(id)
	var lost := 0.0
	for e in t.events_of(&"hit", func(d: Dictionary) -> bool: return d["victim"] == door):
		var kind := "blast" if e["outcome"] == &"blast" else "round"
		lost += float(e["damage"]) * float(factors.get(kind, 0.0))
	for e in t.events_of(
		&"hit_landed",
		func(d: Dictionary) -> bool: return d["body"] == door and d["hand"] >= 0,
	):
		lost += float(e["damage"]) * float(factors.get("melee", 0.0))
	t.check(lost > 0.0, "%s hurt the %s door at all" % [what, id])
	t.check(
		absf((full - door.damage.hp) - lost) < 0.05,
		"%s took %.2f off the %s door's HP (%.2f of %.0f left, expected %.2f lost)"
			% [what, full - door.damage.hp, id, door.damage.hp, full, lost],
	)
