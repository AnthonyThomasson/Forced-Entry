extends GameTest
## Look showroom of #193 (the isometric 3D render), a sandbox to play: you are the player in one
## furnished room seen as 3D from an orthographic isometric camera. Walk it (WASD, relative to the
## screen) and hold Q / E to turn the camera. The on-screen Previous / Next buttons step through
## the sets: raw 3D first, then the pixel post A at the three pitches (35.3 true isometric,
## 30, 26.6 dimetric), then posts B and C at 35.3. The 2D world is still there, hidden, and the
## 3D view mirrors it as proxy boxes and a capsule; nothing is asserted.

const IsoStage := preload("res://sandboxes/showroom/iso_render/iso_stage.gd")
const ROOM := Rect2(0, 0, 1000, 640)
## Piece heights by the node name's start (3D units).
const HEIGHTS := {
	"shelving": 92.0, "tool_chest": 46.0, "sofa": 38.0, "armchair": 40.0, "dining_table": 40.0,
	"coffee_table": 26.0, "chair": 34.0, "workbench": 48.0, "bench": 30.0,
}


func describe() -> Dictionary:
	return {
		"name": "Isometric 3D render look (#193)",
		"description": "One room in 3D from an orthographic isometric camera: WASD walks, hold "
			+ "Q / E to turn, Previous / Next step through camera pitches and pixel posts.",
		"tags": ["sandbox", "showroom", "3d", "render", "isometric"],
		"manual": true,
	}


func configure(s: TestSetup) -> void:
	s.arena(ROOM, { "floor": "oak_planks" })
	s.switch(&"lighting.enabled", false)
	s.switch(&"nav.rebake", false)
	s.actor(&"you", &"player", Vector2(520, 400), { "start_slot": 3 })
	s.object(&"dining_table", "dining_table", Vector2(300, 220))
	s.object(&"chair_n", "chair", Vector2(300, 150))
	s.object(&"chair_s", "chair", Vector2(300, 290))
	s.object(&"sofa", "sofa", Vector2(720, 120))
	s.object(&"armchair", "armchair", Vector2(880, 200))
	s.object(&"coffee_table", "coffee_table", Vector2(720, 230))
	s.object(&"shelving", "shelving", Vector2(960, 420))
	s.object(&"tool_chest", "tool_chest", Vector2(120, 540))
	s.object(&"workbench", "workbench", Vector2(260, 590))
	s.camera_follow([&"you"])


func run(t: TestContext) -> void:
	var stage := IsoStage.new()
	t.world.add_child(stage)
	stage.setup(t.world, t.actor(&"you"), HEIGHTS)
