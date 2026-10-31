extends GameTest
## DR5: a standing door is a solid leaf in the world. A puppet walking into a shut door stops at it;
## a pistol round goes on through a hollow door and stops in a steel one; an NPC does not see a
## puppet through a shut wooden door and does through a glass-panel one; the shut door casts a
## shadow (a light occluder) and the glass-panel door none.

const WIDTH := 52.0
## The walls are 12 px thick and their ends reach 6 px into the gap, so the doorway is free between
## jambs 40 px apart; the hinge sits on one of them.
const JAMB := 20.0
## The doorways' rows (y) along the wall at x = 400, and what stands in each.
const SIGHT_WOOD := 100.0
const SHOT_STEEL := 250.0
const SIGHT_GLASS := 400.0
const SHOT_HOLLOW := 550.0
const WALK := 700.0


func describe() -> Dictionary:
	return {
		"name": "A standing door blocks bodies, rounds by penetration, sight and light",
		"description": "A shut door stops a walking puppet; a pistol round passes a hollow door "
			+ "and stops in steel; sight is stopped by a wooden door, not a glass one; a wooden "
			+ "door casts a shadow, a glass one none.",
		"tags": ["door", "objects", "projectile", "vision", "lighting"],
		"timeout": 12.0,
	}


func _doorway(y: float, material: String, style: String, id: String) -> Dictionary:
	return {
		"pos": Vector2(400, y), "width": WIDTH,
		"door": {
			"name": id, "material": material, "style": style,
			"hinge": Vector2(400, y - JAMB), "swing_into": Vector2.RIGHT,
		},
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": Rect2(0, 0, 400, 800) },
		{ "key": "east", "type": "bedroom", "rect": Rect2(400, 0, 400, 800) },
	], [
		_doorway(SIGHT_WOOD, "hollow", "flush", "sight_wood"),
		_doorway(SHOT_STEEL, "steel", "riveted", "shot_steel"),
		_doorway(SIGHT_GLASS, "glass", "panes", "sight_glass"),
		_doorway(SHOT_HOLLOW, "hollow", "panelled", "shot_hollow"),
		_doorway(WALK, "solid", "plank", "walk"),
	])
	# a character is partial cover; make every round that arrives land
	s.switch(&"projectile.flyover", false)
	# dead straight: it is the door being tested, not the aim
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.von_down()
	s.actor(&"walker", &"puppet", Vector2(300, WALK))
	for row in [[&"steel", SHOT_STEEL], [&"hollow", SHOT_HOLLOW]]:
		s.actor(StringName("%s_shooter" % row[0]), &"puppet", Vector2(300, row[1]), {
			"start_slot": 3,
		})
		s.actor(StringName("%s_target" % row[0]), &"puppet", Vector2(500, row[1]), {
			"max_health": 400.0,
		})
	for row in [[&"wood", SIGHT_WOOD], [&"glass", SIGHT_GLASS]]:
		s.actor(StringName("%s_watcher" % row[0]), &"invader", Vector2(330, row[1]), {
			"movement:speed": 0.0, "facing": Vector2.RIGHT,
		})
		s.actor(StringName("%s_hidden" % row[0]), &"puppet", Vector2(480, row[1]), {
			"max_health": 100_000.0,
		})


func run(t: TestContext) -> void:
	t.puppet(&"walker").walk_to(Vector2(500, WALK))
	for kind in [&"steel", &"hollow"]:
		t.puppet(StringName("%s_shooter" % kind)).aim_at(t.actor(StringName("%s_target" % kind)))
	await t.seconds(0.6)
	for _i in 3:
		for kind in [&"steel", &"hollow"]:
			t.puppet(StringName("%s_shooter" % kind)).shoot()
		await t.seconds(0.4)
	await t.seconds(1.5)

	var walker := t.actor(&"walker")
	t.check(
		walker.global_position.x > 340.0 and walker.global_position.x < 392.0,
		"the walker stops at the shut door (x %.0f)" % walker.global_position.x,
	)
	var hollow_target := t.actor(&"hollow_target")
	t.check(
		hollow_target.health < hollow_target.max_health,
		"a pistol round goes on through a hollow door (%.0f / %.0f)"
			% [hollow_target.health, hollow_target.max_health],
	)
	var steel_target := t.actor(&"steel_target")
	t.check(
		steel_target.health == steel_target.max_health,
		"a pistol round stops in a steel door (%.0f / %.0f)"
			% [steel_target.health, steel_target.max_health],
	)
	t.check(
		t.actor(&"steel_shooter").ammo.rounds(3) < t.actor(&"steel_shooter").ammo.capacity(3),
		"the pistol did fire at the steel door",
	)
	t.check(
		not _sees(t, &"wood_watcher", &"wood_hidden"),
		"an NPC does not see a puppet through a shut wooden door",
	)
	t.check(
		_sees(t, &"glass_watcher", &"glass_hidden"),
		"an NPC sees a puppet through a glass-panel door",
	)
	t.check(
		not t.object(&"sight_wood").find_children("*", "LightOccluder2D", true, false).is_empty(),
		"a shut wooden door casts a shadow",
	)
	t.check(
		t.object(&"sight_glass").find_children("*", "LightOccluder2D", true, false).is_empty(),
		"a glass-panel door casts none",
	)


## Whether the NPC `who` knows `target` as visible now.
func _sees(t: TestContext, who: StringName, target: StringName) -> bool:
	var brain := t.controller(who, &"known_contacts_for_display")
	for c in brain.known_contacts_for_display():
		if str(c["name"]) == str(target) and c["visible"]:
			return true
	return false
