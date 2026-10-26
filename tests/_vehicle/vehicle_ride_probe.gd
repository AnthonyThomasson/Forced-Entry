extends RefCounted
## Moving things for the vehicle tests (not a test): placing a character or a parked vehicle, the
## ride (boarding by a door, getting out) and driving to a speed. `const VehicleRide :=
## preload("res://tests/_vehicle/vehicle_ride_probe.gd")`, beside `vehicle_probe.gd` (`Probe`) and
## `vehicle_frame_probe.gd` (`VehicleFrame`: where a door's user stands). The character is a puppet:
## it presses E (`use_vehicle()`) and drives (`drive(throttle, steer, handbrake)`).

const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")


## Put a character at `point` (standing still) and let a couple of frames pass.
static func place(t: TestContext, id: StringName, point: Vector2) -> void:
	var p := t.puppet(id)
	if p != null:
		p.stop()
	t.actor(id).global_position = point
	await t.frames(2)


## Move a parked vehicle to `pos`, turned to `rot`: frozen a frame, moved, then let go (a free rigid
## body moved directly is put back by the physics step).
static func move_vehicle(t: TestContext, v: Node2D, pos: Vector2, rot: float) -> void:
	v.set("freeze", true)
	await t.frames(1)
	v.global_position = pos
	v.global_rotation = rot
	await t.frames(1)
	v.set("freeze", false)
	await t.frames(2)


## Press E for puppet `id` and wait until it is seated (true) or `timeout` passes.
static func _board(t: TestContext, id: StringName, timeout := 6.0) -> bool:
	var c := t.actor(id)
	t.puppet(id).use_vehicle()
	return await t.until(func(): return c.use.is_in_vehicle(), timeout)


## Press E for seated puppet `id` and wait until it is out (its `use.vehicle()` null) or `timeout`
## passes.
static func exit(t: TestContext, id: StringName, timeout := 8.0) -> bool:
	var c := t.actor(id)
	t.puppet(id).use_vehicle()
	return await t.until(func(): return c.use.vehicle() == null, timeout)


## Walk puppet `id` to door `door_id`'s stand point, press E and wait until seated. False when it
## never sits.
static func board_by(
	t: TestContext,
	id: StringName,
	v: Node2D,
	door_id: StringName,
	timeout := 6.0,
) -> bool:
	await place(t, id, VehicleFrame.stand_point(v, door_id))
	return await _board(t, id, timeout)


## Hold full throttle (puppet `id`) until `v` reaches `target` px/s; then let go. Whether it got
## there.
static func reach_speed(
	t: TestContext,
	id: StringName,
	v: Node,
	target: float,
	timeout := 6.0,
) -> bool:
	var p := t.puppet(id)
	p.drive(1.0, 0.0, false)
	var ok := await t.until(func(): return v.speed() >= target, timeout)
	p.drive(0.0, 0.0, false)
	return ok


## Puppet `id` drives `v` as `plan` says: for its `duration` s holding its `steer` (and
## `handbrake`), the throttle on below its `target` px/s and off above it, calling `sample` each
## frame.
static func hold_speed(
	t: TestContext,
	id: StringName,
	v: Node,
	plan: Hold,
	sample := Callable(),
) -> void:
	var p := t.puppet(id)
	var deadline := t.time + plan.duration
	while t.time < deadline:
		p.drive(1.0 if v.speed() < plan.target else 0.0, plan.steer, plan.handbrake)
		await t.frames(1)
		if sample.is_valid():
			sample.call()
	p.drive(0.0, 0.0, false)


## A `Hold` near `target` px/s for `duration` s, holding `steer`, the handbrake off.
static func hold(target: float, steer: float, duration: float) -> Hold:
	var out := Hold.new()
	out.target = target
	out.steer = steer
	out.duration = duration
	return out


## How `hold_speed` drives: the speed it keeps near, its steer and handbrake, and for how long.
class Hold:
	## The speed it keeps near, px/s: the throttle on below it, off above it.
	var target: float = 0.0
	## The steer held, -1..1.
	var steer: float = 0.0
	## Whether the handbrake is held.
	var handbrake: bool = false
	## How long it drives, s.
	var duration: float = 0.0
