extends GameTest
## V3 (ticket #54): boarding is one fluid movement, never a jump. Sampled every frame from the E
## press until the door has shut behind the seated character: the character's position never steps
## further in a frame than its own walk does, its facing turns smoothly (toward the door, then
## forward), the door eases open before the character folds in and eases shut after, the fold eases
## from standing to seated, and the seated character ends drawn over the chassis and under the roof.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
## The most the facing may turn in one frame (rad): 15 rad/s, a half turn in no less than 0.2 s.
const MAX_TURN_PER_FRAME := 0.25
## The most the fold may change in one frame: a 0.5 s eased fold peaks near 0.05.
const MAX_FOLD_PER_FRAME := 0.1
## The most a door's open amount may change in one frame: a 0.35 s eased swing peaks near 0.08.
const MAX_DOOR_PER_FRAME := 0.15
## A measured ease (the door from 5 % to 90 % open, the fold from 10 % to 90 %) takes between these
## shares of the spec's full time (`Probe.DOOR_OPEN_TIME`, `Probe.FOLD_TIME`).
const EASE_SHARE_MIN := 0.4
const EASE_SHARE_MAX := 2.0


func describe() -> Dictionary:
	return {
		"name": "The boarding animation is continuous",
		"description": "Every frame of a boarding: per-frame steps under a walking step, a smooth "
			+ "turn to the door and then forward, the door easing open before the fold and shut "
			+ "after it, an eased fold, and the seated character between the Chassis and Roof "
			+ "layers.",
		"tags": ["vehicle", "car", "board", "animation", "door"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80))


func run(t: TestContext) -> void:
	if not _premises(t):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	var handle: Vector2 = Probe.door(car, &"front_left")["handle"]
	if not await _start_in_reach(t, car):
		return
	var got := await _sample_boarding(t, car, me)
	if not t.require(got.seated_at >= 0, "the character gets in"):
		return
	_check_steps(t, me, got)
	_check_facing(t, car, handle, got)
	_check_door(t, got)
	_check_fold(t, got)
	_check_seated(t, car, me)


## The car and the character have the reads the test samples, the front-left handle and the
## Chassis and Roof draw layers (false: ends the test).
func _premises(t: TestContext) -> bool:
	if not Probe.ready(t, &"car", [&"me"]):
		return false
	var car := t.vehicle(&"car") as Node2D
	if not Probe.has_reads(
		t,
		t.actor(&"me").movement,
		[&"posture_folded"],
		"character me's movement",
	):
		return false
	if not t.require(
			Probe.door(car, &"front_left").has("handle"),
			"the car reports its front-left handle",
	):
		return false
	return t.require(
		Probe.layer(car, "Chassis") != null and Probe.layer(car, "Roof") != null,
		"the car has its Chassis and Roof draw layers",
	)


## In reach of the front-left handle but not at it (ahead of it and out from the side), facing
## away from the car, so the boarding has a walk and a turn to make (false: ends the test).
func _start_in_reach(t: TestContext, car: Node2D) -> bool:
	var d := Probe.door(car, &"front_left")
	var handle: Vector2 = d["handle"]
	var start := handle + Probe.outward(car, d) * 35.0 + Probe.forward(car) * 25.0
	if not t.require(
			start.distance_to(handle) < Probe.DOOR_REACH,
			"the start is in reach of the front-left handle",
	):
		return false
	await Probe.place(t, &"me", start)
	var puppet := t.puppet(&"me")
	puppet.aim_at(start + (start - car.global_position))
	await t.seconds(0.4)
	puppet.aim_at(null)
	return true


## Every frame from the press until the door is shut behind the seated character (or 6 s).
func _sample_boarding(t: TestContext, car: Node2D, me: Node2D) -> Samples:
	var got := Samples.new()
	t.puppet(&"me").use_vehicle()
	var deadline := t.time + 6.0
	while t.time < deadline:
		await t.frames(1)
		got.pos.append(me.global_position)
		got.face.append(me.facing)
		got.fold.append(float(me.movement.posture_folded()))
		got.door.append(Probe.open_of(car, &"front_left"))
		if got.seated_at < 0 and me.use.is_in_vehicle():
			got.seated_at = got.pos.size() - 1
		if got.seated_at >= 0 and got.door[-1] < 0.02 and got.pos.size() > got.seated_at + 5:
			break
	return got


## Position: no frame steps further than the character's own walk does in a frame.
func _check_steps(t: TestContext, me: Node2D, got: Samples) -> void:
	var walk_step: float = me.movement.speed / Engine.physics_ticks_per_second * 1.2
	var worst_step := 0.0
	for i in range(1, got.pos.size()):
		worst_step = maxf(worst_step, got.pos[i].distance_to(got.pos[i - 1]))
	t.trace("step", worst_step)
	t.check(
		worst_step <= walk_step,
		"no frame moves the character further than a walking step (worst %.2f px, a step %.2f px)"
			% [worst_step, walk_step],
	)


## Facing: smooth, toward the door (its `handle`) at some point before the fold, forward at the
## end.
func _check_facing(t: TestContext, car: Node2D, handle: Vector2, got: Samples) -> void:
	var face := got.face
	var worst_turn := 0.0
	for i in range(1, face.size()):
		worst_turn = maxf(worst_turn, absf(face[i - 1].angle_to(face[i])))
	t.check(
		worst_turn <= MAX_TURN_PER_FRAME,
		"the facing turns smoothly (worst %.3f rad in a frame)" % worst_turn,
	)
	var fold_starts := _first(got.fold, func(x): return x > 0.1)
	var faced_door := false
	for i in range(0, fold_starts if fold_starts >= 0 else face.size()):
		var to_door := handle - got.pos[i]
		if to_door.length() > 1.0 and face[i].dot(to_door.normalized()) > 0.7:
			faced_door = true
	t.check(faced_door, "it turns to face the door before folding in")
	t.check(
		face[-1].dot(Probe.forward(car)) > 0.9,
		"it ends facing forward (dot %.2f)" % face[-1].dot(Probe.forward(car)),
	)


## The door: eases open, is open before the fold starts, eases shut after the fold is done.
func _check_door(t: TestContext, got: Samples) -> void:
	var door := got.door
	var peak: float = door.max()
	t.check(peak >= 0.9, "the door opens (most %.2f)" % peak)
	t.check(door[-1] <= 0.05, "the door is shut at the end (%.2f)" % door[-1])
	var worst_door := _worst_change(door)
	t.check(
		worst_door <= MAX_DOOR_PER_FRAME,
		"the door eases, never snaps (worst %.3f in a frame)" % worst_door,
	)
	var opening := _first(door, func(x): return x > 0.05)
	var open := _first(door, func(x): return x >= 0.9)
	if opening >= 0 and open >= 0:
		var took := float(open - opening) / Engine.physics_ticks_per_second
		t.check(
			_about(took, Probe.DOOR_OPEN_TIME),
			"the door takes about %.2f s to open (%.2f s)" % [Probe.DOOR_OPEN_TIME, took],
		)
	var fold_starts := _first(got.fold, func(x): return x > 0.1)
	var door_open_by := _first(door, func(x): return x >= 0.8)
	t.check(
		door_open_by >= 0 and fold_starts >= 0 and door_open_by <= fold_starts,
		"the door is open before the character folds in (open frame %d, fold frame %d)"
			% [door_open_by, fold_starts],
	)
	var peak_at := door.find(peak)
	var closing := -1
	for i in range(peak_at, door.size()):
		if door[i] < 0.8:
			closing = i
			break
	t.check(
		closing >= 0 and got.fold[closing] >= 0.8,
		"the door shuts only once the character is folded in (fold %.2f as it closes)"
			% (got.fold[closing] if closing >= 0 else -1.0),
	)


## The fold: from standing to seated, eased.
func _check_fold(t: TestContext, got: Samples) -> void:
	var fold := got.fold
	t.check(fold[0] < 0.1, "the character starts standing (fold %.2f)" % fold[0])
	t.check(
		fold[got.seated_at] >= 0.9,
		"it is folded into the seat once seated (fold %.2f)" % fold[got.seated_at],
	)
	var worst_fold := _worst_change(fold)
	t.check(worst_fold <= MAX_FOLD_PER_FRAME, "the fold eases (worst %.3f in a frame)" % worst_fold)
	var fold_starts := _first(fold, func(x): return x > 0.1)
	var folded := _first(fold, func(x): return x >= 0.9)
	if fold_starts >= 0 and folded >= 0:
		var fold_time := float(folded - fold_starts) / Engine.physics_ticks_per_second
		t.check(
			_about(fold_time, Probe.FOLD_TIME),
			"the fold takes about %.2f s (%.2f s)" % [Probe.FOLD_TIME, fold_time],
		)


## Seated: inside the body, over the chassis and under the roof.
func _check_seated(t: TestContext, car: Node2D, me: Node2D) -> void:
	var reach_in := car.global_position.distance_to(Probe.edge(car, -Probe.forward(car)))
	t.check(
		me.global_position.distance_to(car.global_position) < reach_in,
		"the character ends inside the car's body",
	)
	t.check(
		Probe.draws_above(me, Probe.layer(car, "Chassis")),
		"the seated character is drawn over the chassis",
	)
	t.check(Probe.draws_above(Probe.layer(car, "Roof"), me), "and under the roof")


## Whether a measured ease of `took` s fits a full time of `full` s.
func _about(took: float, full: float) -> bool:
	return took >= full * EASE_SHARE_MIN and took <= full * EASE_SHARE_MAX


## The first index of `values` where `test` holds, or -1.
func _first(values: Array, test: Callable) -> int:
	for i in values.size():
		if test.call(values[i]):
			return i
	return -1


## The largest change in `values` from one frame to the next.
func _worst_change(values: Array[float]) -> float:
	var worst := 0.0
	for i in range(1, values.size()):
		worst = maxf(worst, absf(values[i] - values[i - 1]))
	return worst


## The boarding sampled every frame: the character's position, facing and fold, the front-left
## door's open amount, and the frame it was first seated.
class Samples:
	## The character's position each frame.
	var pos: Array[Vector2] = []
	## Its facing each frame.
	var face: Array[Vector2] = []
	## Its fold each frame, 0 standing to 1 seated.
	var fold: Array[float] = []
	## The front-left door's open amount each frame.
	var door: Array[float] = []
	## The first frame it was in the vehicle, or -1.
	var seated_at: int = -1
