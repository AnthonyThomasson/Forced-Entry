extends GameTest
## D18 / DR11 (#194 ajarfall, review 3, `docs/twins.md`): a felled leaf that lands on a character
## who cannot be bowled away (a low post holds them) rests on them, asleep within 4 s and moving
## them no further. When the character then walks off, dies or is moved, the leaf is not left
## hanging in the air asleep: it falls and lies flat, the doorway clear.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const Rest := preload("res://tests/_objects/rest_on_character_probe.gd")
const DOORWAY_X := 400.0
const KICK_IMPULSE := 4000.0


func describe() -> Dictionary:
	return {
		"name": "A door resting on a held character sleeps, and falls flat when they leave",
		"description": "Three hollow doors kicked down onto characters held by a post: each leaf "
			+ "rests on its character, asleep within 4 s, the character moved no further in the "
			+ "next 2 s. The characters walk off, die and are moved: each leaf lies flat.",
		"tags": ["door", "objects", "3d", "twins"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	var doorways: Array = []
	for i in Rest.LEAVES.size():
		var y := 100.0 + 200.0 * i
		doorways.append({
			"pos": Vector2(DOORWAY_X, y), "width": 52.0,
			"door": {
				"name": "leaf_%d" % i, "material": "hollow", "style": "flush",
				"hinge": Vector2(DOORWAY_X, y - 20.0), "swing_into": Vector2.RIGHT,
			},
		})
		Rest.hold(s, StringName("who_%d" % i), DOORWAY_X - 15.0, y)
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 600) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 600) },
	], doorways)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	for i in Rest.LEAVES.size():
		t.object(StringName("leaf_%d" % i)).take_blow(
			&"kick", 1000.0, Vector2.RIGHT * KICK_IMPULSE, 40.0
		)
	for i in Rest.LEAVES.size():
		if not await _rests(t, i):
			return
	await _stays_at_rest(t)
	for i in Rest.LEAVES.size():
		Rest.leave(t, StringName("who_%d" % i), Rest.LEAVES[i])
	await t.seconds(1.0)
	for i in Rest.LEAVES.size():
		await _falls(t, i)


## Leaf `i` is knocked down, comes to rest (asleep within `Rest.ASLEEP_WITHIN`) standing on its
## character, not lying flat: false when the premise fails.
func _rests(t: TestContext, i: int) -> bool:
	var leaf := t.object(StringName("leaf_%d" % i))
	var label := Rest.label("a door", Rest.LEAVES[i])
	if not t.require(leaf.is_down(), "premise: %s is knocked down" % label):
		return false
	var asleep: bool = await Probe.settle(t, leaf, Rest.ASLEEP_WITHIN)
	t.check(asleep, "%s: it rests, asleep within %.0f s" % [label, Rest.ASLEEP_WITHIN])
	var says := "premise: %s rests on its character, not lying flat (top %.0f, lean %.0f)"
	var rests := Probe.top(leaf) > DoorFallConfig.step_over
	return t.require(rests, says % [label, Probe.top(leaf), Probe.lean(leaf)])


## In the 2 s after, no leaf has moved its character and each is still asleep.
func _stays_at_rest(t: TestContext) -> void:
	var spots: Array = []
	for i in Rest.LEAVES.size():
		spots.append(t.actor(StringName("who_%d" % i)).global_position)
	await t.seconds(2.0)
	for i in Rest.LEAVES.size():
		var crept: float = t.actor(StringName("who_%d" % i)).global_position.distance_to(spots[i])
		t.check(
			crept <= Rest.NO_CREEP and Probe.asleep(t.object(StringName("leaf_%d" % i))),
			"leaf %d at rest pushes its character no further (%.1f px) and sleeps" % [i, crept],
		)


## Leaf `i`, its character gone, comes to rest lying flat, or leaning on the post that held the
## character (something real), never hanging in the air.
func _falls(t: TestContext, i: int) -> void:
	var leaf := t.object(StringName("leaf_%d" % i))
	var label := Rest.label("a door", Rest.LEAVES[i])
	t.check(await Probe.settle(t, leaf, Rest.FALLS_WITHIN), "%s: it comes to rest" % label)
	var post := t.object(StringName("post_who_%d" % i))
	var flat := Probe.top(leaf) <= DoorFallConfig.step_over
	var leans := Probe.lean(leaf) >= 20.0 and Rest.touches(leaf, post)
	t.check(
		flat or leans,
		"%s: it lies flat or leans on the post (top %.1f, lean %.0f)"
			% [label, Probe.top(leaf), Probe.lean(leaf)],
	)
