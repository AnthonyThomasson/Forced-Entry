extends GameTest
## V1 (`docs/player-vision.md`): the cone's corners are read at every facing. The shape query of the
## sector's region is a convex hull the physics engine must build from the region's polygon, and a
## polygon with a vertex almost on the line of its neighbours (a bubble vertex in the direction of
## a sector edge) is one it can fail to build: the query then answers nothing and the cone has no
## corners. A ring of wardrobes round the eye and 30,000 facings drawn with a fixed seed (one of
## them, 137.325 degrees, makes such a vertex): some wardrobe is in the sector at each, so every
## read finds corners.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const Cone := preload("res://scenes/vision/view_cone.gd")
const EYE_AT := Vector2(0, 0)
const RING := 12
const RING_RADIUS := 300.0
const MISSED_SHOWN := 5
const RANDOM_FACINGS := 30_000


func describe() -> Dictionary:
	return {
		"name": "The cone's region is built at every facing",
		"description": "A ring of wardrobes round the eye and thirty thousand seeded facings: the "
			+ "region's shape query finds a wardrobe's corners at each.",
		"tags": ["vision", "3d"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(-800, -800, 1600, 1600), { "walls": false })
	s.switch(&"nav.rebake", false)
	for i in RING:
		var at := EYE_AT + Vector2.from_angle(float(i) / RING * TAU + 0.1) * RING_RADIUS
		s.object(StringName("w%d" % i), "wardrobe", at, { "anchored": true })


func run(t: TestContext) -> void:
	await t.frames(3)
	var space := Probe.space(t)
	var sight := {
		"fov_degrees": Probe.FOV,
		"view_distance": Probe.REACH,
		"awareness_radius": Probe.BUBBLE,
		"eye_height": Probe.SEE_OVER,
	}
	var missed: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 194
	for k in RANDOM_FACINGS:
		var degrees := rng.randf() * 360.0
		var facing := Vector2.RIGHT.rotated(deg_to_rad(degrees))
		var cone := Cone.new()
		cone.begin(space, EYE_AT + Vector2(rng.randf(), rng.randf()) * 7.0, facing, [], sight)
		cone.step(1)
		if cone.get("_build").found.is_empty():
			missed.append("%.5f" % degrees)
	t.expect_eq(
		missed.size(),
		0,
		"no facing reads no corners: %s" % [missed.slice(0, MISSED_SHOWN)],
	)
