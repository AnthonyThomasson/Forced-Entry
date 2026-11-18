extends GameTest
## The blood a round carries out of a character runs out: past
## `BallisticsPenetrationConfig.blood_carry_distance` the surface it hits is marked, but not with
## blood.


func describe() -> Dictionary:
	return {
		"name": "A round's blood runs out with distance",
		"description": "A puppet shoots through another with a tiny carry distance; the wardrobe "
			+ "behind is hit but its mark is clean.",
		"tags": ["hit particles", "blood", "penetration", "pistol"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 400))
	s.set_static(BallisticsPenetrationConfig, "blood_carry_distance", 40.0)
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
		wardrobe.hit_marks().all(func(i): return i["blood"] == 0.0),
		"the wardrobe's hit mark is clean",
	)
