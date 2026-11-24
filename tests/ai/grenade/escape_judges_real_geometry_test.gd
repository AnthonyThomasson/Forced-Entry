extends GameTest
## G16's danger zone, judged by the real 3D line from the burst to the body (#194 D10;
## `AgentThrow.in_zone`, the blast's own rule `Explosion.shields`): a body is outside a frag's zone
## when every point of it, at its posture's heights, is cut off from the burst by what stands in
## the way. A row of couches (back 38 px) 115 px from a burst on the floor: a standing body 125 px
## behind it is in their shadow (safe standing), one close behind it is not (the line rises over
## the back to its head) unless it is ducked (head 36), and a burst at a desk's height (31 px up)
## has no shadow behind the couches at all: the line from it clears their backs.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const BURST := Vector2(500, 340)
const ROW_Y := 480.0
const CLOSE := Vector2(500, 530)
const FAR := Vector2(500, 600)


func describe() -> Dictionary:
	return {
		"name": "The AI judges a spot's cover by the real line from the burst, at real postures",
		"description": "Behind a row of couches a frag's danger zone has a shadow: a standing "
			+ "body far behind them is outside it, one close behind them is inside it unless it "
			+ "is ducked, and a burst raised to a desk's height has no such shadow.",
		"tags": ["ai", "grenade", "evade", "cover", "3d"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 800))
	for i in 3:
		s.object(StringName("couch_%d" % i), "sofa", Vector2(BURST.x - 120.0 + 120.0 * i, ROW_Y))
	s.actor(&"npc", &"puppet", Vector2(80, 80), { "max_health": 100_000.0 })


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var npc := t.actor(&"npc")
	var geometry := AgentThrow.new()
	var space: PhysicsDirectSpaceState3D = TwinSpace.space_of(npc)
	var threat := GrenadeAi.escape_threat(&"frag", Probe.BLAST_RADIUS, BURST, 3.0)
	t.check(
		not geometry.in_zone(space, threat, FAR, BodyHeights.STAND),
		"a standing body 115 px behind the couches is outside the zone: in their shadow",
	)
	t.check(
		geometry.in_zone(space, threat, CLOSE, BodyHeights.STAND),
		"one close behind them is inside it: the line clears the back to its head",
	)
	t.check(
		not geometry.in_zone(space, threat, CLOSE, BodyHeights.DUCK),
		"the same body ducked is outside it: its head is under the back's top",
	)
	threat.burst_height = 31.0 + Explosion.BURST_CENTRE
	t.check(
		geometry.in_zone(space, threat, FAR, BodyHeights.STAND),
		"a burst at a desk's height has no shadow behind the couches: the standing body is in",
	)
	threat.burst_height = Explosion.BURST_CENTRE
	_check_escape(t, geometry, space)


## `escape` / `has_escape` on the same judgement: an NPC standing exposed close behind the couches
## with time to move picks a spot the real line shields at the posture it would hold there (a
## ducked spot is a `crouch`); with no fuse left and no legs, and nothing to hide behind, there is
## no way to get safe.
func _check_escape(t: TestContext, geometry: RefCounted, space: PhysicsDirectSpaceState3D) -> void:
	var map: RID = NavWorld.map_of(t.world)
	var npc := t.actor(&"npc")
	var threat := GrenadeAi.escape_threat(&"frag", Probe.BLAST_RADIUS, BURST, 3.0)
	var runner := GrenadeAi.escape_runner(CLOSE, 200.0)
	var plan: Dictionary = geometry.escape(space, map, threat, runner, [])
	if not t.require(
			plan["spot"] != Vector2.INF,
			"an NPC standing exposed behind the couches, with 3 s, finds a safe spot",
	):
		return
	var held := BodyHeights.DUCK if plan["crouch"] else BodyHeights.STAND
	t.check(
		GrenadeAi.shielded(
			t,
			BURST,
			npc,
			Explosion.BURST_CENTRE,
			{ "at": plan["spot"], "posture": held },
		),
		"the spot %s is shielded by the real line in the posture it takes there (%s)"
			% [str((plan["spot"] as Vector2).round()), held],
	)
	var stuck := GrenadeAi.escape_runner(CLOSE, 0.0)
	var none := GrenadeAi.escape_threat(&"frag", Probe.BLAST_RADIUS, Vector2(500, 700), 0.1)
	t.check(
		not geometry.has_escape(space, map, none, stuck, []),
		"with no fuse and no legs, nothing to hide behind and the zone all round: no escape",
	)
