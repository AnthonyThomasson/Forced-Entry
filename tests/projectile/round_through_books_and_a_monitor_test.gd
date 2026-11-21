extends GameTest
## Rounds go by the material of what they meet, at its real height (#194 stack-a, D20,
## `docs/stacked-items.md` SI7): three books stacked on a crate are shot one by one, each at its own
## height (2.5 px apart): a round at one goes through that book alone (paper), the others are over
## or under its line; a round at a monitor on a crate goes through it (electronics, 14 px).

const BOOKS_ROW := 120.0
const MONITOR_ROW := 340.0
const SHOOTER_X := 100.0
const AT_X := 400.0
## How high the crate is, a book's thickness, and the monitor's middle.
const CRATE := 16.0
const BOOK := 2.5
const MONITOR_MIDDLE := CRATE + 7.0


func describe() -> Dictionary:
	return {
		"name": "A round goes by the material of a book stack and a monitor",
		"description": "Three books on a crate are shot top to bottom, each at its own height: "
			+ "each round penetrates its book and no other; a round at a monitor on a crate "
			+ "penetrates it.",
		"tags": ["items", "stacking", "bullets", "penetration", "projectile"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	var straight: Dictionary = GunConfig.guns.duplicate(true)
	for gun: StringName in straight:
		straight[gun]["spread_deg"] = 0.0
	s.set_static(GunConfig, "guns", straight)
	s.actor(&"book_gun", &"puppet", Vector2(SHOOTER_X, BOOKS_ROW), { "start_slot": 3 })
	s.actor(&"monitor_gun", &"puppet", Vector2(SHOOTER_X, MONITOR_ROW), { "start_slot": 3 })
	s.object(&"books_crate", "crate", Vector2(AT_X, BOOKS_ROW))
	s.object(&"book_a", "book", Vector2.ZERO, { "on": &"books_crate" })
	s.object(&"book_b", "book", Vector2.ZERO, { "on": &"books_crate" })
	s.object(&"book_c", "book", Vector2.ZERO, { "on": &"books_crate" })
	s.object(&"monitor_crate", "crate", Vector2(AT_X, MONITOR_ROW))
	s.object(&"monitor", "monitor", Vector2.ZERO, { "on": &"monitor_crate" })
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.seconds(1.0)
	var middle := {
		&"book_c": CRATE + BOOK * 2.5, &"book_b": CRATE + BOOK * 1.5, &"book_a": CRATE + BOOK * 0.5,
	}
	# the top book first, so each shot below it finds its book where it was
	for id: StringName in [&"book_c", &"book_b", &"book_a"]:
		t.puppet(&"book_gun").aim_at(Vector2(AT_X, BOOKS_ROW), middle[id])
		await t.seconds(0.5)
		t.puppet(&"book_gun").shoot()
		await t.seconds(0.4)
		var hits := _hits(t, id)
		t.check(
			hits.size() == 1 and hits[0] == &"penetrate",
			"a round at the %.1f px of %s went through it (%s)" % [middle[id], id, hits],
		)
	t.puppet(&"monitor_gun").aim_at(Vector2(AT_X, MONITOR_ROW), MONITOR_MIDDLE)
	await t.seconds(0.5)
	t.puppet(&"monitor_gun").shoot()
	await t.seconds(0.4)
	var on_monitor := _hits(t, &"monitor")
	t.check(
		on_monitor.size() == 1 and on_monitor[0] == &"penetrate",
		"a round at the monitor's 14 px of electronics went through it (%s)" % [on_monitor],
	)


## The outcomes of the rounds that hit item `id`.
func _hits(t: TestContext, id: StringName) -> Array:
	return t.events_of(&"hit", func(d): return d["victim"] == t.object(id)).map(
		func(d): return d["outcome"]
	)
