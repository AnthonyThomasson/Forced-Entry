extends GameTest
## D12 (#194): a spent casing flies in the twin 3D space. Ejected over a desk it falls onto the
## desk's top (31 px up) and rests there, inside its footprint; ejected in the open it falls to the
## floor.

const DESK := Vector2(300, 100)
## The desk's footprint (120 x 50) and top.
const HALF := Vector2(60, 25)
const TOP := 31.0
## Where the gun's port is: a standing shooter's muzzle is 65 px up.
const PORT := 55.0
const OPEN := Vector2(500, 250)


func describe() -> Dictionary:
	return {
		"name": "A casing ejected over a desk lands on the desk's top",
		"description": "A casing let go 55 px up over a desk's middle falls onto the desk's 31 px "
			+ "top and rests inside its footprint; one in the open falls to the floor.",
		"tags": ["casing", "projectile", "3d", "furniture", "heights"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"nav.rebake", false)
	s.object(&"desk", "desk", DESK)


func run(t: TestContext) -> void:
	await t.frames(3)
	var on_desk := CasingSpawner.spawn(
		DESK,
		Vector2.UP,
		t.world,
		PORT,
	)  # thrown to its side: along the desk
	var in_open := CasingSpawner.spawn(OPEN, Vector2.RIGHT, t.world, PORT)
	if not t.require(
			await t.until(func(): return on_desk.is_resting() and in_open.is_resting(), 4.0),
			"both casings came to rest",
	):
		return
	var at: Vector2 = on_desk.global_position
	t.check(
		absf(at.x - DESK.x) <= HALF.x and absf(at.y - DESK.y) <= HALF.y,
		"the casing over the desk lies within its footprint (%s)" % str(at.round()),
	)
	t.check(
		absf(on_desk.altitude() - TOP) <= 2.0,
		"on its top (%.1f px up, the top at %.0f)" % [on_desk.altitude(), TOP],
	)
	t.check(
		in_open.altitude() <= 1.0,
		"in the open it lies on the floor (%.1f px up)" % in_open.altitude(),
	)
