extends GameTest
## Fixture for tests/_harness/session_picture_test.gd, not a test of its own (its name does not end
## in `_test`): a test that declares no world, so it stands on the default arena, and builds a
## district of its own into the world, as the worldgen tests do.

## Whether the district is built, and its root.
static var built := false
static var district: Node2D = null


func describe() -> Dictionary:
	return { "name": "Own world fixture", "tags": ["harness"], "internal": true, "timeout": 8.0 }


func configure(s: TestSetup) -> void:
	s.actor(&"me", &"puppet", Vector2(400, 250))


func run(t: TestContext) -> void:
	district = WorldGen.generate_district(3, "", Vector2(400, 700), t.world)
	built = true
	await t.seconds(1.0)
	t.check(district != null, "the district was built")
