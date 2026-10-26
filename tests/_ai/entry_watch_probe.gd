extends RefCounted
## Shared helpers for the tactical-entry tests (not a test itself):
## `const EntryWatch := preload("res://tests/_ai/entry_watch_probe.gd")`. The per-frame sampler of a
## run (`watch`), its reads over the samples, and the check that an actor went through a doorway by
## tactical entry (`check_entered`, E9). A doorway is an `entry_probe.gd` frame, and its geometry
## (`in_funnel`, `in_room`, `faces_through`) and the radio (`first_call_time`) are read there.

const Entry := preload("res://tests/_ai/entry_probe.gd")


## Sample the actors `ids` every physics frame for up to `duration` s (or until `stop` returns
## true): one `{ t, pos: { id: Vector2 }, facing: { id: Vector2 } }` per frame. Each actor's
## distance to the door is traced for the failure output.
static func watch(
	t: TestContext,
	ids: Array,
	door: Dictionary,
	duration: float,
	stop := Callable(),
) -> Array:
	var samples: Array = []
	var end := t.time + duration
	while t.time < end:
		var pos := {}
		var facing := {}
		for id in ids:
			var a := t.actor(id)
			if a == null:
				continue
			pos[id] = a.global_position
			facing[id] = a.facing
			t.trace("%s_to_door" % id, a.global_position.distance_to(door["pos"]))
		samples.append({ "t": t.time, "pos": pos, "facing": facing })
		if stop.is_valid() and stop.call():
			break
		await t.frames(1)
	return samples


## The positions of actor `id` in `samples`, in order.
static func path_of(samples: Array, id: StringName) -> Array:
	var out: Array = []
	for s in samples:
		if s["pos"].has(id):
			out.append(s["pos"][id])
	return out


## The longest run of time (s) actor `id` spent in the funnel of `door` moving slower than
## `still_speed` px/s.
static func longest_pause_in_funnel(
	samples: Array,
	id: StringName,
	door: Dictionary,
	still_speed := 20.0,
) -> float:
	var longest := 0.0
	var run := 0.0
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i - 1]
		var b: Dictionary = samples[i]
		if not a["pos"].has(id) or not b["pos"].has(id):
			continue
		var dt: float = b["t"] - a["t"]
		var p: Vector2 = b["pos"][id]
		var speed: float = (p - (a["pos"][id] as Vector2)).length() / maxf(dt, 0.0001)
		if Entry.in_funnel(door, p) and speed < still_speed:
			run += dt
			longest = maxf(longest, run)
		else:
			run = 0.0
	return longest


## Where actor `id` first stood still (slower than `still_speed` px/s for `still_time` s) inside the
## room behind `door`: the corner it entered to. `Vector2.INF` when it never did.
static func first_stop_in_room(
	samples: Array,
	id: StringName,
	door: Dictionary,
	still_time := 0.3,
	still_speed := 15.0,
) -> Vector2:
	var run := 0.0
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i - 1]
		var b: Dictionary = samples[i]
		if not a["pos"].has(id) or not b["pos"].has(id):
			continue
		var dt: float = b["t"] - a["t"]
		var p: Vector2 = b["pos"][id]
		var speed: float = (p - (a["pos"][id] as Vector2)).length() / maxf(dt, 0.0001)
		if not (Entry.in_room(door, p) and speed < still_speed):
			run = 0.0
			continue
		run += dt
		if run >= still_time:
			return p
	return Vector2.INF


## The position of actor `id` at the first sample at or after time `at`, or Vector2.INF.
static func pos_at(samples: Array, id: StringName, at: float) -> Vector2:
	for s in samples:
		if s["t"] >= at and s["pos"].has(id):
			return s["pos"][id]
	return Vector2.INF


## How many separate times actor `id` stepped into the funnel of `door` in `samples`.
static func funnel_entries(samples: Array, id: StringName, door: Dictionary) -> int:
	var count := 0
	var was_in := false
	for p in path_of(samples, id):
		var now_in := Entry.in_funnel(door, p)
		if now_in and not was_in:
			count += 1
		was_in = now_in
	return count


## The time of the first sample where actor `id` is in the funnel of `door`, or INF.
static func first_in_funnel(samples: Array, id: StringName, door: Dictionary) -> float:
	for s in samples:
		if s["pos"].has(id) and Entry.in_funnel(door, s["pos"][id]):
			return s["t"]
	return INF


## The time of the last sample where actor `id` is in the funnel of `door`, or -INF.
static func last_in_funnel(samples: Array, id: StringName, door: Dictionary) -> float:
	var last := -INF
	for s in samples:
		if s["pos"].has(id) and Entry.in_funnel(door, s["pos"][id]):
			last = s["t"]
	return last


## How long (s) actor `id` pointed its gun through `door` (see `faces_through`) in `samples`,
## optionally only while `where` (a Callable on its position) holds.
static func time_facing_through(
	samples: Array,
	id: StringName,
	door: Dictionary,
	where := Callable(),
) -> float:
	var total := 0.0
	for i in range(1, samples.size()):
		var sample: Dictionary = samples[i]
		if not sample["pos"].has(id):
			continue
		var p: Vector2 = sample["pos"][id]
		if where.is_valid() and not where.call(p):
			continue
		if Entry.faces_through(door, p, sample["facing"][id]):
			total += float(sample["t"]) - float(samples[i - 1]["t"])
	return total


## The share of `samples` (those with actor `id`) in which `holds` (a Callable on its position and
## facing) is true.
static func share_facing(samples: Array, id: StringName, holds: Callable) -> float:
	var seen := 0
	var held := 0
	for s in samples:
		if not s["pos"].has(id):
			continue
		seen += 1
		if holds.call(s["pos"][id], s["facing"][id]):
			held += 1
	return float(held) / float(seen) if seen > 0 else 0.0


## Check that actor `id` got through `door` by tactical entry (E9): it radioed `going_in` for it, no
## later than the first time it stood in the doorway's funnel, and it did not pause in the funnel.
static func check_entered(t: TestContext, samples: Array, id: StringName, door: Dictionary) -> void:
	var going := Entry.first_call_time(t, "going_in", id, door["id"])
	var funnel := first_in_funnel(samples, id, door)
	t.check(
		going < INF,
		"%s went through %s by entry (it never radioed going_in for it)" % [id, door["id"]],
	)
	if going < INF and funnel < INF:
		t.check(
			funnel >= going - 0.05,
			"%s was in the funnel of %s at %.2f s, before it radioed going_in at %.2f s"
				% [id, door["id"], funnel, going],
		)
	# Up to the moment it is through: a narrow room's corner can lie inside the funnel, and it holds
	# that corner.
	var through := Entry.first_call_time(t, "in", id, door["id"])
	var crossing := samples.filter(func(sample): return sample["t"] <= through)
	t.check(
		longest_pause_in_funnel(crossing, id, door) < 0.5,
		"%s did not pause in the funnel of %s" % [id, door["id"]],
	)
