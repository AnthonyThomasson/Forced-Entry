extends GameTest
## The showroom for the downtown district ticket: you are the player in a staging room, one set at
## a time (Previous / Next along the bottom of the screen). Each set shows today's version where
## one exists beside variants A / B / C, each with a floor caption, at game zoom beside the real
## floors, walls, lamps and furniture it will sit among. Nothing is asserted.

const SetStage := preload("res://sandboxes/showroom/downtown_district/set_stage.gd")


func describe() -> Dictionary:
	return {
		"name": "Downtown district showroom",
		"description": "Player-controlled showroom, one set at a time (Previous / Next at the "
			+ "bottom of the screen): the WIP ELEVATOR LOBBY floor stencil, the tower's shadow, "
			+ "the podium band, awnings and signs (one fades while anyone walks under it), the "
			+ "roofless shell interiors, the crosswalk and junction, road glyphs, sidewalk "
			+ "clutter, and the shop, noodle bar and stockroom pieces. Each exhibit is today's "
			+ "version (where one exists) beside variants A / B / C, captioned on the floor. WASD "
			+ "to walk.",
		"tags": ["sandbox", "showroom", "worldgen", "art", "downtown", "street", "tower"],
		"manual": true,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 2200, 840), { "floor": "concrete" })
	# the exhibits are anchored and swapped as a set; nothing should re-bake the nav map
	s.switch(&"nav.rebake", false)
	# the dusk, lifted so an exhibit's detail reads (the pieces spawned per set add no lights)
	s.set_static(LightingConfig, &"ambient_color", Color(0.66, 0.62, 0.82))
	s.actor(&"you", &"player", Vector2(SetStage.CENTRE_X, 740), { "start_slot": 2 })
	# the character the awning set walks under its awning, parked until then
	s.actor(&"walker", &"puppet", SetStage.WALKER_PARK, { "start_slot": 2 })
	s.camera_follow([&"you"])


## Add the stage, which stages the first set and owns the rest.
func run(t: TestContext) -> void:
	var stage := SetStage.new()
	stage.name = "SetStage"
	t.world.add_child(stage)
