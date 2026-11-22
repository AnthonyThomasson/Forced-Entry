class_name ObjectMeshShopItemConfig
## Objects domain, the 3D meshes of the small items the shops and special rooms give up
## (`item_shop_mesh.gd`, `docs/stacked-items.md` SI16): how tall each stands. A `class_name` holder
## of `static var`s, read as `ObjectMeshShopItemConfig.<name>` (ADR 0003). Lengths are 2D pixels
## (42.3 px a metre). A piece's own `art_opts.height` overrides its kind's. The instruments and the
## syringe lie within a step (`DoorFallConfig.step_over`, 10 px): a walker steps over one.

## A till: its body (12) and the keys on it (0.8).
static var till_height: float = 12.8
static var jar_height: float = 9.0
## A cart's diagnostic screen: its body (the lit pane lies 0.3 on it).
static var screen_height: float = 3.0
static var pack_height: float = 9.0
## A row of scalpels and clamps laid in a tray.
static var instruments_height: float = 0.8
static var syringe_height: float = 0.8
## The cyberware on the ripperdoc's shelf (`CyberwareShelf`): an arm (its joint stands 4 up), an
## eye (a ball), a chip with its pins, a jar.
static var cyber_arm_height: float = 4.0
static var cyber_eye_height: float = 6.0
static var cyber_chip_height: float = 1.2
static var cyber_jar_height: float = 6.0
## A run of bottles in a fridge and of packs in a machine or on an aisle: the stock's own height
## (a carrying row's `height`, set by `ShopStock`, overrides it).
static var bottles_height: float = 17.0
static var snacks_height: float = 9.0
