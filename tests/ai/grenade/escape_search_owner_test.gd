extends GameTest
## G16, an escape search belongs to the NPC that asked for it (`AgentGrenades._begin`,
## `EscapePool`): one its NPC has not asked after for more than `STALE_FRAMES` is not picked up
## again, the NPC begins a new one from where it stands and with the fuse left now (the old one's
## answer is for a runner and a fuse that are gone); one whose NPC has died or been freed is
## cancelled and spends none of the pool. The pool is given nothing to spend (`per_frame` 0), so no
## search finishes and what each is asked is all that is seen.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")
const FIRST_FUSE := 2.0
const LATER_FUSE := 1.2


func describe() -> Dictionary:
	return {
		"name": "An escape search is its NPC's: a stale one is begun again, a dead one's dropped",
		"description": "A search unasked for 40 frames is replaced by a new one from where the NPC "
			+ "stands with the fuse left now; the search of an NPC that died or was freed is "
			+ "cancelled.",
		"tags": ["ai", "grenade", "evade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.set_static(EscapePool, "per_frame", 0)
	s.actor(&"npc", &"puppet", Maps.HALL_MIDDLE)
	s.actor(&"doomed", &"puppet", Maps.HALL_MIDDLE + Vector2(0, 40))
	s.actor(&"freed", &"puppet", Maps.HALL_MIDDLE + Vector2(60, 40))


func run(t: TestContext) -> void:
	EscapePool.reset()
	for id: StringName in [&"npc", &"doomed", &"freed"]:
		Probe.arm(t.actor(id), 0, 1)
	await t.frames(2)
	await _check_stale(t)
	await _check_gone(t)
	EscapePool.reset()


## The perception of `id`'s grenades, bound to its body, and a frag 90 px west of the hall's middle
## that it has seen.
func _known(t: TestContext, id: StringName, grenade: StubGrenade) -> AgentGrenades:
	var npc := t.actor(id)
	var geometry := AgentThrow.new()
	geometry.vision = AgentVision.new()
	geometry.bind(npc)
	geometry.learn_carried()
	var known := AgentGrenades.new()
	known.setup(geometry)
	known.bind(npc)
	known.enabled = true
	known._note(grenade, grenade.global_position, &"seen", false)
	return known


func _plan(t: TestContext, known: AgentGrenades, id: StringName) -> void:
	var npc := t.actor(id)
	known.plan(TwinSpace.space_of(npc), NavWorld.map_of(npc), SightRay.exclude_of(npc))


func _frag(t: TestContext) -> StubGrenade:
	var grenade := StubGrenade.new()
	grenade.position = Maps.HALL_MIDDLE + Vector2(-90, 0)
	grenade.fuse = FIRST_FUSE
	t.world.add_child(grenade)
	return grenade


func _check_stale(t: TestContext) -> void:
	var grenade := _frag(t)
	var known := _known(t, &"npc", grenade)
	var id := grenade.get_instance_id()
	_plan(t, known, &"npc")
	var first: EscapeSearch = known.get("_searches").get(id)
	if not t.require(first != null, "set-up: the NPC began a search"):
		return
	await t.frames(EscapePool.STALE_FRAMES + 10)
	var moved := Maps.HALL_MIDDLE + Vector2(40, 0)
	(t.actor(&"npc") as Node2D).global_position = moved
	grenade.fuse = LATER_FUSE
	_plan(t, known, &"npc")
	var second: EscapeSearch = known.get("_searches").get(id)
	var asked: Dictionary = known.get("_asked").get(id, {})
	t.check(second != null and second != first, "the stale search is not picked up again")
	t.check(
		(asked.get("from", Vector2.INF) as Vector2).distance_to(moved) < 1.0
		and is_equal_approx(float(asked.get("began_fuse", 0.0)), LATER_FUSE),
		"the new search is from where the NPC stands and the fuse left now (%s)" % [asked],
	)


func _check_gone(t: TestContext) -> void:
	var dying := _frag(t)
	var known := _known(t, &"doomed", dying)
	_plan(t, known, &"doomed")
	var search: EscapeSearch = known.get("_searches").get(dying.get_instance_id())
	var freed_grenade := _frag(t)
	var freed_known := _known(t, &"freed", freed_grenade)
	_plan(t, freed_known, &"freed")
	var orphan: EscapeSearch = freed_known.get("_searches").get(freed_grenade.get_instance_id())
	if not t.require(search != null and orphan != null, "set-up: both began a search"):
		return
	t.actor(&"doomed").take_damage(1_000_000.0)
	t.actor(&"freed").queue_free()
	await t.frames(2)
	if not t.require(t.actor(&"doomed").is_dead, "set-up: the NPC died"):
		return
	var npc := t.actor(&"npc")
	EscapePool.serve(TwinSpace.space_of(npc), NavWorld.map_of(npc))
	t.check(search.done, "the search of an NPC that died is cancelled")
	t.check(orphan.done, "the search of an NPC that was freed is cancelled")


## A live frag as the grenade perception reads one (`kind`, `fuse_left()`, `throw_stats()`).
class StubGrenade extends Node2D:
	var kind := &"frag"
	var fuse := 2.0

	func fuse_left() -> float:
		return fuse

	func throw_stats() -> Dictionary:
		return {
			"kind": &"frag", "max_range": 550.0, "danger_radius": 250.0, "fuse": 3.0,
			"flash_cover_reach": INF, "max_blind": 0.0,
		}
