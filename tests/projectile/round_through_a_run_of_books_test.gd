extends GameTest
## A run of books stops a pistol round and lets a rifle round through (#194 unbake-b, D21,
## `docs/stacked-items.md` SI13, SI7): a bookshelf with its books loose on the boards is shot from
## the front at the height of a run on its lowest board, with a dummy a step behind it. The pistol's
## round goes through the run (a hit, the run's paper) but is spent in it and in the back: the
## dummy is not hit; the rifle's goes on and hits the dummy.
##
## Both are shot at the run, level with its middle, from the front.

const SHOOTER_GAP := 260.0
const TARGET_GAP := 14.0
const ROWS := { &"pistol": 120.0, &"rifle": 560.0 }
const SLOTS := { &"pistol": 3, &"rifle": 6 }
const AT_X := 400.0


func describe() -> Dictionary:
	return {
		"name": "A run of books stops a pistol round, a rifle round goes through",
		"description": "A bookshelf with loose books, shot from the front at a run on the "
			+ "lowest board with a dummy behind the shelf: the pistol round is stopped by the "
			+ "run and the back, the rifle round hits the dummy.",
		"tags": ["items", "bullets", "penetration", "projectile", "unbake"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 900))
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	for gun: StringName in ROWS:
		var row: float = ROWS[gun]
		s.object(StringName("shelf_%s" % gun), "bookshelf", Vector2(AT_X, row))
		s.actor(
			StringName("shooter_%s" % gun), &"puppet", Vector2(AT_X, row + SHOOTER_GAP),
			{ "start_slot": SLOTS[gun] },
		)
		s.actor(
			StringName("dummy_%s" % gun), &"puppet",
			Vector2(AT_X, row - 40.0 - TARGET_GAP),
			{ "max_health": 500.0, "faction": &"dummy" },
		)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	# A run's penetration (70) stands in for its thickness (a hand of paper): at the bounce minimum
	# a round glances off it (`BallisticsRicochetConfig.penetration_bounce_min`), as off a wall.
	var penetration := float(ObjectDefinitions.get_definition("book_stood")["penetration"])
	t.check(
		penetration < BallisticsRicochetConfig.penetration_bounce_min,
		"a run of books (penetration %.0f) is below the bounce minimum (%.0f): a round goes in"
		% [penetration, BallisticsRicochetConfig.penetration_bounce_min],
	)
	var runs: Dictionary = {}
	for gun: StringName in ROWS:
		var shelf: Node2D = t.object(StringName("shelf_%s" % gun))
		var placed := RoomItems.carry(
			shelf, ObjectDefinitions.get_definition("bookshelf"), shelf.get_parent(), "test"
		)
		runs[gun] = _lowest_run(placed)
		t.require(runs[gun] != null, "premise: the %s's shelf carries books" % gun)
	await t.seconds(1.0)
	var target_hits := {}
	for gun: StringName in ROWS:
		target_hits[gun] = await _fire(t, gun, runs[gun])
	t.check(target_hits[&"pistol"] == 0, "the pistol round is spent in the books and the back")
	t.check(target_hits[&"rifle"] > 0, "the rifle round goes through to the dummy")


## The `gun`'s round fired at `book` (a run) from in front of its shelf, a dummy behind the shelf:
## how many hits the dummy took (the run's own is checked).
func _fire(t: TestContext, gun: StringName, book: Node2D) -> int:
	var shelf: Node2D = t.object(StringName("shelf_%s" % gun))
	var size: Vector2 = shelf.size
	var dummy: Node2D = t.actor(StringName("dummy_%s" % gun))
	dummy.global_position = Vector2(
		book.global_position.x, shelf.position.y - size.y * 0.5 - TARGET_GAP
	)
	var shooter: Node2D = t.actor(StringName("shooter_%s" % gun))
	shooter.global_position.x = book.global_position.x
	await t.frames(2)
	var puppet := t.puppet(StringName("shooter_%s" % gun))
	puppet.aim_at(book.global_position, _middle_of(book))
	await t.seconds(0.5)
	puppet.shoot()
	await t.seconds(0.5)
	var on_run := t.events_of(&"hit", func(d): return d["victim"] == book)
	t.check(on_run.size() >= 1, "the %s's round hit the run of books" % gun)
	return t.events_of(&"hit", func(d): return d["victim"] == dummy).size()


## The `book_stood` item of the lowest board in `placed` (`RoomItems.carry`'s entries), the
## widest of them.
func _lowest_run(placed: Array) -> Node2D:
	var best: Node2D = null
	for entry: Dictionary in placed:
		var item: Node2D = entry["node"]
		if entry["key"] != "book_stood":
			continue
		if best == null or _lift_of(item) < _lift_of(best) or (
			_lift_of(item) == _lift_of(best) and item.size.x > best.size.x
		):
			best = item
	return best


func _lift_of(item: Node2D) -> float:
	return (item.rest as PieceRest).lift


## The height (px) a round level with the middle of `book` flies at.
func _middle_of(book: Node2D) -> float:
	return _lift_of(book) + float(book.look.art_opts.get("height", 10.0)) * 0.5
