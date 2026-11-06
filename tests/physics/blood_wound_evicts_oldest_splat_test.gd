extends GameTest
## A bleeding body keeps its newest `max_splats_per_body` splats and frees the oldest as each new
## one lands. The list is a FIFO with an advancing head, and it must hold what the plain list it
## replaced held: after every hit the same splats in the same order, the oldest past the cap queued
## for deletion, and a splat something else freed passed over only when it reaches the front. A
## plain array, moved the way the old list moved, is the reference.

const BloodSplat = preload("res://scenes/physics/blood/blood_splat.gd")
const CAP := 10
const HITS := 8


func describe() -> Dictionary:
	return {
		"name": "A body's blood list evicts its oldest splat",
		"description": "BloodWound keeps the same splats, in the same order and count, as a plain "
			+ "oldest-first list capped at max_splats_per_body, with a splat freed from outside.",
		"tags": ["blood", "splat", "cap"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"nav.rebake", false)
	s.set_static(BloodSplatConfig, &"max_splats_per_body", CAP)
	s.actor(&"victim", &"puppet", Vector2(300, 200), { "max_health": 1_000_000.0 })


func run(t: TestContext) -> void:
	await t.frames(2)
	var victim := t.actor(&"victim")
	var wound: BloodWound = victim.anatomy.wound
	var model: Array = []
	var seen: Array = []
	var differing: Array[int] = []
	var unqueued := 0
	var over_cap := 0
	for k in HITS:
		if k == 1:  # the list is under its cap; something else frees the oldest and a middle splat
			wound._splats.items()[0].free()
			wound._splats.items()[2].free()
		var thrown := _hit(t, victim, wound, k)
		seen.append_array(thrown)
		for splat in thrown:
			_push(model, splat)
		if _ids(wound._splats.items()) != _ids(model):
			differing.append(k)
		over_cap += 1 if wound._splats.size() > CAP else 0
		unqueued += _unqueued_evictions(seen, wound._splats.items())
		await t.frames(1)
	t.check(differing.is_empty(), "hits after which the list differs from the plain one %s"
		% str(differing))
	t.check(over_cap == 0, "the list never stood over its cap")
	t.check(unqueued == 0, "every splat pushed out of the list was queued for deletion (%d not)"
		% unqueued)
	t.check(wound._splats.size() == CAP, "the list ends at its cap (%d)" % wound._splats.size())


## One hit's spray: the splats `record` added to the world, in the order thrown.
func _hit(t: TestContext, victim: Node2D, wound: BloodWound, k: int) -> Array:
	var before := t.world.get_children()
	var hit := HitInfo.new()
	hit.normal = Vector2.from_angle(k * 0.9)
	hit.direction = -hit.normal
	hit.position = victim.global_position + hit.normal * 10.0
	hit.damage = 40.0
	seed(9191 + k)
	wound.record(hit)
	return t.world.get_children().filter(
		func(n): return not before.has(n) and n.get_script() == BloodSplat
	)


## The plain list's move: push the newest, then drop from the front while over the cap or while
## the front is a splat that is gone.
func _push(model: Array, splat: Node) -> void:
	model.append(splat)
	while model.size() > CAP or (not model.is_empty() and not is_instance_valid(model[0])):
		model.pop_front()


## Instance ids in order, -1 for a splat that is gone.
func _ids(list: Array) -> Array[int]:
	var ids: Array[int] = []
	for splat in list:
		ids.append(splat.get_instance_id() if is_instance_valid(splat) else -1)
	return ids


## How many splats ever thrown have left the list yet are neither gone nor queued for deletion.
func _unqueued_evictions(seen: Array, kept: Array) -> int:
	var count := 0
	for splat in seen:
		if is_instance_valid(splat) and not kept.has(splat) and not splat.is_queued_for_deletion():
			count += 1
	return count
