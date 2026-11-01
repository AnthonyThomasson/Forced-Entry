extends RefCounted
## Turns a showroom painter into a node: its texture through `PixelArt.render`, the pixels it drew
## `glowing` drawn unshaded over it, an optional drop shadow, and an optional solid collider so a
## piece stands in the way as the catalogue's do. The painter is any script with
## `static paint(canvas, base, material, opts)` (Art, interface 12).

const SHADOW_SHIFT := 2.0
const SHADOW_ALPHA := 0.3


## A node at `pos` (its top-left) drawing `painter`'s art for `size` px. `opts` goes to the painter;
## `flags`: `street` (on the street's light layer), `shadow` (a drop shadow), `solid` (a collider),
## `z` (its z index, default the standing world's), `shift` (how far the shadow falls, px),
## `facing` (a cardinal facing), `color` (the painter's base colour).
static func make(
	painter: Script,
	size: Vector2,
	pos: Vector2,
	opts := {},
	flags := {},
) -> Node2D:
	var root := Node2D.new()
	root.position = pos
	root.z_index = int(flags.get("z", DrawLayers.STANDING))
	var facing: Vector2 = flags.get("facing", Vector2.DOWN)
	var color: Color = flags.get("color", Color.WHITE)
	var tex := PixelArt.render(painter, size, color, facing, opts)
	if flags.get("shadow", false):
		var shade := _layer(tex, "Shadow")
		shade.modulate = Color(0, 0, 0, SHADOW_ALPHA)
		root.add_child(shade)
		root.set_meta(&"has_shadow", true)
		root.set_meta(&"shadow_shift", float(flags.get("shift", SHADOW_SHIFT)))
	root.add_child(_layer(tex, "Art"))
	var glow := PixelArt.emissive(painter, size, color, facing, opts)
	if glow != null:
		var lit := _layer(glow, "Glow")
		lit.material = CanvasItemMaterial.new()
		(lit.material as CanvasItemMaterial).light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		root.add_child(lit)
	if flags.get("street", false):
		for child in root.get_children():
			(child as CanvasItem).light_mask = LightMasks.STREET
		root.light_mask = LightMasks.STREET
	if flags.get("solid", false):
		root.add_child(_collider(size))
	return root


## Shift the drop shadow of `root` (made with the `shadow` flag) away from the light. It has to be
## in the tree: the direction is read in its own frame (`PixelArt.away_from_light`).
static func settle(root: Node2D) -> void:
	if not root.has_meta(&"has_shadow"):
		return
	var shade := root.get_node("Shadow") as Node2D
	shade.position = PixelArt.away_from_light(root) * float(root.get_meta(&"shadow_shift"))


static func _layer(tex: Texture2D, layer_name: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = layer_name
	s.texture = tex
	s.centered = false
	return s


static func _collider(size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = "Collider"
	body.collision_layer = PhysicsLayers.SOLID
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	body.add_child(shape)
	return body
