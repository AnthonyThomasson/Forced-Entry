extends GameTest
## An outfit's weight is cached between loadout changes. Repeated movement reads do not walk every
## garment and plate again; changing the loadout refreshes the value.

const Probe := preload("res://tests/_outfit/outfit_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "Outfit weight follows the loadout",
		"description": "Repeated weight reads reuse one total, while a new outfit is weighed again "
			+ "and changes the character's carried weight.",
		"tags": ["items", "outfit", "perf"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.actor(&"wearer", &"puppet", Vector2(300, 200))


func run(t: TestContext) -> void:
	var outfit: Outfit = t.actor(&"wearer").wardrobe.outfit
	var scans = outfit.get("weight_scans")
	if not t.require(scans != null, "the outfit counts its full weight scans"):
		return
	outfit.set_ids(Probe.PLAIN_CLOTHES)
	var plain := outfit.weight()
	var after_plain: int = outfit.get("weight_scans")
	for _i in 20:
		t.check(outfit.weight() == plain, "an unchanged loadout keeps the same weight")
	t.check(outfit.get("weight_scans") == after_plain, "repeated reads reuse the cached weight")
	outfit.set_ids(Probe.PLATED_KIT)
	var plated := outfit.weight()
	t.check(plated > plain, "a heavier loadout changes the cached weight")
	t.check(outfit.get("weight_scans") == after_plain + 1, "the new loadout is weighed once")
