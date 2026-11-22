extends RefCounted
## (An oracle: `noodle_mesh.gd` of commit 08f43a10, the old look #194 unbake-c keeps.
## Only tests read it (`old_shop_pieces.gd`); nothing in scenes/ does.)
## Objects domain, the 3D mesh of the noodle bar's pieces (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `noodle_painter.gd`'s
## proportions, in grimy steel, by `kind`. `bar` is a long counter with steaming pots along it and
## bowls at one end; `stool` a round seat on a post; `booth` a bench along each long side with a
## back, a table between them and a bowl at each seat; `menu` a board hung thin against the wall at
## the back of its footprint, its lines of text and its three characters, each lit pixel a glowing
## block (two glow nodes: the first and the second line's colours, no real light).

const OPTIONS := [
	"kind", "top_color", "accent_color", "wood_color", "broth_color", "bowl_color", "menu_color",
	"menu_color_2", "height",
]
const COLOURS := [
	"top_color", "accent_color", "wood_color", "broth_color", "bowl_color", "menu_color",
	"menu_color_2",
]
const HANZI := ["大", "中", "王"]
## How far a feature stands proud of the face it is laid on, and how big one lit pixel of text is
## on the board (its width, and its height per art px).
const PROUD := 0.5
const PIXEL := 1.0


## The node a noodle-bar `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"noodle", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if _kind(spec) == "menu":
		rig.hangs_on_wall = true
		for second in [false, true]:
			var glow := FurnitureMesh.fetch_glow(
				"noodle_%s" % second, spec, tuning, func() -> Mesh: return _lines(spec, second)
			)
			rig.add_glow(glow, _menu_colour(spec, second), ObjectMeshStateConfig.neon_strength)
	return rig


## The kind the piece is: its `art_opts.kind`, else the painter's.
static func _kind(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", "bar"))


## The painter's colour option `name` of the piece, else its holder default.
static func _colour(spec: FurnitureSpec, name: String) -> Color:
	var colours: Array[Color] = ObjectArtShopConfig.noodle_menu_colors
	var defaults := {
		"top_color": ObjectArtShopConfig.noodle_top_color,
		"accent_color": ObjectArtShopConfig.noodle_accent_color,
		"wood_color": ObjectArtShopConfig.noodle_wood_color,
		"broth_color": ObjectArtShopConfig.noodle_broth_color,
		"bowl_color": ObjectArtShopConfig.noodle_bowl_color,
		"menu_color": colours[0],
		"menu_color_2": colours[1],
	}
	return spec.opts.get(name, defaults[name])


## The colour of the menu's first (`RAMEN`) or second (`UDON`, the characters) line.
static func _menu_colour(spec: FurnitureSpec, second: bool) -> Color:
	return _colour(spec, "menu_color_2") if second else _colour(spec, "menu_color")


## How tall the piece stands: its `art_opts.height`, else its kind's (a menu board: the top of its
## board).
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	match _kind(spec):
		"stool":
			return ObjectMeshNoodleConfig.stool_height
		"booth":
			return ObjectMeshNoodleConfig.booth_back
		"menu":
			return ObjectMeshNoodleConfig.menu_base + ObjectMeshNoodleConfig.menu_height
	return ObjectMeshNoodleConfig.bar_height


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	var out := {
		"opts": spec.read(OPTIONS),
		"height": height_of(spec),
		"bar": ObjectMeshNoodleConfig.bar_height,
		"stool": ObjectMeshNoodleConfig.stool_height,
		"seat": ObjectMeshNoodleConfig.booth_seat,
		"table": ObjectMeshNoodleConfig.table_height,
		"menu": [ObjectMeshNoodleConfig.menu_base, ObjectMeshNoodleConfig.menu_height],
		"depth": ObjectMeshNoodleConfig.menu_depth,
	}
	for name: String in COLOURS:
		out[name] = _colour(spec, name)
	return out


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	match _kind(spec):
		"stool":
			_stool(spec, kit)
		"booth":
			_booth(spec, kit)
		"menu":
			_board(spec, kit)
		_:
			_bar(spec, kit)
	return kit.build()


## The bar: the steel body and top, the lip, three pots with their broth and three bowls.
static func _bar(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var base := spec.color
	var broth := _colour(spec, "broth_color")
	kit.box(MeshKit.volume(spec.area(0, 0, w, d), 0.0, height), base, _colour(spec, "top_color"))
	kit.box(
		MeshKit.volume(spec.area(3, d - 6.0, w - 6.0, 2), height, 1.0),
		_colour(spec, "accent_color"),
	)
	for x: float in [18.0, 52.0, 86.0]:
		if x + 8.0 > w:
			continue
		var at := Vector2(x, minf(12.0, d - 9.0)) - spec.half()
		kit.cylinder(
			Vector3(at.x, height, at.y),
			8.0,
			11.0,
			base.darkened(0.4),
			Color(0.55, 0.56, 0.58),
		)
		kit.cylinder(Vector3(at.x, height + 10.8, at.y), 4.0, 0.4, broth.darkened(0.2))
	for x: float in [112.0, 124.0, 136.0]:
		if x + 5.0 > w:
			continue
		var at := Vector2(x, minf(20.0, d - 6.0)) - spec.half()
		kit.cylinder(Vector3(at.x, height, at.y), 5.0, 5.0, _colour(spec, "bowl_color"))
		kit.cylinder(Vector3(at.x, height + 4.8, at.y), 3.0, 0.4, broth)


## The stool: a disc foot, a post and a seat of wood in a steel rim.
static func _stool(spec: FurnitureSpec, kit: MeshKit) -> void:
	var radius := floorf(spec.size.x / 2.0) - 1.0
	var height := height_of(spec)
	var base := spec.color
	kit.cylinder(Vector3.ZERO, radius * 0.7, 1.5, base.darkened(0.4))
	kit.cylinder(Vector3(0, 1.5, 0), 2.0, height - 5.0, base.darkened(0.4))
	kit.cylinder(
		Vector3(0, height - 3.5, 0),
		radius,
		3.5,
		base.darkened(0.3),
		_colour(spec, "wood_color"),
	)
	kit.cylinder(Vector3(0, height - 3.5, 0), radius - 2.0, 3.8, _colour(spec, "wood_color"))


## The booth: a bench along each long side with a back at the outer edge, the table between, a bowl
## in front of each seat.
static func _booth(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var base := spec.color
	for y: float in [0.0, d - 18.0]:
		kit.box(
			MeshKit.volume(spec.area(0, y, w, 18), 0.0, ObjectMeshNoodleConfig.booth_seat),
			MeshKit.tone(base, &"dark"),
			base,
		)
		var back_y := y if y == 0.0 else d - 4.0
		kit.box(
			MeshKit.volume(spec.area(0, back_y, w, 4), 0.0, ObjectMeshNoodleConfig.booth_back),
			base,
			base.lightened(0.08),
		)
	var table := Rect2(8, 22, w - 16.0, d - 44.0)
	var top_at := ObjectMeshNoodleConfig.table_height
	kit.box(
		MeshKit.volume(
			spec.area(table.position.x, table.position.y, table.size.x, table.size.y),
			top_at - 3.0,
			3.0,
		),
		base.darkened(0.2),
		_colour(spec, "top_color"),
	)
	var mid := table.position.y + table.size.y / 2.0
	var post := Vector2(w / 2.0, d / 2.0) - spec.half()
	kit.cylinder(Vector3(post.x, 0, post.y), 3.0, top_at - 3.0, base.darkened(0.4))
	for x: float in [30.0, 70.0]:
		if x + 6.0 > w:
			continue
		var at := Vector2(x, mid) - spec.half()
		kit.cylinder(Vector3(at.x, top_at, at.y), 6.0, 3.0, _colour(spec, "bowl_color"))
		kit.cylinder(Vector3(at.x, top_at + 2.8, at.y), 4.0, 0.4, _colour(spec, "broth_color"))


## The menu board: a thin slab at the back of the footprint, dark, framed with a lit border.
static func _board(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rect := spec.area(2, 0, spec.size.x - 4.0, ObjectMeshNoodleConfig.menu_depth)
	kit.box(
		MeshKit.volume(rect, ObjectMeshNoodleConfig.menu_base, ObjectMeshNoodleConfig.menu_height),
		spec.color.darkened(0.35),
	)


## A lit mark `at` (art px from the board's top-left, 2D) `w` by `h` px, as a block standing
## proud of the board's face: its horizontal place is the 2D one, the vertical runs down from the
## board's top.
static func _mark(
	spec: FurnitureSpec,
	kit: MeshKit,
	at: Vector2,
	size: Vector2,
	colour: Color,
) -> void:
	var scale := ObjectMeshNoodleConfig.menu_height / maxf(1.0, spec.size.y)
	var top := ObjectMeshNoodleConfig.menu_base + ObjectMeshNoodleConfig.menu_height
	var rect := spec.area(at.x, ObjectMeshNoodleConfig.menu_depth, size.x, PROUD)
	var height := maxf(0.5, size.y * scale)
	kit.box(MeshKit.volume(rect, top - at.y * scale - height, height), colour)


## One line of text drawn in the pixel font, a block per lit pixel.
static func _text(
	spec: FurnitureSpec, kit: MeshKit, text: String, at: Vector2i, colour: Color
) -> void:
	for pixel in FurnitureGlyphs.pixels(text):
		_mark(spec, kit, Vector2(at) + pixel * PIXEL, Vector2(PIXEL, PIXEL), colour)


## A character in brush strokes, in a 10 px box at `at`: a block along each stroke.
static func _hanzi(
	spec: FurnitureSpec, kit: MeshKit, character: String, at: Vector2i, colour: Color
) -> void:
	for point in FurnitureGlyphs.strokes(character, 10.0, PIXEL):
		_mark(spec, kit, Vector2(at) + point, Vector2(PIXEL, PIXEL), colour)


## The lit lines: the first colour's (RAMEN, its rule and the frame) or the second's (UDON, the
## characters and its rule).
static func _lines(spec: FurnitureSpec, second: bool) -> Mesh:
	var kit := spec.kit()
	var first := _colour(spec, "menu_color")
	var other := _colour(spec, "menu_color_2")
	var w := spec.size.x
	var h := spec.size.y
	if not second:
		_text(spec, kit, "RAMEN", Vector2i(8, 2), first)
		_mark(spec, kit, Vector2(46, 7), Vector2(12, 1), first)
		for edge: Rect2 in _frame(w, h):
			_mark(spec, kit, edge.position, edge.size, first.darkened(0.2))
	else:
		_text(spec, kit, "UDON", Vector2i(8, 10), other.darkened(0.1))
		for i in HANZI.size():
			_hanzi(spec, kit, HANZI[i], Vector2i(int(w) - 44 + i * 14, 3), other)
		_mark(spec, kit, Vector2(46, 15), Vector2(12, 1), other)
	return kit.build()


## The four bars of the frame round the board's face (art px from the canvas's top-left).
static func _frame(w: float, h: float) -> Array[Rect2]:
	return [
		Rect2(3, 1, w - 6.0, 1),
		Rect2(3, h - 2.0, w - 6.0, 1),
		Rect2(3, 1, 1, h - 2.0),
		Rect2(w - 4.0, 1, 1, h - 2.0),
	]
