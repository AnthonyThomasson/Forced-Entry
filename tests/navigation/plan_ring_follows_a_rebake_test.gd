extends GameTest
## The district's planning ring is re-baked with its planning map (#182): a piece of furniture
## shoved in the match building is carved out of both, from the same updater tick, so the ring's
## answers go on matching the district map's. A point where the piece stood is floor again on
## both, and a point where it stands now is off the floor on both.

const SEED := 7
const SHOVE := Vector2(0, 130)
## How near (px) the ring's snap is to the district map's.
const SAME := 3.0
## How long (sim s) a re-bake may take to land: the bake runs on the server's worker thread in real
## time, and a headless run's frames are far shorter than that.
const WAIT := 12.0


func describe() -> Dictionary:
	return {
		"name": "A district's planning ring is re-baked with its planning map",
		"description": "A chair in the match building is shoved; the ring and the district map "
			+ "both carve it where it now stands and both free the floor it left.",
		"tags": ["navigation", "district", "rebake"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED)
	s.switch(&"nav.rebake", true)


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var region: NavigationRegion2D = t.world.find_children(
		"NavRegion", "NavigationRegion2D", true, false,
	)[0]
	var map := region.get_navigation_map()
	var small := NavRing.region_of(region)
	if not t.require(small != null and NavBuilder.ready(map), "premise: the ring is baked"):
		return
	var piece := _solid_piece(t)
	if not t.require(piece != null, "premise: the match building has a solid piece"):
		return
	var old_spot := piece.global_position
	var new_spot := old_spot + SHOVE
	if not t.require(
		NavRing.map_for(map, [old_spot, new_spot]) == NavRing.map_of(map),
		"premise: both spots are inside the ring",
	):
		return
	var held_planning := region.navigation_polygon
	var held_ring := small.navigation_polygon
	piece.global_position = new_spot
	t.check(
		await t.until(func() -> bool: return region.navigation_polygon != held_planning, WAIT),
		"the planning region is re-baked after the shove",
	)
	t.check(
		await t.until(func() -> bool: return small.navigation_polygon != held_ring, WAIT),
		"the ring is re-baked after the shove",
	)
	await t.seconds(0.3)  # the maps take the new meshes in
	for spot in [old_spot, new_spot]:
		t.check(
			NavBuilder.snap(
				map,
				spot,
			).distance_to(NavigationServer2D.map_get_closest_point(map, spot))
				<= SAME,
			"%s: the ring snaps it as the district map does" % str(spot.round()),
		)
	t.check(
		NavBuilder.snap(map, old_spot).distance_to(old_spot) <= SAME,
		"the floor the piece left is floor again",
	)


## A furniture piece of the match building that carves a hole: a rigid body with a collider.
func _solid_piece(t: TestContext) -> RigidBody2D:
	for body in t.world.house.find_children("*", "RigidBody2D", true, false):
		if not body.find_children("*", "CollisionShape2D", true, false).is_empty():
			return body
	return null
