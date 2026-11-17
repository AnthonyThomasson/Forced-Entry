extends GameTest
## How far below the pavement a spot of the street lies in the 3D render (#193, Objects'
## `StreetGround`): a road floor (a `Floor` of art `street` whose kind is not the sidewalk) lies
## `ObjectStreetMeshConfig.kerb` px lower over its whole rect, as `StreetMesh` shows it; the
## sidewalk, a floor of another art and a spot off every rect lie at 0. Asserted at the seam Main
## uses: `refresh` over a world's floors and `offset_at`.

const SCRATCH := "user://settings_street_ground_test.json"


func describe() -> Dictionary:
	return {
		"name": "The road lies a kerb lower than the pavement and the floors",
		"description": "StreetGround answers the kerb's drop on a road rect and 0 on a sidewalk, "
			+ "another floor or off the street, and sees a floor added later after a refresh.",
		"tags": ["objects", "3d", "render", "street"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.von_script([])


func run(t: TestContext) -> void:
	var ground := StreetGround.new()
	ground.refresh(t.world)
	var arena_roads := ground.roads()
	_floor(t, "street", {}, Rect2(2000, 0, 300, 200))
	_floor(t, "street", { "kind": "asphalt" }, Rect2(2000, 400, 300, 100))
	_floor(t, "street", { "kind": "sidewalk" }, Rect2(2000, 600, 300, 100))
	_floor(t, "wood", {}, Rect2(3000, 0, 300, 200))
	t.expect_eq(ground.offset_at(Vector2(2100, 100)), 0.0, "not before a refresh")
	ground.refresh(t.world)
	var drop := -ObjectStreetMeshConfig.kerb
	t.expect_eq(ground.roads(), arena_roads + 2, "two roads, not the sidewalk or the wood")
	t.expect_eq(ground.offset_at(Vector2(2100, 100)), drop, "a road is a kerb lower")
	t.expect_eq(ground.offset_at(Vector2(2299, 199)), drop, "to its far corner")
	t.expect_eq(ground.offset_at(Vector2(2100, 450)), drop, "an asphalt floor too")
	t.expect_eq(ground.offset_at(Vector2(2300.5, 100)), 0.0, "not past its edge")
	t.expect_eq(ground.offset_at(Vector2(2100, 650)), 0.0, "the sidewalk is the pavement")
	t.expect_eq(ground.offset_at(Vector2(3100, 100)), 0.0, "another floor is level")
	t.expect_eq(ground.offset_at(Vector2(-500, -500)), 0.0, "and off every rect, level")


## A floor of `art` with `opts` over `rect`, in the group the mirror finds floors by.
func _floor(t: TestContext, art: String, opts: Dictionary, rect: Rect2) -> void:
	var node := FakeFloor.new()
	node.art = art
	node.art_opts = opts
	node.size = rect.size
	node.add_to_group(&"floors")
	t.world.add_child(node)
	node.global_position = rect.position


## A floor as the mirror reads one: its `art`, `art_opts` and `size`, in the group `floors`.
class FakeFloor extends Node2D:
	var art := ""
	var art_opts := {}
	var size := Vector2.ZERO
