class_name ObjectArtStorageConfig
## Casegoods (scenes/objects/art/): the cabinet (front, count, crown, handles, glass) and the shelf
## (contents, box colour). A `class_name` holder of `static var`s, read as
## `ObjectArtStorageConfig.<name>`; there is no instance and no autoload. A piece's catalogue
## `art_opts` overrides a painter knob for that piece only, keyed by the knob's name without its
## painter prefix (`table_inset` → `inset`).

## Front lip strip depth as a fraction of the cabinet's depth, what it shows by default
## ("doors", "drawers", "lid" or "none") and how many doors or drawers across it.
static var cabinet_front_depth: float = 0.16
static var cabinet_front: String = "doors"
static var cabinet_count: int = 2
## Crown moulding around the top.
static var cabinet_crown: bool = false
## The handles' metal, and the tint of a glass top.
static var cabinet_handle_color: Color = Color(0.5, 0.36, 0.2)
static var cabinet_glass_color: Color = Color(0.42, 0.42, 0.34)
## What fills the shelf by default ("books", "boxes" or "shoes"), and the cardboard of a box.
static var shelf_contents: String = "books"
static var shelf_box_color: Color = Color(0.5, 0.38, 0.24)
