extends RefCounted
## Objects domain, the 3D mesh of the tower stockroom's wall safe (the pattern is
## `table_mesh.gd`, `domain-art/meshes.md`): at the piece's own footprint and `stock_painter.gd`'s
## proportions, a steel body with a lighter top, its door's edge toward the front with a dial and a
## handle. The stockroom's crates and its pallet with their wrapped boxes are loose items now
## (decision D21: `PieceCarries`, `item_stock_mesh.gd`).

const OPTIONS := ["kind", "height"]
## How far a feature stands proud of the face it is laid on.
const PROUD := 0.5


## The node a stockroom `piece` is shown by, in 3D units with its origin at the piece's origin.
static func build(piece: Node2D) -> Node3D:
	var spec := FurnitureSpec.of(piece)
	return FurnitureMesh.show(piece, FurnitureMesh.fetch(
		"stock", spec, _tuning(spec), func() -> Mesh: return _mesh(spec)
	))


## How tall the safe stands: its `art_opts.height`, else the holder's.
static func height_of(spec: FurnitureSpec) -> float:
	var own: Variant = spec.opts.get("height")
	if own is float or own is int:
		return float(own)
	return ObjectMeshShopConfig.safe_height


## Every value the shape reads, so a retuned one is another mesh.
static func _tuning(spec: FurnitureSpec) -> Dictionary:
	return { "opts": spec.read(OPTIONS), "height": height_of(spec) }


## The solids of the piece, built once per cache key.
static func _mesh(spec: FurnitureSpec) -> Mesh:
	var kit := spec.kit()
	_safe(spec, kit)
	return kit.build()


## The safe: a steel body, a lighter top, the door's edge with a dial and a handle on its front.
static func _safe(spec: FurnitureSpec, kit: MeshKit) -> void:
	var w := spec.size.x
	var d := spec.size.y
	var height := height_of(spec)
	var steel := spec.color
	kit.box(MeshKit.volume(spec.area(0, 0, w, d - PROUD), 0.0, height), steel, steel.lightened(0.1))
	kit.box(
		MeshKit.volume(spec.area(3, d - PROUD, w - 6.0, PROUD * 0.5), 3.0, height - 8.0),
		steel.lightened(0.05),
	)
	kit.box(
		MeshKit.volume(spec.area(8, d - PROUD, 4, PROUD), height * 0.5, 4.0),
		Color(0.85, 0.85, 0.8),
	)
	kit.box(
		MeshKit.volume(spec.area(w - 12.0, d - PROUD, 7, PROUD), height * 0.5, 3.0),
		Color(0.06, 0.06, 0.08),
	)
