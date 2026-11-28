extends GameTest
## #194 (`docs/twins.md`: a character that leaves wakes what rested on it): a
## bookshelf leaning on a character who cannot be bowled away (held by a low post) is not left
## hanging in the air asleep when the character walks off, dies or is moved: it falls and lies on
## its side.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const Rest := preload("res://tests/_objects/rest_on_character_probe.gd")
## The shelf's pose: leaning this many degrees, its foot at this x less its pivot.
const LEAN := 35.0
const FOOT := 380.0


func describe() -> Dictionary:
	return {
		"name": "A bookshelf leaning on a character falls when the character leaves",
		"description": "A bookshelf leans on a character held in place by a post. The character "
			+ "walks off, dies or is moved: the shelf does not stay asleep in the air, it comes "
			+ "to rest lying on its side.",
		"tags": ["furniture", "3d", "twins", "tipping"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 1000))
	for i in Rest.LEAVES.size():
		var y := 150.0 + 300.0 * i
		s.object(StringName("shelf_%d" % i), "bookshelf", Vector2(400, y))
		Rest.hold(s, StringName("who_%d" % i), 400.0, y)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	for i in Rest.LEAVES.size():
		var body := Probe.body(t.object(StringName("shelf_%d" % i)))
		body.global_transform = Transform3D(
			Basis(Vector3.BACK, deg_to_rad(-LEAN)),
			Vector3(FOOT, 12.0, 150.0 + 300.0 * i),
		)
	await t.seconds(3.0)
	for i in Rest.LEAVES.size():
		var shelf := t.object(StringName("shelf_%d" % i))
		var held := Probe.lean(shelf) > 25.0 and Probe.top(shelf) > 60.0
		var says := "premise: shelf %d rests leaning on its character (lean %.0f, top %.0f)"
		if not t.require(held, says % [i, Probe.lean(shelf), Probe.top(shelf)]):
			return
	for i in Rest.LEAVES.size():
		Rest.leave(t, StringName("who_%d" % i), Rest.LEAVES[i])
	await t.seconds(1.0)
	for i in Rest.LEAVES.size():
		var shelf := t.object(StringName("shelf_%d" % i))
		var label := Rest.label("a bookshelf", Rest.LEAVES[i])
		t.check(await Probe.settle(t, shelf, Rest.FALLS_WITHIN), "%s: it comes to rest" % label)
		t.check(
			Probe.top(shelf) <= Rest.FLAT,
			"%s: it lies down, not hanging (top %.0f, lean %.0f)"
				% [label, Probe.top(shelf), Probe.lean(shelf)],
		)
