class_name PieceHeights
extends RefCounted
## Objects domain, how tall a piece of furniture really is (`docs/research/3d-cover-heights.md`):
## its top height and, where it matters, its parts: a sofa's seat, arms and back, a bed's mattress
## and headboard, a counter's top and backsplash. The numbers are the 3D meshes' own (the
## `ObjectMesh*Config` holders and the painters' rules: `height_of` of each mesh script), so the
## mesh and the height are one truth; a test builds every catalogue piece's mesh and compares.
## Lengths are px above the floor, 1 3D unit = 1 px, 42.3 px a metre (`BodyHeights`).
##
## A part is `{ base, top, rect }`: where it starts and ends above the floor and the share of the
## footprint it covers, `rect` in the footprint's unit square in the painter's canonical frame
## (`FurnitureSpec.area`: back-left corner at (0, 0), x across, the front toward +y). `top_of` is
## the highest part's top: the height of the piece's mass (a bowl on a bar or a coat rack's hat is
## a prop, left out); `base_of` the lowest part's base (a mirror or a menu board hangs at 46 or
## 80; an awning stands over the head).
##
## Read through a catalogue row (`definition`: `size`, `art`, `art_opts`) so the AI and the
## projectile need no piece, or through a live piece's `FurnitureSpec`.

const TableMesh = preload("res://scenes/objects/art/table_mesh.gd")
const SofaMesh = preload("res://scenes/objects/art/sofa_mesh.gd")
const CabinetMesh = preload("res://scenes/objects/art/cabinet_mesh.gd")
const ShelfMesh = preload("res://scenes/objects/art/shelf_mesh.gd")
const CounterMesh = preload("res://scenes/objects/art/counter_mesh.gd")
const ApplianceMesh = preload("res://scenes/objects/art/appliance_mesh.gd")
const NoodleMesh = preload("res://scenes/objects/art/noodle_mesh.gd")
const ClinicMesh = preload("res://scenes/objects/art/clinic_mesh.gd")
const TechMesh = preload("res://scenes/objects/art/tech_mesh.gd")
const SecurityMesh = preload("res://scenes/objects/art/security_mesh.gd")
const ShopMesh = preload("res://scenes/objects/art/shop_mesh.gd")
const StockMesh = preload("res://scenes/objects/art/stock_mesh.gd")
const ItemMesh = preload("res://scenes/objects/art/item_mesh.gd")
const StreetPropMesh = preload("res://scenes/objects/art/street_prop_mesh.gd")
## The whole footprint.
const FULL := Rect2(0.0, 0.0, 1.0, 1.0)


## The `FurnitureSpec` a catalogue row says (its size, art id and options; no colour or facing).
static func spec_of(definition: Dictionary) -> FurnitureSpec:
	var spec := FurnitureSpec.new()
	spec.size = definition.get("size", Vector2.ZERO)
	spec.art = String(definition.get("art", ""))
	var options: Variant = definition.get("art_opts", {})
	spec.opts = options if options is Dictionary else {}
	return spec


## The highest top (px) of the piece a catalogue row says: its mass, in the canonical frame.
static func top_of(definition: Dictionary) -> float:
	var top := 0.0
	for part: Dictionary in parts_of(definition):
		top = maxf(top, part["top"])
	return top


## The lowest base (px) of the piece a catalogue row says: 0 for a piece on the floor.
static func base_of(definition: Dictionary) -> float:
	var parts_list := parts_of(definition)
	return parts_list[0]["base"] if not parts_list.is_empty() else 0.0


## The parts of the piece a catalogue row says, lowest first.
static func parts_of(definition: Dictionary) -> Array[Dictionary]:
	if PieceCarries.carries(definition) and not definition.has("art"):
		return [_part(0.0)]  # A bare place for loose items (a crate stack's, a pallet's): no mass.
	return parts(spec_of(definition))


## The highest top of the parts of `spec`.
static func top_of_spec(spec: FurnitureSpec) -> float:
	var top := 0.0
	for part: Dictionary in parts(spec):
		top = maxf(top, part["top"])
	return top


## The lowest base of the parts of `spec`.
static func base_of_spec(spec: FurnitureSpec) -> float:
	var parts_list := parts(spec)
	var base: float = parts_list[0]["base"] if not parts_list.is_empty() else 0.0
	for part: Dictionary in parts_list:
		base = minf(base, part["base"])
	return base


## The parts of the piece `spec` says (its art id, footprint and options), lowest first; a piece
## whose art has no mesh is one part at the default table height.
static func parts(spec: FurnitureSpec) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match spec.art:
		"sofa":
			out = _sofa(spec)
		"chair":
			out = _chair(spec)
		"bed":
			out = _bed(spec)
		"counter":
			out = _counter(spec)
		"noodle":
			out = _noodle(spec)
		"fixture":
			out = _fixture(spec)
		"bath", "toilet", "office_chair", "recliner", "clinic":
			out = _room(spec)
		"tech", "security", "shop", "stock", "street_prop", "podium", "awning", "streetlight":
			out = _commercial(spec)
		"shelf":
			out = ShelfMesh.hollow_parts(spec) if ShelfMesh.is_loose(spec) else _plain(spec)
		"item":
			out = [_part(ItemMesh.height_of(spec))]
		"shell_decor", "decor", "rug", "plant", "lamp", "coat_rack", "hotplate", "car":
			out = _decor(spec)
		_:
			out = [_part(_height_of(spec))]
	return out


## Whether the piece is thin parts round empty compartments (an emptied shelf), so its body moves
## as the solid box of its extent (`PieceBody`).
static func hollow(spec: FurnitureSpec) -> bool:
	return spec.art == "shelf" and ShelfMesh.is_loose(spec)


## A piece that is one part: the top the mesh script's own `height_of` says.
static func _plain(spec: FurnitureSpec) -> Array[Dictionary]:
	return [_part(_height_of(spec))]


## One part: `base` to `top` over `rect` of the footprint.
static func _part(top: float, base: float = 0.0, rect: Rect2 = FULL) -> Dictionary:
	return { "base": base, "top": top, "rect": rect }


## The share of the footprint that `area` (px from the back-left corner) covers.
static func _share(spec: FurnitureSpec, area: Rect2) -> Rect2:
	var size := Vector2(maxf(spec.size.x, 1.0), maxf(spec.size.y, 1.0))
	return Rect2(area.position / size, area.size / size)


## A table, a cabinet, a shelf, an appliance: the mesh script's own `height_of`.
static func _height_of(spec: FurnitureSpec) -> float:
	match spec.art:
		"table":
			return TableMesh.height_of(spec.size, spec.opts)
		"cabinet":
			return CabinetMesh.height_of(spec)
		"shelf":
			return ShelfMesh.height_of(spec)
		"appliance":
			return ApplianceMesh.height_of(spec)
	return ObjectMeshConfig.table_height


## A sofa: the seat across the whole footprint, a rolled arm at each end, the back along the rear
## between them (the painter's own layout).
static func _sofa(spec: FurnitureSpec) -> Array[Dictionary]:
	var rows := SofaMesh.layout(spec)
	var arm: float = rows["arm"]
	var back: float = rows["back"]
	var arms := ObjectMeshSeatConfig.sofa_arm_height
	var width := spec.size.x
	return [
		_part(ObjectMeshSeatConfig.sofa_seat_height),
		_part(arms, 0.0, _share(spec, Rect2(0.0, 0.0, arm, spec.size.y))),
		_part(arms, 0.0, _share(spec, Rect2(width - arm, 0.0, arm, spec.size.y))),
		_part(
			ObjectMeshSeatConfig.sofa_back_height,
			0.0,
			_share(spec, Rect2(arm, 0.0, width - 2.0 * arm, back)),
		),
	]


## A chair: the seat, and the back along the rear.
static func _chair(spec: FurnitureSpec) -> Array[Dictionary]:
	var depth := clampf(
		roundf(
			spec.size.y * float(spec.opts.get("back_depth", ObjectArtTableConfig.chair_back_depth))
		),
		3.0,
		floorf(spec.size.y / 2.0),
	)
	return [
		_part(ObjectMeshSeatConfig.chair_seat_height),
		_part(
			ObjectMeshSeatConfig.chair_back_height,
			0.0,
			_share(spec, Rect2(0.0, 0.0, spec.size.x, depth)),
		),
	]


## A bed: the mattress over the whole frame, the headboard a strip across the head.
static func _bed(spec: FurnitureSpec) -> Array[Dictionary]:
	return [
		_part(ObjectMeshRoomConfig.bed_mattress_height),
		_part(
			ObjectMeshRoomConfig.bed_headboard_height,
			0.0,
			_share(spec, Rect2(0.0, 0.0, spec.size.x, 4.0)),
		),
	]


## A counter: the body and top at the counter height, the backsplash a strip along the rear.
static func _counter(spec: FurnitureSpec) -> Array[Dictionary]:
	var height := CounterMesh.height_of(spec)
	var splash := CounterMesh.splash_of(spec)
	var out: Array[Dictionary] = [_part(height)]
	if splash > 0.0:
		out.append(
			_part(
				height + ObjectMeshKitchenConfig.counter_splash,
				height,
				_share(spec, Rect2(0.0, 0.0, spec.size.x, splash)),
			)
		)
	return out


## The noodle bar's four: the counter, a stool, a booth (its seats, the backs and the table
## between) and the menu board hung on the wall.
static func _noodle(spec: FurnitureSpec) -> Array[Dictionary]:
	match String(spec.opts.get("kind", "")):
		"booth":
			return _booth(spec)
		"menu":
			var base := ObjectMeshNoodleConfig.menu_base
			var rect := _share(
				spec,
				Rect2(0.0, 0.0, spec.size.x, ObjectMeshNoodleConfig.menu_depth),
			)
			return [_part(base + ObjectMeshNoodleConfig.menu_height, base, rect)]
	return [_part(NoodleMesh.height_of(spec))]


## A booth: a bench seat along each long side with its back at the outer edge, the table between.
static func _booth(spec: FurnitureSpec) -> Array[Dictionary]:
	var depth := spec.size.y
	var table := Rect2(8.0, 22.0, spec.size.x - 16.0, depth - 44.0)
	var seats := ObjectMeshNoodleConfig.booth_seat
	return [
		_part(seats, 0.0, _share(spec, Rect2(0.0, 0.0, spec.size.x, 18.0))),
		_part(seats, 0.0, _share(spec, Rect2(0.0, depth - 18.0, spec.size.x, 18.0))),
		_part(ObjectMeshNoodleConfig.table_height, 0.0, _share(spec, table)),
		_part(
			ObjectMeshNoodleConfig.booth_back, 0.0, _share(spec, Rect2(0.0, 0.0, spec.size.x, 4.0))
		),
		_part(
			ObjectMeshNoodleConfig.booth_back,
			0.0,
			_share(spec, Rect2(0.0, depth - 4.0, spec.size.x, 4.0)),
		),
	]


## A wall fixture: a mirror hangs from `fixture_mirror_base`, a towel bar at `fixture_bar_height`.
static func _fixture(spec: FurnitureSpec) -> Array[Dictionary]:
	var deep := ObjectMeshDecorConfig.fixture_thickness + 1.6
	var rect := _share(spec, Rect2(0.0, 0.0, spec.size.x, deep))
	if String(spec.opts.get("kind", "mirror")) == "towels":
		var bar := ObjectMeshDecorConfig.fixture_bar_height
		return [_part(bar + 2.0, bar - 22.0, rect)]
	var base := ObjectMeshDecorConfig.fixture_mirror_base
	return [_part(base + ObjectMeshDecorConfig.fixture_mirror_height, base, rect)]


## The bathroom, the office and the clinic's chairs: one top each.
static func _room(spec: FurnitureSpec) -> Array[Dictionary]:
	var top := ObjectMeshChairConfig.recliner_back_height
	var kind := String(spec.opts.get("kind", ""))
	match spec.art:
		"bath":
			top = ObjectMeshRoomConfig.bath_rim_height
			if String(spec.opts.get("style", "tub")) == "shower":
				top = ObjectMeshRoomConfig.bath_screen_height
		"toilet":
			top = ObjectMeshRoomConfig.toilet_tank_height
		"office_chair":
			top = ObjectMeshChairConfig.office_back_height
		"clinic":
			top = ClinicMesh.height_of(spec)
		_:
			if kind == "surgical":
				top = ObjectMeshClinicConfig.head_height
	return [_part(top)]


## The commercial and street kinds with a `height_of` of their own: one top each.
static func _commercial(spec: FurnitureSpec) -> Array[Dictionary]:
	var top := ObjectMeshOverheadConfig.post_height
	match spec.art:
		"tech":
			top = ObjectMeshTechConfig.rail_height
			if String(spec.opts.get("kind", "monitor_wall")) == "server_rack":
				top = TechMesh.rack_height(spec)
		"security":
			top = SecurityMesh.height_of(spec)
		"shop":
			top = ShopMesh.height_of(spec)
		"stock":
			top = StockMesh.height_of(spec)
		"street_prop":
			top = StreetPropMesh.height_of(spec)
		"podium":
			top = ObjectMeshStreetConfig.pillar_height
		"awning":
			return _awning(spec)
	return [_part(top)]


## An awning, or a glyph sign: over the head, from where its lowest edge hangs to its top.
static func _awning(spec: FurnitureSpec) -> Array[Dictionary]:
	if String(spec.opts.get("kind", "awning")) == "hanging":
		var rod := ObjectMeshOverheadConfig.hanging_rod
		return [_part(rod + 2.0, rod - ObjectMeshOverheadConfig.hanging_blade)]
	var front := ObjectMeshOverheadConfig.awning_front
	var rise := ObjectMeshOverheadConfig.awning_rise
	return [_part(front + rise + 2.0, front - ObjectMeshOverheadConfig.awning_valance)]


## The decor, the shell's clutter, a rug, a plant, a lamp, a coat rack, a hotplate, a car.
static func _decor(spec: FurnitureSpec) -> Array[Dictionary]:
	var kind := String(spec.opts.get("kind", ""))
	var top := _shell_top(kind)
	match spec.art:
		"rug":
			top = ObjectMeshDecorConfig.rug_height + ObjectMeshDecorConfig.rug_field_lift
		"plant":
			top = ObjectMeshDecorConfig.plant_height
		"lamp":
			top = ObjectMeshDecorConfig.lamp_height
		"coat_rack":
			top = ObjectMeshDecorConfig.coat_rack_height
		"hotplate":
			top = ObjectMeshKitchenConfig.hotplate_crate_height
		"car":
			top = ObjectMeshCarConfig.roof_top()
		"decor":
			top = _clutter_top(kind)
	return [_part(top)]


## The top of a piece of clutter: a cable's thickness, a flattened box and its blanket, standing
## water, a neon tube; trash is the bags' height.
static func _clutter_top(kind: String) -> float:
	match kind:
		"cables", "cable_nest":
			return ObjectMeshShellConfig.cable
		"cardboard":
			return ObjectMeshShellConfig.cardboard + ObjectMeshShellConfig.blanket
		"puddle":
			return ObjectMeshShellConfig.puddle
		"neon_tube":
			return ObjectMeshShellConfig.neon_tube
	return 10.0


## The top of the shell's rubble.
static func _shell_top(kind: String) -> float:
	match kind:
		"rebar":
			return ObjectMeshShellConfig.rod * 2.0 + 0.6
		"rubble":
			return ObjectMeshShellConfig.rubble_high
		"scaffold":
			return ObjectMeshShellConfig.tube + ObjectMeshShellConfig.board
		"cement":
			return ObjectMeshShellConfig.bag
	return ObjectMeshShellConfig.stain_top
