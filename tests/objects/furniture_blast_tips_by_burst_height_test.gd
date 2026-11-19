extends GameTest
## A blast shoves a free piece at its burst's height (#194 furn3d, D13): the same burst, up at chest
## height, lays a tall thin bookshelf on its side and only slides a low heavy sofa, which stays
## upright. The frag's fragments are left out (`fragments` 0): what lays the shelf down is the
## blast's own push, applied at the burst's height, not a fragment's hit.

const Probe := preload("res://tests/_objects/piece_probe.gd")
const SHELF := Vector2(300, 140)
const SOFA := Vector2(300, 420)
## The burst point sits this far (px) to the side of the piece's centre, and this high.
const BESIDE := 60.0
const BURST_HEIGHT := 60.0


func describe() -> Dictionary:
	return {
		"name": "A blast up high lays a bookshelf on its side and only slides a sofa",
		"description": "A frag goes off 60 px up and 60 px beside a bookshelf and, the same way, "
			+ "beside a sofa: the shelf lies on its side, the sofa slid and stayed upright.",
		"tags": ["furniture", "3d", "tipping", "blast", "knockback"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.object(&"shelf", "bookshelf", SHELF)
	s.object(&"sofa", "sofa", SOFA)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	await t.frames(3)
	var shelf := t.object(&"shelf")
	var sofa := t.object(&"sofa")
	var row := GrenadeConfig.row(&"frag").duplicate()
	row["fragments"] = 0
	Explosion.frag(SHELF - Vector2(BESIDE, 0), t.world, null, row, BURST_HEIGHT)
	Explosion.frag(SOFA - Vector2(BESIDE, 0), t.world, null, row, BURST_HEIGHT)
	await t.seconds(0.3)  # the blasts wake them (the node's `sleeping` reads the last step)
	await Probe.settle(t, shelf, 10.0)
	await Probe.settle(t, sofa, 10.0)
	t.check(
		Probe.lean(shelf) > 60.0,
		"the bookshelf lies on its side (%.0f degrees)" % Probe.lean(shelf),
	)
	t.check(
		Probe.lean(sofa) < 15.0,
		"the sofa stays upright (%.0f degrees)" % Probe.lean(sofa),
	)
	t.check(
		sofa.global_position.distance_to(SOFA) > 3.0,
		"but slid (%.1f px)" % sofa.global_position.distance_to(SOFA),
	)
