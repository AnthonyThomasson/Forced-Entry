class_name DoorCatalog
## World Generation domain: the catalogue of doors, one definition per material and style, for
## `DoorFactory.spawn` (the Objects domain owns the fields and what each material is made of,
## `DoorMaterialConfig`; World-Gen owns which doors exist and how they look by name and colour).
##
## Definition fields: `name` (display name), `material` (`hollow` hollow-core wood, `solid` solid
## wood, `steel`, `glass` a glass-panel door: wood frame with panes), `style` (`flush`, `panelled`,
## `plank`, `riveted`, `peephole`, `panes`) and `color` (the leaf's base colour; the frame's, for
## glass).

const DOORS := {
	"hollow_flush": {
		"name": "Hollow-core door", "material": "hollow", "style": "flush",
		"color": Color(0.64, 0.52, 0.38),
	},
	"hollow_panelled": {
		"name": "Panelled hollow-core door", "material": "hollow", "style": "panelled",
		"color": Color(0.64, 0.52, 0.38),
	},
	"solid_panelled": {
		"name": "Solid wood door", "material": "solid", "style": "panelled",
		"color": Color(0.42, 0.28, 0.17),
	},
	"solid_plank": {
		"name": "Plank door", "material": "solid", "style": "plank",
		"color": Color(0.42, 0.28, 0.17),
	},
	"steel_riveted": {
		"name": "Riveted steel door", "material": "steel", "style": "riveted",
		"color": Color(0.44, 0.46, 0.46),
	},
	"steel_peephole": {
		"name": "Steel door with a peephole", "material": "steel", "style": "peephole",
		"color": Color(0.44, 0.46, 0.46),
	},
	"glass_panes": {
		"name": "Glass-panel door", "material": "glass", "style": "panes",
		"color": Color(0.5, 0.36, 0.22),
	},
}


## The definition of the door of `material` in `style`, or {} if the catalogue has none.
static func definition(material: String, style: String) -> Dictionary:
	return DOORS.get("%s_%s" % [material, style], {})
