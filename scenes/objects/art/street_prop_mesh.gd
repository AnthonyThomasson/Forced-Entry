extends RefCounted
## Objects domain, the 3D mesh of a district's sidewalk props (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and
## `street_prop_painter.gd`'s proportions, in grimy steel, by `kind`. `vending` is a drinks machine,
## a lighter face with grooves and the lit window of drinks toward the street (a glow node of the
## rig, no real light); `bench` two steel end frames with wooden slats between, at seat height;
## `bin` a round bin with a lid, its dark mouth and a trim ring; `grate` a drain grate, its frame,
## bars and the dark pit; `litter` flat scraps lying about, a fixed scatter per look.

const OPTIONS := [
	"kind", "top_color", "accent_color", "glass_color", "wood_color", "products", "slats",
	"grate_step", "scraps", "height",
]
## How far a feature stands proud of the face it is laid on.
const PROUD := 0.6


## The node a street prop `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	var tuning := _tuning(spec)
	var rig := FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"street_prop", spec, tuning, func() -> Mesh: return _mesh(spec)
	))
	if _kind(spec) == "vending":
		var glow := FurnitureMesh.fetch_glow(
			"street_prop", spec, tuning, func() -> Mesh: return _window(spec)
		)
		rig.add_glow(glow, _colour(spec, "glass_color"), ObjectMeshStateConfig.window_strength)
	return rig


## The kind the piece is: its `art_opts.kind`, else the painter's.
static func _kind(spec: FurnitureSpec) -> String:
	return String(spec.opts.get("kind", "vending"))


## The painter's colour option `name` of the piece, else its holder default.
static func _colour(spec: FurnitureSpec, name: String) -> Color:
	var defaults := {
		"top_color": ObjectArtStreetPropConfig.prop_top_color,
		"accent_color": ObjectArtStreetPropConfig.prop_accent_color,
		"glass_color": ObjectArtStreetPropConfig.prop_glass_color,
		"wood_color": ObjectArtStreetPropConfig.prop_wood_color,
	}
	return spec.opts.get(name, defaults[name])


## The drinks in the window (or the litter's scraps): the piece's own list, else the holder's.
static func _products(spec: FurnitureSpec) -> Array:
	return spec.opts.get("products", ObjectArtStreetPropConfig.prop_products)


## How tall the piece stands: its `art_opts.height`, else its kind's (a grate and litter are
## flat).
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	match _kind(spec):
		"bench":
			return ObjectMeshStreetConfig.bench_seat
		"bin":
			return ObjectMeshStreetConfig.bin_height + ObjectMeshStreetConfig.bin_lid
		"grate":
			return ObjectMeshStreetConfig.grate_height
		"litter":
			return ObjectMeshStreetConfig.litter_height
	return ObjectMeshStreetConfig.vending_height


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	var out := {
		"opts": spec.read(OPTIONS),
		"height": height_of(spec),
		"bin": [ObjectMeshStreetConfig.bin_height, ObjectMeshStreetConfig.bin_lid],
		"products": _products(spec),
		"slats": spec.opts.get("slats", ObjectArtStreetPropConfig.prop_slats),
		"step": spec.opts.get("grate_step", ObjectArtStreetPropConfig.prop_grate_step),
		"scraps": spec.opts.get("scraps", ObjectArtStreetPropConfig.prop_scraps),
	}
	for name in ["top_color", "accent_color", "glass_color", "wood_color"]:
		out[name] = _colour(spec, name)
	return out


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	match _kind(spec):
		"bench":
			_bench(spec, kit)
		"bin":
			_bin(spec, kit)
		"grate":
			_grate(spec, kit)
		"litter":
			_litter(spec, kit)
		_:
			_vending(spec, kit)
	return kit.build()


## The machine: a steel body, a lighter face with grooves and the drinks standing proud of the
## glass.
static func _vending(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var products := _products(spec)
	kit.box(
		MeshKit.volume(spec.area(0, 0, w, d - PROUD), 0.0, height),
		spec.color,
		_colour(spec, "top_color"),
	)
	for k in range(5, int(w) - 5, 5):
		kit.box(
			MeshKit.volume(spec.area(k, d - PROUD, 1, PROUD), height * 0.5, height * 0.45),
			spec.color.darkened(0.2),
		)
	kit.box(
		MeshKit.volume(spec.area(2, d - PROUD, w - 4.0, PROUD * 0.5), 8.0, height * 0.4 + 4.0),
		spec.color.darkened(0.5),
	)
	for k in range(0, int(w) - 8, 4):
		kit.box(
			MeshKit.volume(spec.area(4 + k, d - PROUD, 3, PROUD), 12.0, 10.0),
			products[int(k / 4.0) % products.size()],
		)


## The window: the dull glass plate along the front, behind the drinks.
static func _window(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	kit.box(
		MeshKit.volume(
			spec.area(3, spec.size.y - PROUD, spec.size.x - 6.0, PROUD * 0.6),
			10.0,
			height_of(spec) * 0.4,
		),
		_colour(spec, "glass_color"),
	)
	return kit.build()


## The bench: two steel end frames with feet, wooden slats across them at seat height.
static func _bench(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var seat := height_of(spec)
	var wood := _colour(spec, "wood_color")
	for x: float in [3.0, w - 7.0]:
		kit.box(MeshKit.volume(spec.area(x, 0, 4, d), 0.0, seat - 2.5), spec.color)
	var slats := maxi(1, int(spec.opts.get("slats", ObjectArtStreetPropConfig.prop_slats)))
	var step := floorf((d - 2.0) / float(slats))
	for k in slats:
		kit.box(
			MeshKit.volume(
				spec.area(2, 1.0 + k * step, w - 4.0, maxf(1.0, step - 1.0)),
				seat - 2.5,
				2.5,
			),
			wood.lightened(0.04 * (k % 2)),
		)


## The bin: a dark round body, a lid with a dark mouth and the trim ring.
static func _bin(spec: FurnitureSpec, kit: MeshKit) -> void:
	var radius := floorf(minf(spec.size.x, spec.size.y) / 2.0) - 1.0
	var body := ObjectMeshStreetConfig.bin_height
	var lid := ObjectMeshStreetConfig.bin_lid
	var top := _colour(spec, "top_color")
	kit.cylinder(Vector3.ZERO, radius, body, spec.color.darkened(0.3))
	kit.cylinder(
		Vector3(0, body, 0),
		radius - 1.0,
		lid,
		_colour(spec, "accent_color").darkened(0.2),
		top,
	)
	kit.cylinder(Vector3(1, body + lid, 1), maxf(1.0, radius - 6.0), 0.2, Color(0.05, 0.05, 0.06))


## The grate: the frame, the dark pit and the bars over it.
static func _grate(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var top := _colour(spec, "top_color")
	var frame := spec.color.darkened(0.15)
	for strip in FurnitureSpec.ring(Rect2(0, 0, w, d), Rect2(3, 3, w - 6.0, d - 6.0)):
		kit.box(
			MeshKit.volume(
				spec.area(strip.position.x, strip.position.y, strip.size.x, strip.size.y),
				0.0,
				height,
			),
			frame,
		)
	kit.box(
		MeshKit.volume(spec.area(3, 3, w - 6.0, d - 6.0), 0.0, height * 0.3),
		Color(0.03, 0.03, 0.04),
	)
	var step := maxi(2, int(spec.opts.get("grate_step", ObjectArtStreetPropConfig.prop_grate_step)))
	for x in range(4, int(w) - 4, step):
		kit.box(MeshKit.volume(spec.area(x, 3, 2, d - 6.0), 0.0, height), top)


## Scraps of paper, cans and cloth, a fixed scatter: flat boxes and a few round ones.
static func _litter(spec: FurnitureSpec, kit: MeshKit) -> void:
	var rng := spec.rng("litter", OPTIONS)
	var drink: Color = _products(spec)[rng.randi() % _products(spec).size()]
	var tones: Array[Color] = [drink]
	for name in ["accent_color", "top_color", "wood_color"]:
		tones.append(_colour(spec, name))
	var height := height_of(spec)
	for _i in int(spec.opts.get("scraps", ObjectArtStreetPropConfig.prop_scraps)):
		var at := Vector2(
			rng.randi_range(2, maxi(2, int(spec.size.x) - 6)),
			rng.randi_range(2, maxi(2, int(spec.size.y) - 6)),
		)
		var tone := tones[rng.randi() % tones.size()]
		var scrap := Rect2(at, Vector2(rng.randi_range(2, 5), rng.randi_range(2, 4)))
		if rng.randf() < 0.3:
			var centre := at + Vector2(2, 2) - spec.half()
			kit.cylinder(Vector3(centre.x, 0.0, centre.y), 2.0, height, tone)
		else:
			var scale := rng.randf_range(0.5, 1.0)
			kit.box(MeshKit.volume(spec.within(scrap), 0.0, height * scale), tone)
