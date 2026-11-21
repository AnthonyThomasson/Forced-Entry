class_name ObjectFactory
## Objects-domain factory: turns an object DEFINITION (a plain data dict, looked up by
## World-Gen from its catalogue) into a runtime EnvironmentObject node. Objects owns the
## field schema; World-Gen owns which objects exist. This keeps the two domains talking
## through a plain Dictionary, so neither reaches into the other's internals.
##
## Definition fields: name, shape ("circle"|"square"|"rect"), size, color (required);
##   material, penetration, weight, solid, interactions (all optional);
##   anchored (optional, default false: a solid piece that never moves, frozen static; still struck,
## dented, throwing debris); art (an `ObjectArt` painter id, e.g. "sofa"; omitted = the flat shape)
## and art_opts (painter overrides, see the ObjectArt*Config holders) (optional);
##   overhang (optional `{ size, reach }`: an overhead part beyond the footprint, a streetlight's
##     arm and head, shown by the piece's mesh from its painter with `part: "overhang"`, `size`
##     across x out, centred `reach` px out along the facing, above the characters, with no
##     collider; kept as the plain field `piece.look.overhang` and read back as an area by
##     `piece.look.overhang_rect()`, which the 3D meshes read).
## `opts`:
##   name:    String  — node name (readable hit labels; defaults to the definition name).
##   rotated: bool    — swap the footprint's width/height (a 90° turn).
##   color:   Color   — override the definition color (e.g. a room palette tone).
##   facing:  Vector2 — which way the piece's front faces (cardinal; default DOWN). Orients art.
##   neon:    String  — the piece's neon trim or screen, `"cyan"`, `"magenta"` or `""` for none;
##                      omitted, a share of the light-giving pieces take one, picked per piece from
##                      where it stands (ObjectArt.neon_for), so the same piece of the same house
##                      always looks the same.

const EnvironmentObject = preload("res://scenes/objects/environment_object.gd")
const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
## How high (px) a probe for a top starts: over every piece, under a roof.
const TOP_PROBE := 90.0


## Build a runtime object from its definition and add it under `parent`. Returns the node.
static func spawn(
	definition: Dictionary,
	position: Vector2,
	parent: Node,
	opts: Dictionary = {},
) -> Node:
	if definition.is_empty():
		push_error("ObjectFactory: empty definition")
		return null

	var size: Vector2 = definition["size"]
	if opts.get("rotated", false):
		size = Vector2(size.y, size.x)
	var color: Color = opts.get("color", definition["color"])

	var obj := Node2D.new()
	obj.name = String(opts.get("name", definition.get("name", "Object"))).capitalize()
	obj.position = position
	obj.script = EnvironmentObject

	obj.shape_type = definition["shape"]
	obj.object_name = definition["name"]
	obj.size = size
	obj.color = color
	obj.solid = definition.get("solid", true)
	obj.anchored = definition.get("anchored", false)
	obj.object_material = definition.get("material", "")
	obj.penetration = definition.get("penetration", 0.0)
	obj.weight = definition.get("weight", 10.0)
	obj.interactions = definition.get("interactions", [])
	obj.look.art = definition.get("art", "")
	obj.look.art_opts = definition.get("art_opts", {})
	var neon: String = opts.get(
		"neon",
		ObjectArt.neon_for(obj.look.art, obj.look.art_opts, hash(Vector2i(position.round()))),
	)
	if neon != "":
		obj.look.art_opts = obj.look.art_opts.merged({ "neon": neon })
	obj.look.facing = opts.get("facing", Vector2.DOWN)
	obj.look.overhang = definition.get("overhang", {})

	parent.add_child(obj, true)  # Readable unique names (Chair, Chair2, ...).
	return obj


## Build a small item from `definition` and set it down on the top of `base` (another piece: a
## table, a shelf, a box), at `offset` px from `base`'s origin in its frame, under `parent` (#194
## stack-a, D20, `docs/stacked-items.md`). The item's free body starts at that top's height
## (`top_at`) and settles asleep on it; it is its own body from then on (a shove, a round, a blast
## or a tipping base moves it alone). `opts` as `spawn`'s. Another item set on the same spot goes on
## top of the first (a stack).
static func spawn_on(
	definition: Dictionary,
	base: Node2D,
	offset: Vector2,
	parent: Node,
	opts: Dictionary = {},
) -> Node:
	var point := base.to_global(offset)
	var local := (parent as Node2D).to_local(point) if parent is Node2D else point
	var item := spawn(definition, local, parent, opts)
	if item == null:
		return null
	var rest := item.rest as PieceRest
	rest.lift = maxf(top_at(base, point), _chain_top(base, item))
	var base_rest: Variant = base.get(&"rest")
	if base_rest is PieceRest:
		(base_rest as PieceRest).stacked.append(item)
	return item


## The height (px above the floor) of the highest top at plan point `point` over `base`: read from
## the twin space (a downward ray against the world's twins and what lies flat, so a box or a
## plate already standing there raises it) once `base` has a twin there, else `base`'s own lift
## and top from its catalogue parts.
static func top_at(base: Node2D, point: Vector2) -> float:
	var twin := TwinSpace.twin_for(base)
	if twin != null and twin.is_inside_tree():
		var space := TwinSpace.space_of(base)
		if space != null:
			var query := PhysicsRayQueryParameters3D.create(
				PlanSpace.lift(point, TOP_PROBE), PlanSpace.lift(point, -1.0),
				PhysicsLayers.TWIN_WORLD | PhysicsLayers.TWIN_WALKOVER
			)
			var hit := space.intersect_ray(query)
			if not hit.is_empty():
				return PlanSpace.height_of(hit["position"])
	var rest: Variant = base.get(&"rest")
	var lift: float = (rest as PieceRest).lift if rest is PieceRest else 0.0
	return lift + PieceHeights.top_of_spec(FurnitureSpec.of(base))


## The top (px) of the highest item already set on `base` that still has no twin and that `item`'s
## footprint overlaps: two items set on one spot in one frame (a house is built before the twin
## space takes any piece over) stack on each other, which the twin space cannot say yet. An item
## with a twin is read through `top_at`'s ray, which sees where it really lies. 0 when none.
static func _chain_top(base: Node2D, item: Node2D) -> float:
	var base_rest: Variant = base.get(&"rest")
	if not base_rest is PieceRest:
		return 0.0
	var mine := Rect2(item.global_position - item.size * 0.5, item.size)
	var best := 0.0
	var kept: Array[Node2D] = []
	for other in (base_rest as PieceRest).stacked:
		if not is_instance_valid(other) or TwinSpace.twin_for(other) != null:
			continue  # gone, or a twin now: the ray sees it
		kept.append(other)
		if other == item:
			continue
		if not mine.intersects(Rect2(other.global_position - other.size * 0.5, other.size)):
			continue
		var top: float = (other.rest as PieceRest).lift + PieceHeights.top_of_spec(
			FurnitureSpec.of(other)
		)
		best = maxf(best, top)
	(base_rest as PieceRest).stacked = kept
	return best
