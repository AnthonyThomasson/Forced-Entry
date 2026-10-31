extends Node2D
## Objects domain: draws a `Door`'s leaf (the child `DoorVisuals`, in the leaf's own frame, centred
## on it): the painter's art (`art/door_painter.gd`), lit for the angle the leaf stands at now, cut
## through its dents like any piece (`Deformation.draw_shape`), with a hit's hole marks over it. The
## art is painted again only when the leaf turns to another of `ArtCanvasConfig.turn_steps`'
## lighting steps, or when its look changes (the panes shatter, the door falls).

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

## The Physics component recording the dents and holes (a child; its changes redraw).
var deformable: Deformable
## The door this draws and the footprint it draws (px), centred on this node.
var _door: Node2D
var _size := Vector2.ONE
## The art now and the lighting angle it was painted for (NAN = not yet).
var _art: Texture2D
## Whether the door lies knocked down.
var _fallen := false
var _lit := NAN


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	deformable = Deformable.new()
	deformable.max_depth = DoorConfig.dent_depth
	deformable.allow_chunks = false
	deformable.max_impacts = DoorConfig.dents
	add_child(deformable)
	deformable.changed.connect(queue_redraw)
	_refresh(global_rotation)


## Paint the art again when the leaf has turned to another lighting step.
func _process(_delta: float) -> void:
	var snapped_angle := PixelArt.snap_angle(global_rotation)
	if snapped_angle != _lit:
		_refresh(snapped_angle)


func _draw() -> void:
	var shape_look := ShapeLook.new()
	var color: Color = _door.look.color
	shape_look.fill = color
	shape_look.outline = color.darkened(ArtSurfaceConfig.tone_outline)
	shape_look.damage_total = deformable.damage_total
	shape_look.texture = _art
	Deformation.draw_shape(self, "rect", _size, [] if _fallen else deformable.impacts, shape_look)


## Draw `door` (a `Door`) as a leaf of `size` px.
func setup(door: Node2D, size: Vector2) -> void:
	_door = door
	_size = size


## The door has been knocked down: draw it lying face up, `size` px (its length along the way it
## fell, then its width), its hinge edge toward `-y`, or `+y` when `flipped`.
func fall(size: Vector2, flipped: bool) -> void:
	_size = size
	_fallen = true
	scale.y = -1.0 if flipped else 1.0
	_refresh(global_rotation)


## Paint the art again (the leaf's look changed: its panes shattered).
func refresh() -> void:
	_refresh(_lit)


## The art of the leaf as it is drawn now.
func texture() -> Texture2D:
	return _art


## Paint the art for `angle` and draw it.
func _refresh(angle: float) -> void:
	_lit = PixelArt.snap_angle(angle)
	var look = _door.look
	_art = ObjectArt.turned("door", _size, look.color, _lit, look.art_opts(_fallen))
	queue_redraw()
