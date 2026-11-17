extends Node2D
## Floor (Objects domain): one room's floor, or a piece of the street round a house — a rect
## covered in a repeating pixel-art tile. It has no collider, so shots, navigation and perception
## all pass over it. Built by FloorFactory; the 3D render shows it (`floor_mesh.gd`,
## `street_mesh.gd`), reading these fields. It tells the Physics blood flow where its grooves are
## and, unless `sound_surface` is off (the street: footsteps out there stay the open ground's), the
## Audio domain what it is made of. A floor of the street (`light_layer` `street`) is lit only by
## the street's lights. It joins the group `floors`, which the Lighting domain walks for its
## per-floor light budget.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const StreetMarks = preload("res://scenes/objects/decals/street_marks.gd")

## Floor extent (px) from this node's origin.
@export var size: Vector2 = Vector2(100.0, 100.0)
## Tiling painter id.
@export var art: String = "floor"
## Base color the tile is painted in.
@export var color: Color = Color(0.6, 0.5, 0.4)
## Material tag (the tile's surface finish).
@export var floor_material: String = ""
## Painter options, e.g. { "pattern": "planks" }.
@export var art_opts: Dictionary = {}
## Registers with SoundSurface (off: footsteps on it sound like the open ground).
@export var sound_surface: bool = true
## World-placed marks over the floor (the street's: `{ seed, lane, edges }`; a `StreetMarks` child
## holds them, see street_marks.gd); empty = none.
@export var marks: Dictionary = {}
## How far (px) into the repeating tile the floor's corner falls: 0 starts the tile at the corner (a
## room's floor); the street's pieces share one grid, so their slab joints meet.
@export var tile_offset: Vector2 = Vector2.ZERO
## The light layer it is drawn on: `""` the house's (Godot's default), `street` the street's, lit
## only by the street lamps, the flashes and the street's own sky, so a floor spanning the whole
## house is never crowded by the house's lights.
@export var light_layer: String = ""

## The room's wear node (`WearFactory.spawn` sets it: the room's `RoomWear`, in this floor's frame),
## whose floor marks the 3D mesh lays on the slab; null for a floor with none.
var wear: Node2D = null
## BloodSurface registration of this floor.
var _surface_id := -1
## SoundSurface registration of this floor.
var _sound_id := -1


func _ready() -> void:
	add_to_group(&"floors")
	if not marks.is_empty():
		StreetMarks.new().setup_marks(self, size, art_opts, marks, tile_offset)
	# Tell the Physics blood flow where this floor's grooves are, so blood follows grout and seams.
	_surface_id = BloodSurface.register(
		Rect2(global_position, size),
		flow_groove,
		ObjectArt.porous(art, art_opts),
	)
	# And the Audio domain what it is made of, so footsteps sound like it.
	if sound_surface:
		_sound_id = SoundSurface.register(
			Rect2(global_position, size),
			floor_material,
			String(art_opts.get("pattern", "")),
		)


func _exit_tree() -> void:
	BloodSurface.unregister(_surface_id)
	SoundSurface.unregister(_sound_id)


## Whether this is a floor of the street (`light_layer` `street`): the Lighting domain's sun
## reaches it and no house light does.
func is_street() -> bool:
	return light_layer == "street"


## 1 where world point `at` is on a groove of this floor's pattern (BloodSurface callback).
func flow_groove(at: Vector2, half_width: float) -> float:
	return ObjectArt.groove(art, at - global_position, art_opts, half_width)
