extends GameTest
## (A level round at a head flies over a chair, so the piece behind is a wardrobe.) A round that
## passes through a character carries its blood on: a wardrobe standing within
## `BallisticsPenetrationConfig.blood_carry_distance` behind the target gets a bloody mark where the
## round hits it.


func describe() -> Dictionary:
	return {
		"name": "A round carries blood onto what is behind its target",
		"description": "A puppet shoots through another; the wardrobe just behind takes a bloody "
			+ "hit mark.",
		"tags": ["hit particles", "blood", "penetration", "pistol"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.set_static(BallisticsPenetrationConfig, "blood_carry_distance", 400.0)
	s.actor(&"shooter", &"puppet", Vector2(100, 200), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(300, 200), { "max_health": 400.0 })
	s.object(&"wardrobe", "wardrobe", Vector2(460, 200))


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.5)
	shooter.shoot()
	var wardrobe := t.object(&"wardrobe")
	if not t.require(
			await t.until(func(): return not wardrobe.hit_marks().is_empty(), 2.0),
			"the round reaches the wardrobe",
	):
		return
	t.check(
		wardrobe.hit_marks().any(func(i): return i["blood"] > 0.0),
		"the wardrobe's hit mark is bloody",
	)
