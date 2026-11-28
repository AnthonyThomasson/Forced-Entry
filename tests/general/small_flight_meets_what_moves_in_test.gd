extends GameTest
## D12 (#194): a thing in flight that has looked a corridor clear still meets what moves into it. A
## grenade's flight (it strikes characters, vehicles and the world) is thrown across an empty room;
## after it has looked ahead a body of the twin space is put in its path a few frames on, as a
## character, a vehicle or a door leaf moves into one. The flight strikes it, as a flight that
## sweeps the space every frame does, and neither passes through.

const DELTA := 1.0 / 60.0
const FRAMES := 40
## The frame on which the blocker steps into the path, and how far ahead of the flight (px) its
## near face then stands.
const MOVES_IN := 2
const AHEAD := 14.0
## A blocker's size (plan x, plan y, height; px).
const BLOCK := Vector3(12.0, 80.0, 120.0)
const SAME := 0.001
## What moves: a character, a vehicle, and a door leaf or a free piece (in the world's layer).
const LAYERS := [PhysicsLayers.TWIN_CHARACTER, PhysicsLayers.TWIN_VEHICLE, PhysicsLayers.TWIN_WORLD]


func describe() -> Dictionary:
	return {
		"name": "A flight meets a body that moves into its looked-over corridor",
		"description": "A grenade's flight thrown across an empty room, a body put in its path "
			+ "frames after it looked ahead: it is struck by it and does not pass through, "
			+ "exactly as a flight that sweeps every frame.",
		"tags": ["physics", "3d", "flight", "character", "vehicle", "door"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var space := TwinSpace.space_of(t.world)
	var twins := TwinSpace.of_world(t.world)
	if not t.require(space != null and twins != null, "premise: the room has a twin space"):
		return
	for layer in LAYERS:
		var looking := _flight()
		var plain := _flight()
		plain.get(&"_probe").look = false
		var blocker := _blocker(twins, layer)
		var far := await _fly(t, space, blocker, [looking, plain])
		var named := " (layer %d)" % layer
		t.check(far["still_looked"], "premise: the corridor was found clear" + named)
		t.check(
			float(far["looking_x"]) < 300.0 + AHEAD + BLOCK.x,
			"the flight does not pass through the blocker (x %.1f, layer %d)" % [
				far["looking_x"],
				layer,
			],
		)
		t.check(
			absf(float(far["looking_x"]) - float(far["plain_x"])) < SAME,
			"it ends where the sweeping flight does (%.2f against %.2f)" % [
				far["looking_x"],
				far["plain_x"],
			],
		)
		blocker.queue_free()
		await t.frames(1)


## A flight like a grenade's: a lob across the empty room at the blocker's height.
func _flight() -> SmallFlight:
	var flight := SmallFlight.new(3.0)
	flight.mask = PhysicsLayers.TWIN_ALL
	flight.place(Vector2(300, 200), 30.0)
	flight.velocity = Vector2(240.0, 0.0)
	flight.rise = 100.0
	return flight


## A box body of the twin space on `layer`, parked far off the flight's path.
func _blocker(twins: TwinSpace, layer: int) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BLOCK.x, BLOCK.z, BLOCK.y) * RenderConfig.unit
	shape.shape = box
	body.add_child(shape)
	body.collision_layer = layer
	body.collision_mask = 0
	twins.add_child(body)
	body.global_position = PlanSpace.lift(Vector2(600, 40), BLOCK.z / 2.0)
	return body


## Fly both (`pair`: the one looking ahead, the plain one) for `FRAMES` frames, one a physics frame
## (the twin space takes a moved body on its next step), the blocker stepping into the path on
## frame `MOVES_IN`.
func _fly(t: TestContext, space: PhysicsDirectSpaceState3D, blocker: AnimatableBody3D,
		pair: Array) -> Dictionary:
	var looking: SmallFlight = pair[0]
	var plain: SmallFlight = pair[1]
	var looked := false
	for frame in FRAMES:
		if frame == MOVES_IN:
			var near := looking.at.x + AHEAD + BLOCK.x / 2.0
			blocker.global_position = PlanSpace.lift(Vector2(near, looking.at.y), BLOCK.z / 2.0)
		await t.frames(1)
		looking.step(space, DELTA)
		plain.step(space, DELTA)
		if frame == MOVES_IN - 1 and looking.get(&"_probe").frames > 0:
			looked = true
	return { "still_looked": looked, "looking_x": looking.at.x, "plain_x": plain.at.x }
