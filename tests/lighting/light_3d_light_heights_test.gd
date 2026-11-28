extends GameTest
## #193 phase 3 (L2 in 3D, the height of a light): every kind of light-giving piece hangs its 3D
## light where its glowing part is in the piece's mesh, not at the piece's centre at hand height. A
## piece's `get_lights()` declares the height (`lift`, px above the floor,
## `ObjectArtLightConfig.specs`), `WorldLighting3D` hangs the `OmniLight3D` there, over the declared
## place on the floor: a lamp's bulb over its shade, a screen's face, a rack's LEDs, a street lamp's
## head at the top of its post, a tube on the floor. The declared height of each kind sits inside
## its mesh's own measures (the holders of `ObjectMesh*Config`), so a retuned mesh that leaves its
## light behind fails here.
## It reads (tests/_lighting/lighting_3d_probe.gd) `WorldLighting3D.lights()`, `lights_of`, a
## light's
## position, and a piece's `get_lights()`.

const Probe := preload("res://tests/_lighting/lighting_3d_probe.gd")
const COLUMNS := 4
const GAP := Vector2(260.0, 200.0)

## One piece per kind of light: its catalogue key and the row of `ObjectArtLightConfig.specs` it
## gives light by; `edit` changes the catalogue's piece (a desk's neon trim).
var _cases: Array[Dictionary] = []


func describe() -> Dictionary:
	return {
		"name": "Every kind of light hangs where its glowing part is, not at the piece's centre",
		"description": "A piece of each kind (lamp, TV, monitor item, monitor wall, rack, rig, "
			+ "surgical lamp, tool cart, scanner, fridge, menu board, hotplate, neon tube, street "
			+ "lamp and sign, neon trim): its 3D light stands over its declared place at its "
			+ "declared lift, which is inside the height range of its mesh.",
		"tags": ["lighting", "3d"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 1000))
	s.switch(&"nav.rebake", false)
	_cases = _kinds()
	for i in _cases.size():
		var c: Dictionary = _cases[i]
		var def: Dictionary = WorldGen.object_definition(String(c["key"])).duplicate(true)
		if c.has("opts"):
			def["art_opts"] = c["opts"]
		var at := Vector2(160.0, 140.0) + Vector2(i % COLUMNS, int(i / float(COLUMNS))) * GAP
		s.object(StringName(c["row"]), def, at, { "facing": Vector2.DOWN })


func run(t: TestContext) -> void:
	var lighting := Probe.light(t)
	if lighting == null:
		return
	for c: Dictionary in _cases:
		var row := String(c["row"])
		var piece: Node2D = t.object(StringName(row))
		if not t.require(piece != null, "%s: the piece is placed" % row):
			continue
		var own := Probe.lights_of(lighting, piece)
		if not t.require(own.size() == 1, "%s gives one 3D light (%d)" % [row, own.size()]):
			continue
		_check(t, row, piece, own[0])


## `light` of `piece` (a `row` kind) hangs at its declared lift, over its declared place, and the
## lift is inside the heights the kind's mesh has.
func _check(t: TestContext, row: String, piece: Node2D, light: OmniLight3D) -> void:
	var spec: Dictionary = (piece.call(&"get_lights") as Array)[0]
	var lift := float(spec["lift"])
	t.check(lift > 0.0, "%s declares where its light hangs (lift %.1f)" % [row, lift])
	t.expect_near(
		lift, float(ObjectArtLightConfig.specs[row]["lift"]), 0.001,
		"%s declares its row's lift" % row,
	)
	t.expect_near(
		light.position.y, lift * RenderConfig.unit, 0.01,
		"%s's light hangs at its lift, not at hand height or its kind's" % row,
	)
	var at: Vector2 = piece.global_transform * (spec["offset"] as Vector2)
	t.check(Probe.ground_of(light).distance_to(at) < 0.5, "%s's light is over its place" % row)
	var range_px: Vector2 = _ranges()[row]
	t.check(
		lift >= range_px.x and lift <= range_px.y,
		"%s's lift %.1f is inside its mesh's heights %s" % [row, lift, range_px],
	)


## The heights (px, low and high) the glowing part of each kind has in its mesh, by row.
func _ranges() -> Dictionary:
	var tech := ObjectMeshTechConfig
	var recliner := ObjectMeshChairConfig.recliner_lamp_height
	var crate := ObjectMeshKitchenConfig.hotplate_crate_height
	var post := ObjectMeshOverheadConfig.post_height
	var desk := Vector2(tech.desk_height, tech.desk_height + tech.screen_height)
	return {
		"lamp": Vector2(
			ObjectMeshDecorConfig.lamp_height - ObjectMeshDecorConfig.lamp_shade,
			ObjectMeshDecorConfig.lamp_height,
		),
		"tv": Vector2(0.0, ObjectMeshKitchenConfig.appliance_heights["tv"]),
		"monitor": Vector2(0.0, ObjectMeshItemConfig.monitor_height),
		"monitor_wall": desk,
		"server_rack": Vector2(tech.rack_height * 0.5, tech.rack_height),
		"rig": Vector2(recliner, recliner),
		"surgical": Vector2(recliner, recliner),
		"tool_cart": Vector2(tech.cart_height - 4.0, tech.cart_height + 2.0),
		"scanner": Vector2(tech.scanner_height * 0.4, tech.scanner_height),
		"fridge": Vector2(0.0, ObjectMeshShopConfig.fridge_height),
		"menu_board": Vector2(
			ObjectMeshNoodleConfig.menu_base,
			ObjectMeshNoodleConfig.menu_base + ObjectMeshNoodleConfig.menu_height,
		),
		"hotplate": Vector2(
			crate,
			crate + ObjectMeshKitchenConfig.hotplate_plate_height
				+ ObjectMeshKitchenConfig.hotplate_pan_height,
		),
		"neon_tube": Vector2(0.0, ObjectMeshShellConfig.neon_tube + 1.0),
		"cobra": Vector2(post - ObjectMeshOverheadConfig.head_height - 6.0, post),
		"sign": Vector2(post - ObjectMeshOverheadConfig.head_height - 6.0, post),
		"trim": Vector2(4.0, 30.0),
	}


## One piece per row of `ObjectArtLightConfig.specs`: the catalogue's key, and for a row a catalogue
## piece gives light by only with an option, the `art_opts` to give it.
func _kinds() -> Array[Dictionary]:
	return [
		{ "row": "lamp", "key": "lamp", "opts": { "neon": "" } },
		{ "row": "tv", "key": "tv" },
		{ "row": "monitor", "key": "monitor" },
		{ "row": "monitor_wall", "key": "monitor_wall" },
		{ "row": "server_rack", "key": "server_rack" },
		{ "row": "rig", "key": "recliner_rig" },
		{ "row": "surgical", "key": "surgical_chair" },
		{ "row": "tool_cart", "key": "tool_cart" },
		{ "row": "scanner", "key": "scanner_post" },
		{ "row": "fridge", "key": "drinks_fridge" },
		{ "row": "menu_board", "key": "menu_board" },
		{ "row": "hotplate", "key": "hotplate" },
		{ "row": "neon_tube", "key": "neon_tube" },
		{ "row": "cobra", "key": "streetlight", "opts": { "head": "cobra", "neon": "" } },
		{ "row": "sign", "key": "street_sign", "opts": { "head": "sign" } },
		{ "row": "trim", "key": "desk", "opts": { "neon": "cyan" } },
	]
