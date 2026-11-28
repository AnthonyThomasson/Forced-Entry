extends GameTest
## A round through a fridge's glass meets what is behind it by material (#194, D21,
## `docs/stacked-items.md` SI16): shot from the front at a shelf of bottles, the first thing it
## meets is the piece's glass (a hit whose material is glass, the round goes on), then the bottles
## (a hit on the item); shot from the side at the same height it meets the steel side, not glass.

const SHOOTER_GAP := 240.0
const AT := Vector2(400, 300)


func describe() -> Dictionary:
	return {
		"name": "A round through a fridge's glass meets the bottles",
		"description": "A stocked drinks fridge shot from the front at the height of its middle "
			+ "shelf: the glass is hit first (material glass) and the round goes on to hit the "
			+ "bottles; from the side the same height hits steel.",
		"tags": ["items", "bullets", "penetration", "projectile", "unbake"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 700))
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.object(&"fridge", "drinks_fridge", AT)
	s.actor(&"front", &"puppet", AT + Vector2(0.0, SHOOTER_GAP), { "start_slot": 6 })
	s.actor(&"side", &"puppet", AT + Vector2(-SHOOTER_GAP, 0.0), { "start_slot": 6 })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var fridge: Node2D = t.object(&"fridge")
	var placed := RoomItems.carry(
		fridge, ObjectDefinitions.get_definition("drinks_fridge"), fridge.get_parent(), "test"
	)
	var bottle := _middle_shelf(placed)
	t.require(bottle != null, "premise: the fridge carries bottles")
	await t.seconds(1.0)
	var level := _middle_of(bottle)
	t.actor(&"front").global_position.x = bottle.global_position.x
	await t.frames(2)
	await _fire(t, &"front", bottle.global_position, level)
	var on_glass := t.events_of(
		&"hit", func(d): return d["victim"] == fridge and d["material"] == "glass"
	)
	var on_bottle := t.events_of(&"hit", func(d): return d["victim"] == bottle)
	t.check(on_glass.size() >= 1, "the round from the front met the glass first")
	t.check(on_bottle.size() >= 1, "the round went through the glass to the bottles")
	var before := t.events_of(&"hit").size()
	t.actor(&"side").global_position.y = AT.y
	await t.frames(2)
	await _fire(t, &"side", fridge.global_position, level)
	var steel := t.events_of(&"hit").slice(before).filter(
		func(d): return d["victim"] == fridge and d["material"] == "metal"
	)
	t.check(steel.size() >= 1, "from the side the round met the steel")


## The run of `placed` (`RoomItems.carry`'s entries) on the board nearest the middle of the fridge.
func _middle_shelf(placed: Array) -> Node2D:
	var best: Node2D = null
	for entry: Dictionary in placed:
		var item: Node2D = entry["node"]
		if best == null or absf(_lift_of(item) - 30.0) < absf(_lift_of(best) - 30.0):
			best = item
	return best


## The puppet `who` aimed at `at`, `level` px up, and fired once.
func _fire(t: TestContext, who: StringName, at: Vector2, level: float) -> void:
	var puppet := t.puppet(who)
	puppet.aim_at(at, level)
	await t.seconds(0.5)
	puppet.shoot()
	await t.seconds(0.5)


func _lift_of(item: Node2D) -> float:
	return (item.rest as PieceRest).lift


## The height (px) a round level with the middle of `item` flies at.
func _middle_of(item: Node2D) -> float:
	return _lift_of(item) + float(item.look.art_opts.get("height", 10.0)) * 0.5
