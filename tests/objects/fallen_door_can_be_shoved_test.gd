extends GameTest
## D18 (#194 doors3d): a door that lies on the floor is a free body, shovable as a light piece: a
## push through the pushable contract (`Knockback.push`) slides it, and a blast (`Explosion`, which
## finds a body by its footprint) slides it, and its 2D door follows it. A character's strike does
## not reach it: a fist or a shin swung over a leaf 6 px thick passes above it, as a foot steps
## over.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const DOORWAY := Vector2(400, 300)
const HINGE := Vector2(400, 280)
const SHOVE := 6000.0
## A blast's burst height (px): within the leaf's thickness, so it slides it.
const BLAST_HEIGHT := 3.0


func describe() -> Dictionary:
	return {
		"name": "A fallen door can be shoved like a light piece",
		"description": "A fallen hollow door pushed along the floor slides, and stops; the 2D door "
			+ "follows its 3D body.",
		"tags": ["door", "objects", "3d", "pushable", "knockback"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [{
		"pos": DOORWAY, "width": 52.0,
		"door": {
			"name": "felled", "material": "hollow", "style": "flush",
			"hinge": HINGE, "swing_into": Vector2.RIGHT,
		},
	}])
	s.von_down()


func run(t: TestContext) -> void:
	await t.frames(3)
	var door = t.object(&"felled")
	door.take_blow(&"kick", 1000.0, Vector2.RIGHT * 2200.0, 30.0)
	t.require(door.is_down(), "premise: the door is felled")
	t.require(await Probe.settle(t, door, 12.0), "premise: it lies at rest")
	var before: Vector2 = Probe.middle(door)
	Knockback.push(door, Vector2(0.0, SHOVE), Vector2.ZERO, -1.0)
	await t.seconds(0.4)
	t.check(not Probe.asleep(door), "the shove wakes it")
	t.check(await Probe.settle(t, door, 8.0), "and it comes to rest again")
	var slid: Vector2 = Probe.middle(door) - before
	t.check(slid.y > 5.0, "it slid south, the way it was pushed (%.1f px)" % slid.y)
	t.check(absf(slid.x) < slid.y, "and mostly that way (%.1f px across)" % slid.x)
	var lead := Probe.body(door)
	t.check(
		door.global_position.distance_to(PlanSpace.plan_of(lead.global_position)) < 0.5,
		"the 2D door follows it",
	)
	t.check(Probe.lean(door) > 70.0, "it still lies flat (%.0f degrees)" % Probe.lean(door))
	await _blasted(t, door)


## A second blast, through the real path (`Explosion`, which finds a body by its footprint), slides
## the flat door away from it.
func _blasted(t: TestContext, door: Node2D) -> void:
	var before: Vector2 = Probe.middle(door)
	var row := GrenadeConfig.row(&"frag").duplicate()
	row["fragments"] = 0
	Explosion.frag(door.global_position + Vector2(0.0, -30.0), t.world, null, row, BLAST_HEIGHT)
	await t.seconds(0.3)
	t.check(await Probe.settle(t, door, 8.0), "after a blast it comes to rest again")
	var slid: Vector2 = Probe.middle(door) - before
	t.check(slid.y > 3.0, "a blast north of it slides it south (%.1f px)" % slid.y)
	t.check(Probe.lean(door) > 70.0, "and it still lies flat (%.0f degrees)" % Probe.lean(door))
