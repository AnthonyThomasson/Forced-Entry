extends RefCounted
## Objects domain (private): a door's look, `door.look`, what its visuals draw: the material and
## style that pick the painter's art, the leaf's base colour and whether a glass-panel door's panes
## have shattered. Plain data, filled by `Door.setup` from the catalogue definition.

## The material (`DoorMaterialConfig.materials`' key) and the style (`door_painter.gd`'s).
var material := ""
var style := ""
## The leaf's base colour.
var color := Color.GRAY
## The panes are shattered: the frame stays, the glass is gone.
var broken := false


## The surface finish the leaf is drawn in (`PixelCanvas.surface`): metal for steel, else wood (a
## glass-panel door's frame is wood).
func finish() -> String:
	return "metal" if material == "steel" else "wood"


## The options the door painter is handed for the leaf standing (`fallen` false) or lying knocked
## down.
func art_opts(fallen: bool) -> Dictionary:
	return {
		"part": "fallen" if fallen else "leaf",
		"style": style,
		"door_material": material,
		"broken": broken,
		"material": finish(),
	}
