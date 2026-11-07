extends GameTest
## The body's draw cache (`BodyDrawCache`) keeps an undented round part's uvs for the silhouette
## it kept. The ring's point count (`PhysicsDeformConfig.circle_points`) changing between two draws
## gives the part a new silhouette, so its uvs must follow: one uv per vertex, as a plain draw has.

const SIZE := Vector2(20, 14)
const ANGLE := 0.5


func describe() -> Dictionary:
	return {
		"name": "The draw cache's uvs follow a changed ring size",
		"description": "An undented round part drawn again after the ring's point count changed "
			+ "has one uv per vertex, the same as a plain draw.",
		"tags": ["draw", "character", "cache"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))
	s.set_static(BodyDrawCache, &"enabled", true)
	s.set_static(PhysicsDeformConfig, &"circle_points", 44)


func run(t: TestContext) -> void:
	var cache := BodyDrawCache.new()
	var none := []
	var first := cache.polygon(SIZE, none)
	t.require(first.size() == 44, "premise: the ring has 44 points (%d)" % first.size())
	var before := cache.uvs(first, SIZE, none, ANGLE)
	t.expect_eq(before.size(), first.size(), "44 points: one uv per vertex")
	PhysicsDeformConfig.circle_points = 30
	var poly := cache.polygon(SIZE, none)
	t.require(poly.size() == 30, "premise: the ring has 30 points now (%d)" % poly.size())
	var after := cache.uvs(poly, SIZE, none, ANGLE)
	t.expect_eq(after.size(), poly.size(), "30 points: one uv per vertex")
	t.check(after == Deformation.texture_uvs(poly, SIZE, ANGLE), "the uvs equal a plain draw's")
