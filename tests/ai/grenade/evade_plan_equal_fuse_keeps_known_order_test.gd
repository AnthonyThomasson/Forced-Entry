extends GameTest
## G16, the plan for the grenade that goes off first: when two known grenades have exactly the same
## fuse left, the one the NPC knew first is the plan it returns, whichever of them was planned for
## first on this call (a grenade with a plan already is asked after one without, so a fresh plan
## takes a free search before a replan does, but that order must not pick the plan returned).
## The NPC stands in the hall of the terrace house with two frags it knows, both 2 s from
## bursting, both in whose zone it stands: it plans the first, then learns the second, and the plan
## it is handed is still the first's.

const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")
const FUSE := 2.0


func describe() -> Dictionary:
	return {
		"name": "Two grenades with the same fuse: the one known first is the plan",
		"description": "An NPC that knows a planned frag and a fresh one with the same fuse left "
			+ "is handed the plan of the one it knew first.",
		"tags": ["ai", "grenade", "evade"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.actor(&"npc", &"puppet", Maps.HALL_MIDDLE)


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	Probe.arm(npc, 0, 1)
	await t.frames(2)
	var geometry := AgentThrow.new()
	geometry.vision = AgentVision.new()
	geometry.bind(npc)
	geometry.learn_carried()
	geometry.learn_body()
	var known := AgentGrenades.new()
	known.setup(geometry)
	known.bind(npc)
	known.enabled = true
	var first := _frag(t, Maps.HALL_MIDDLE + Vector2(-90, 0))
	var second := _frag(t, Maps.HALL_MIDDLE + Vector2(90, 0))
	var space: PhysicsDirectSpaceState2D = npc.get_world_2d().direct_space_state
	var map: RID = npc.get_world_2d().navigation_map
	var exclude: Array = [npc.get_rid()]
	known._note(first, first.global_position, &"seen", false)
	var planned := known.plan(space, map, exclude)
	if not t.require(
			planned.get("id", 0) == first.get_instance_id(),
			"set-up: the NPC plans the first grenade (%s)" % [planned],
	):
		return
	known._note(second, second.global_position, &"seen", false)
	var plan := known.plan(space, map, exclude)
	t.check(
		plan.get("id", 0) == first.get_instance_id(),
		"with the second grenade fresh and as near to bursting, the plan is still the first's (%s)"
			% [plan],
	)


## A frag at `at` with `FUSE` s left, as the grenade perception reads one (`kind`, `fuse_left()`,
## `throw_stats()`).
func _frag(t: TestContext, at: Vector2) -> Node2D:
	var grenade := StubGrenade.new()
	grenade.position = at
	t.world.add_child(grenade)
	return grenade


## What a live grenade tells the perception about itself.
class StubGrenade extends Node2D:
	var kind := &"frag"

	func fuse_left() -> float:
		return FUSE

	func throw_stats() -> Dictionary:
		return {
			"kind": &"frag", "max_range": 550.0, "danger_radius": 250.0, "fuse": 3.0,
			"flash_cover_reach": INF, "max_blind": 0.0,
		}
