extends GameTest
## `PieceHeights`: every catalogue piece has a real top (and base, where it hangs or stands over
## the head), in real sizes at 42.3 px a metre, and its 3D mesh agrees with it (the mesh sizes are
## the one truth: `docs/research/3d-cover-heights.md`). `REAL` holds the range of metres each
## kind's top may be (retail and design guides, ANSUR II for the people they are made for); a new
## catalogue kind with no row, or a mesh retuned off its real size, fails here. The mesh of each
## piece is built in a world and its solids' top must be the part's top (a prop on top, a bowl on
## a bar or a coat rack's hat, is `PROPS`).

const MainProbe := preload("res://tests/_main/main_probe.gd")
const SCRATCH := "user://settings_piece_heights_test.json"
## The range (metres) of each kind's top: a sofa's back, a bar's counter, a tower's awning.
const REAL := {
	&"tv": [0.5, 0.9], &"sofa": [0.8, 1.0], &"coffee_table": [0.4, 0.5], &"rug": [0.0, 0.03],
	&"toilet": [0.7, 0.85], &"bathtub": [0.4, 0.6], &"shower": [1.8, 2.1],
	&"towel_rack": [
		0.9,
		1.3,
	], &"linen_shelf": [
		1.0,
		1.6,
	], &"bath_mat": [0.0, 0.03], &"rug_large": [0.0, 0.03], &"runner": [0.0, 0.03],
	&"bed": [0.75, 1.2], &"wardrobe": [1.7, 2.1], &"dresser": [0.8, 1.1],
	&"workbench": [0.85, 0.95], &"shelving": [1.7, 2.1], &"tool_chest": [0.8, 1.1],
	&"chair": [0.8, 1.0], &"lamp": [1.4, 1.7], &"plant": [0.6, 1.2], &"armchair": [0.8, 1.0],
	&"side_table": [0.45, 0.6], &"bookshelf": [1.7, 2.0], &"coat_rack": [1.6, 1.9],
	&"shoe_rack": [0.4, 0.7], &"sink": [0.85, 1.15], &"cabinet": [0.8, 1.0],
	&"nightstand": [0.5, 0.7], &"desk": [0.7, 0.8], &"washing_machine": [0.8, 0.95],
	&"dryer": [0.8, 0.95], &"bench": [0.4, 0.5], &"console_table": [0.7, 0.85],
	&"mirror": [1.7, 2.0], &"trash": [0.0, 0.4], &"cables": [0.0, 0.05],
	&"cable_nest": [0.0, 0.05], &"cardboard": [0.0, 0.15], &"puddle": [0.0, 0.01],
	&"neon_tube": [0.0, 0.1], &"streetlight": [3.0, 8.0], &"street_sign": [3.0, 8.0],
	&"awning": [2.1, 2.5], &"glyph_sign": [2.1, 2.5], &"office_chair": [0.9, 1.1],
	&"filing_cabinet": [1.2, 1.4], &"kitchen_counter": [0.88, 1.15], &"stove": [0.85, 1.0],
	&"fridge": [1.7, 1.9], &"dining_table": [0.72, 0.78], &"table": [0.72, 0.78],
	&"island": [0.88, 1.15], &"microwave": [0.4, 0.6], &"kitchenette_counter": [0.85, 1.15],
	&"hotplate": [0.3, 0.55], &"mini_fridge": [0.8, 1.0], &"laundry_sink": [0.85, 1.15],
	&"monitor_wall": [1.3, 1.7], &"recliner_rig": [0.65, 1.1], &"server_rack": [1.8, 2.1],
	&"noodle_counter": [0.9, 1.25], &"bar_stool": [0.6, 0.75], &"noodle_booth": [1.0, 1.3],
	&"menu_board": [1.7, 2.0], &"surgical_chair": [0.7, 1.1], &"tool_cart": [0.8, 0.95],
	&"cyberware_shelf": [1.4, 1.8], &"barricade": [0.8, 1.0], &"scanner_post": [1.9, 2.1],
	&"lockers": [1.7, 1.9], &"shop_counter": [0.9, 1.15], &"shelf_aisle": [1.2, 1.5],
	&"drinks_fridge": [1.8, 2.0], &"snack_machine": [1.7, 1.9], &"crate_stack": [0.6, 1.0],
	&"wrapped_pallet": [0.9, 1.3], &"wall_safe": [0.5, 1.0], &"vending_machine": [1.7, 1.95],
	&"street_bench": [0.4, 0.5], &"street_bin": [0.85, 1.05], &"drain_grate": [0.0, 0.03],
	&"litter": [0.0, 0.1], &"podium": [1.3, 1.7], &"rebar": [0.0, 0.4], &"rubble": [0.1, 0.5],
	&"scaffold": [0.0, 0.5], &"cement_bags": [0.1, 0.6], &"wall_stain": [1.5, 2.3],
	&"car": [1.35, 1.55],
}
## Where a piece that hangs or stands over the head starts (metres), and none for a piece on the
## floor: a mirror and a menu board hang on the wall, an awning and a hanging sign clear a head.
const BASE := {
	&"mirror": [1.0, 1.2], &"menu_board": [1.0, 1.2], &"awning": [1.85, 2.4],
	&"glyph_sign": [1.8, 2.4], &"towel_rack": [0.45, 0.6],
}
## What a mesh stands over the part's top by (px): a bowl on the bar, a pot's broth, a till, a coat
## rack's hat, a rack's LEDs, the tap of a bath or a basin.
const PROPS := {
	&"coat_rack": 4.5, &"sink": 2.5, &"trash": 3.0, &"stove": 1.5, &"toilet": 1.5,
	&"bathtub": 6.5, &"shower": 4.5, &"laundry_sink": 2.5, &"server_rack": 3.5,
	&"tool_cart": 1.5, &"kitchenette_counter": 2.5, &"hotplate": 4.5,
	&"shop_counter": 13.0, &"noodle_counter": 11.5, &"crate_stack": 1.5, &"cement_bags": 2.8,
}
## What is built as cover: the pieces a ducked character is meant to hide behind.
const COVER := [
	"barricade", "crate_stack", "wrapped_pallet", "lockers", "kitchen_counter", "shop_counter",
	"noodle_counter", "island", "kitchenette_counter", "sofa", "dresser", "cabinet",
	"shelf_aisle", "wardrobe", "bookshelf", "fridge", "wall_safe", "vending_machine",
	"drinks_fridge", "snack_machine", "server_rack", "shelving", "tool_chest", "stove",
]
## The pieces whose top is a scatter (trash, rubble) or leans (a plant's leaf, a chair's back): the
## slack (px) of the part's top.
const LOOSE := { &"plant": 0.3, &"office_chair": 0.3, &"trash": 3.0, &"rubble": 1.0 }
const CELL := Vector2(300.0, 260.0)
const PER_ROW := 11


func describe() -> Dictionary:
	return {
		"name": "Every catalogue piece has a real top height and its mesh agrees",
		"description": "PieceHeights gives each catalogue kind its top (and base) in px; each is "
			+ "within the real size of the thing in metres at 42.3 px a metre, a multi-part "
			+ "piece names its parts, and the built mesh's solids top out at the part's top.",
		"tags": ["heights", "furniture", "meshkit", "3d", "cover"],
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	s.own_picture()
	var kinds := _kinds()
	var rows := ceili(float(kinds.size()) / PER_ROW)
	s.arena(Rect2(0, 0, CELL.x * PER_ROW, CELL.y * rows + 100.0))
	var at := Vector2(150.0, 150.0)
	for key: String in kinds:
		s.object(StringName(key), key, at)
		at.x += CELL.x
		if at.x > CELL.x * PER_ROW - 100.0:
			at = Vector2(150.0, at.y + CELL.y)
	s.set_static(RenderConfig, &"unit", 1.0)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.von_script([])


func run(t: TestContext) -> void:
	_every_kind_has_a_real_top(t)
	_parts(t)
	_the_scale(t)
	_cover_clears_a_duck(t)
	await t.frames(5)
	var mirror := _mirror(t)
	ObjectMeshes.register(mirror.builders)
	ObjectMeshes.track(mirror)
	mirror.mirror(t.world)
	await t.frames(3)
	for key: String in _kinds():
		var rig := _rig_of(mirror, t.object(StringName(key)))
		if t.require(rig != null, "%s is shown by a rig of its own" % key):
			_mesh_agrees(t, key, rig)


## Every catalogue key with a footprint (a piece), in catalogue order.
func _kinds() -> Array:
	var out: Array = []
	for key: String in ObjectDefinitions.keys():
		if ObjectDefinitions.get_definition(key).has("size"):
			out.append(key)
	return out


## A kind has a real top: inside the metres a thing of that name stands, and starts where it hangs.
func _every_kind_has_a_real_top(t: TestContext) -> void:
	for key: String in _kinds():
		var id := StringName(key)
		var def := ObjectDefinitions.get_definition(key)
		if not t.require(REAL.has(id), "%s has a real height range in the test" % key):
			continue
		var top := PieceHeights.top_of(def)
		var metres := BodyHeights.metres(top)
		var range_m: Array = REAL[id]
		t.check(
			metres >= range_m[0] and metres <= range_m[1],
			"%s tops out at %.2f m (%.1f px), a %s is %.2f to %.2f m" % [
				key,
				metres,
				top,
				key,
				range_m[0],
				range_m[1],
			],
		)
		var base := BodyHeights.metres(PieceHeights.base_of(def))
		var base_m: Array = BASE.get(id, [0.0, 0.0])
		t.check(
			base >= base_m[0] - 0.001 and base <= base_m[1],
			"%s starts at %.2f m, not in %s" % [key, base, base_m],
		)
		t.check(top > PieceHeights.base_of(def), "%s has a top over its base" % key)


## Parts: each runs up from its base, sits in the footprint, and the piece's top is the highest;
## a sofa, a bed, a counter and a booth are more than one.
func _parts(t: TestContext) -> void:
	for key: String in _kinds():
		var def := ObjectDefinitions.get_definition(key)
		var parts := PieceHeights.parts_of(def)
		t.check(not parts.is_empty(), "%s has a part" % key)
		var highest := 0.0
		for part: Dictionary in parts:
			var rect: Rect2 = part["rect"]
			t.check(
				part["top"] > part["base"] and part["base"] >= 0.0,
				"%s: a part runs up from its base" % key,
			)
			t.check(
				rect.has_area() and Rect2(0.0, 0.0, 1.0, 1.0).grow(0.001).encloses(rect),
				"%s: a part %s sits in the footprint" % [key, rect],
			)
			highest = maxf(highest, part["top"])
		t.expect_near(
			highest,
			PieceHeights.top_of(def),
			0.001,
			"%s: the top is its highest part" % key,
		)
	_named_parts(t)


## The sofa, the bed, the counter and the booth are made of parts that match real sizes.
func _named_parts(t: TestContext) -> void:
	var sofa := PieceHeights.parts_of(ObjectDefinitions.get_definition("sofa"))
	t.expect_eq(sofa.size(), 4, "a sofa: seat, two arms and a back")
	t.expect_near(sofa[0]["top"], BodyHeights.px(0.43), 1.0, "the sofa's seat is about 0.43 m")
	t.check(
		sofa[3]["top"] > sofa[1]["top"] and sofa[1]["top"] > sofa[0]["top"],
		"seat < arm < back",
	)
	var back: Rect2 = sofa[3]["rect"]
	t.check(back.position.y == 0.0 and back.size.y < 0.5, "the sofa's back is along the rear")
	var bed := PieceHeights.parts_of(ObjectDefinitions.get_definition("bed"))
	t.expect_eq(bed.size(), 2, "a bed: the mattress and the headboard")
	t.check(bed[1]["top"] > bed[0]["top"] * 1.4, "the headboard stands well over the mattress")
	t.expect_near(
		bed[0]["top"], BodyHeights.px(0.55), BodyHeights.px(0.1), "the mattress is about 0.55 m up"
	)
	var counter := PieceHeights.parts_of(ObjectDefinitions.get_definition("kitchen_counter"))
	t.expect_eq(counter.size(), 2, "a counter: the top and the backsplash")
	t.expect_near(
		counter[0]["top"],
		BodyHeights.px(0.9),
		BodyHeights.px(0.04),
		"a counter is 0.9 m",
	)
	t.expect_eq(
		PieceHeights.parts_of(ObjectDefinitions.get_definition("noodle_booth")).size(),
		5,
		"a booth: two seats, two backs and the table",
	)


## Low cover is about 0.9 m and hides a duck, not a standing body; walls (96 px) and doors (84) are
## unchanged and an awning or a hanging sign clears a standing head.
func _the_scale(t: TestContext) -> void:
	var counter := PieceHeights.parts_of(ObjectDefinitions.get_definition("kitchen_counter"))
	var cover: float = counter[0]["top"]
	t.check(
		BodyHeights.head_top(BodyHeights.DUCK) < cover,
		"a kitchen counter's top hides a ducked head",
	)
	t.check(
		BodyHeights.muzzle(BodyHeights.DUCK) < cover,
		"a counter blocks a ducked muzzle line",
	)
	t.check(
		BodyHeights.muzzle(BodyHeights.FIRE_OVER) > cover,
		"a risen muzzle clears a counter's top",
	)
	t.expect_eq(MirrorConfig.wall_height, 96.0, "walls stay 96")
	t.expect_eq(MirrorConfig.door_height, 84.0, "doors stay 84")
	for key: String in ["awning", "glyph_sign"]:
		t.check(
			PieceHeights.base_of(ObjectDefinitions.get_definition(key))
			> BodyHeights.head_top(BodyHeights.STAND),
			"%s clears a standing head" % key,
		)


## The mesh's solids start at the part's base and top out at its top (a prop on top allowed).
func _mesh_agrees(t: TestContext, key: String, rig: FurnitureRig) -> void:
	var piece := t.object(StringName(key))
	var spec := FurnitureSpec.of(piece)
	var top := PieceHeights.top_of_spec(spec)
	var base := PieceHeights.base_of_spec(spec)
	var box := rig.body.mesh.get_aabb()
	var props: float = PROPS.get(StringName(key), 0.0)
	if key == "surgical_chair":
		props = ObjectMeshChairConfig.recliner_lamp_height - top
	t.check(
		box.end.y >= top - 0.6 and box.end.y <= top + props + 0.6,
		"%s: the mesh tops out at %.1f, PieceHeights says %.1f (+%.1f props)"
		% [key, box.end.y, top, props],
	)
	if base > 0.0:
		t.expect_near(box.position.y, base, 0.7, "%s: the mesh starts at its base" % key)
	var mesh := rig.body.mesh as ArrayMesh
	var parts := PieceHeights.parts(spec)
	for part: Dictionary in parts:
		_part_is_in_the_mesh(t, key, part, spec, mesh)
	if key == "surgical_chair":
		t.expect_near(
			box.end.y,
			ObjectMeshChairConfig.recliner_lamp_height,
			0.7,
			"the surgical chair's lamp arm (a prop, not its mass) is its mesh's top",
		)


## A solid has a face at `part`'s top over its rect (px, from the footprint's back-left corner,
## the mesh centred on the piece; with the overhang for a piece that has one): the part is in the
## mesh where PieceHeights says it is, and the faces at that height lie in the parts that top out
## there. `LOOSE` pieces are scattered or leaning, their top within a little of the part's.
func _part_is_in_the_mesh(
	t: TestContext, key: String, part: Dictionary, spec: FurnitureSpec, mesh: ArrayMesh
) -> void:
	var slack: float = LOOSE.get(StringName(key), 0.05)
	var area := _area_of(part, spec)
	var found := false
	var strays := 0
	for i in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		for v: Vector3 in vertices:
			if absf(v.y - float(part["top"])) > slack:
				continue
			if area.has_point(Vector2(v.x, v.z)):
				found = true
			elif not _in_a_part_of_that_top(v, part["top"], spec, slack):
				strays += 1
	t.check(found, "%s: a solid tops out at %.1f over %s" % [key, part["top"], area])
	t.expect_eq(
		strays, 0, "%s: no face at %.1f outside the parts that top out there" % [key, part["top"]]
	)


## Where `part` lies (px, in the mesh's frame, slack 0.6 round it): its share of the footprint,
## merged with the piece's overhang when it has one.
func _area_of(part: Dictionary, spec: FurnitureSpec) -> Rect2:
	var rect: Rect2 = part["rect"]
	var area := Rect2(rect.position * spec.size - spec.size * 0.5, rect.size * spec.size)
	if spec.overhang.has_area():
		area = area.merge(spec.overhang.abs())
	return area.grow(0.6)


## Whether `v` (a mesh vertex) is over a part of `spec` that tops out at `top`.
func _in_a_part_of_that_top(v: Vector3, top: float, spec: FurnitureSpec, slack: float) -> bool:
	for part: Dictionary in PieceHeights.parts(spec):
		if absf(float(part["top"]) - top) <= slack:
			if _area_of(part, spec).has_point(Vector2(v.x, v.z)):
				return true
	return false


## Cover clears a ducked head by a real margin (0.04 m): what a piece is built as cover for (a
## barricade, a counter, a sofa, a stack of crates, a locker) hides a duck, and no solid piece on
## the floor tops out within that margin of the duck's head, either way, so no piece hides or leaves
## a head by a hair.
func _cover_clears_a_duck(t: TestContext) -> void:
	var head := BodyHeights.head_top(BodyHeights.DUCK)
	var margin := BodyHeights.px(0.04)
	for key: String in COVER:
		var top := PieceHeights.top_of(ObjectDefinitions.get_definition(key))
		t.check(
			top >= head + margin,
			"%s (%.1f px) hides a duck (head %.1f) by at least %.1f px" % [key, top, head, margin],
		)
	for key: String in _kinds():
		var def := ObjectDefinitions.get_definition(key)
		if def.get("solid", true) == false or PieceHeights.base_of(def) > 1.0:
			continue
		var top := PieceHeights.top_of(def)
		t.check(
			absf(top - head) >= margin,
			"%s's top %.1f is not within %.1f px of a duck's head %.1f" % [key, top, margin, head],
		)


## The rig of `body` when the mirror shows it by one (a `FurnitureRig`), else null (a proxy box).
func _rig_of(mirror: WorldMirror, body: Node) -> FurnitureRig:
	var shown := mirror.proxies_of(body)
	if shown.size() != 1 or not shown[0] is FurnitureRig:
		return null
	return shown[0] as FurnitureRig


func _mirror(t: TestContext) -> WorldMirror:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	return mirror
