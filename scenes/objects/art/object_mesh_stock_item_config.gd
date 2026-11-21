class_name ObjectMeshStockItemConfig
## Objects domain, the 3D meshes of the loose things the shelves and the stockroom give up
## (`item_stock_mesh.gd`; `docs/stacked-items.md` SI13): how tall each kind stands. A `class_name`
## holder of `static var`s, read as `ObjectMeshStockItemConfig.<name>` (ADR 0003). Lengths are 2D
## pixels (42.3 px a metre). A piece's own `art_opts.height` overrides its kind's (a loose crate of
## a stack is 20, a book on a shelf is as tall as its board's room allows). A pallet and a pair of
## shoes lie within a step (`DoorFallConfig.step_over`, 10 px): a walker steps over them.

## A wooden pallet (a deck of slats on stringers) and a shrink-wrapped box on it.
static var pallet_height: float = 5.0
static var wrapped_box_height: float = 40.0
## A standing book (the default when no height is given), a pair of shoes.
static var book_stood_height: float = 16.0
static var shoes_height: float = 6.0
## A pot (the hotplate's plate and pan are `ObjectMeshKitchenConfig.hotplate_*`).
static var pot_height: float = 10.0
