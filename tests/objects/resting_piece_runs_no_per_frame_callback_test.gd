extends GameTest
## A piece at rest costs the frame nothing: its visuals (environment_object_visuals.gd) run no
## per-frame callback and repaint nothing, and a recorded impact (the Deformable's `changed`) still
## repaints it. A district holds hundreds of pieces (perf/match_5v5_stress), and a script callback
## on each makes every process group longer to sort and walk, every frame of a match.

const REST_FRAMES := 30


func describe() -> Dictionary:
	return {
		"name": "A piece at rest runs no per-frame callback",
		"description": "Chairs and a sofa left alone: their visuals neither process nor repaint "
			+ "over 30 frames; a pistol shot that dents a chair repaints it.",
		"tags": ["furniture", "perf", "deformation", "pistol"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(120, 200), { "start_slot": 3 })
	s.object(&"chair", "chair", Vector2(500, 200))
	s.object(&"sofa", "sofa", Vector2(400, 330))


func run(t: TestContext) -> void:
	var drawn := [0]
	var all := t.world.find_children("EnvironmentObjectVisuals", "Node2D", true, false)
	if not t.require(all.size() >= 2, "premise: the pieces have visuals (%d)" % all.size()):
		return
	for visuals: Node2D in all:
		visuals.draw.connect(func(): drawn[0] += 1)
	await t.frames(REST_FRAMES)
	var processing := all.filter(func(v: Node) -> bool: return v.is_processing())
	t.check(processing.is_empty(), "%d of %d pieces' visuals run a per-frame callback"
			% [processing.size(), all.size()])
	t.check(drawn[0] == 0, "%d repaints of pieces left at rest" % drawn[0])
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.object(&"chair").global_position)
	await t.seconds(0.5)
	shooter.shoot()
	var chair := t.object(&"chair")
	t.require(
		await t.until(func(): return t.happened(&"hit", func(d): return d["victim"] == chair), 2.0),
		"premise: the shot hits the chair",
	)
	await t.frames(3)
	t.check(drawn[0] >= 1, "the dented chair is repainted (%d repaints)" % drawn[0])
