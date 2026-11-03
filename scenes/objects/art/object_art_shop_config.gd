class_name ObjectArtShopConfig
## The tower's shop-floor props (scenes/objects/art/): the shop's counter, shelf aisle, drinks
## fridge and snack machine (shop_painter.gd), the noodle bar's bar, stool, booth and menu board
## (noodle_painter.gd) and the stockroom's crates, pallet and safe (stock_painter.gd), in the grimy
## steel family. The steel itself is the catalogue colour; these are the rest. A `class_name` holder
## of `static var`s, read as `ObjectArtShopConfig.<name>`; there is no instance and no autoload. A
## piece's catalogue `art_opts` overrides a painter knob for that piece only, keyed by the knob's
## name without its painter prefix (`shop_top_color` -> `top_color`).

## The grimy steel family's shared tones, which `ObjectArtStreetPropConfig` reads too: the lighter
## steel of tops, the rust-orange lip and trim, dull glass, oak wood and the paper-white of labels
## and bowls.
const STEEL_TOP := Color(0.58, 0.58, 0.55)
const RUST := Color(0.62, 0.34, 0.17)
const DULL_GLASS := Color(0.3, 0.4, 0.42)
const OAK := Color(0.5, 0.38, 0.24)
const PAPER := Color(0.9, 0.88, 0.8)

## The shop's lighter steel tops, the rust-orange lip along a counter, the dull glass of the till
## and snack window, the pale glow of the fridge's glass (glowing) and the packs on the shelves.
static var shop_top_color: Color = STEEL_TOP
static var shop_accent_color: Color = RUST
static var shop_glass_color: Color = DULL_GLASS
static var shop_fridge_glow: Color = Color(0.82, 0.95, 1.0)
static var shop_packs: Array[Color] = [
	Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.2), Color(0.3, 0.7, 0.9), Color(0.5, 0.85, 0.4),
	Color(0.9, 0.55, 0.15), Color(0.85, 0.85, 0.8),
]
## The noodle bar: the bar's and booth's steel top, the lip and stool seat, the bar's wood, the
## broth and the bowls, and the menu board's two lines of light (glowing).
static var noodle_top_color: Color = STEEL_TOP
static var noodle_accent_color: Color = RUST
static var noodle_wood_color: Color = OAK
static var noodle_broth_color: Color = Color(0.74, 0.5, 0.2)
static var noodle_bowl_color: Color = PAPER
static var noodle_menu_colors: Array[Color] = [RUST, Color(0.95, 0.85, 0.5)]
## The stockroom: crate wood, the cardboard of the wrapped boxes, the paper labels.
static var stock_wood_color: Color = OAK
static var stock_cardboard_color: Color = Color(0.62, 0.48, 0.3)
static var stock_label_color: Color = PAPER
