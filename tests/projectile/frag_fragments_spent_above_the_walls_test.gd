extends GameTest
## G8 (#194 D10): a fragment that climbs past the walls' top has nothing left to strike (no body,
## piece or wall stands higher, and a roof would stop it) and is spent there instead of flying its
## whole reach through the air: each fragment's reach ends where its line meets
## `Explosion.FRAGMENT_CEILING`, or at the row's `fragment_range` when that comes first. Read off
## the fragments as they leave a burst on the floor.

const AT := Vector2(500, 300)


func describe() -> Dictionary:
	return {
		"name": "A frag's fragments are spent above the walls' top",
		"description": "Right after a frag goes off, no fragment's reach takes it higher than the "
			+ "ceiling, and a steep one's reach is far shorter than a level one's.",
		"tags": ["grenade", "frag", "fragments", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 600))
	s.switch(&"nav.rebake", false)
	s.actor(&"thrower", &"puppet", Vector2(60, 60), { "max_health": 1.0e9 })


func run(t: TestContext) -> void:
	var row: Dictionary = GrenadeConfig.row(&"frag")
	Explosion.frag(AT, t.world, t.actor(&"thrower"), row)
	var group := t.world.get_children().filter(
		func(n): return String(n.name).begins_with("Projectile") and n is Node2D,
	)
	if not t.require(group.size() == int(row["fragments"]), "the fragments are in the world"):
		return
	var highest := 0.0
	var shortest := INF
	var longest := 0.0
	for p: Node2D in group:
		var sine := float(p.rise) / sqrt(1.0 + float(p.rise) * float(p.rise))
		highest = maxf(highest, float(p.height) + float(p.max_distance) * sine)
		shortest = minf(shortest, float(p.max_distance))
		longest = maxf(longest, float(p.max_distance))
	t.check(
		highest <= Explosion.FRAGMENT_CEILING + 1.0,
		"no fragment's reach climbs past the ceiling (%.1f px, the ceiling %.0f)"
			% [highest, Explosion.FRAGMENT_CEILING],
	)
	t.check(
		shortest < 0.5 * float(row["fragment_range"]),
		"a steep fragment is spent far short of the row's reach (%.0f px against %.0f)"
			% [shortest, float(row["fragment_range"])],
	)
	t.expect_near(
		longest,
		float(row["fragment_range"]),
		1.0,
		"a level one keeps the row's reach (%.0f px)" % longest,
	)
