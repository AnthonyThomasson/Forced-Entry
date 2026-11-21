class_name WorldGenItemConfig
## Tuning for the small items placed on tops and the floor stacks (`scenes/worldgen/room_items.gd`,
## `docs/stacked-items.md` SI9). A `class_name` holder of `static var`s, read as
## `WorldGenItemConfig.<name>`; there is no instance and no autoload. What goes on which piece is
## data in `ItemsCatalog` (`TOPS`, `TOPS_BY_ART`, `FLOOR`).

## Whether a generated house is built with its items (the test switch `worldgen.items`): on, as in
## a match; off, the tops and floors stay bare.
static var enabled: bool = true
## A flat top gets items with this chance (a few per top: about half of them), 1 to `top_max` of
## them.
static var top_chance: float = 0.5
static var top_max: int = 3
## A plate or a book is stacked on one already set down on its top with this chance.
static var stack_chance: float = 0.3
## Spots tried for each item or floor stack before it is dropped.
static var tries: int = 12
## How far (px) an item's edge stays in from its top's edge, and from another item.
static var edge: float = 3.0
static var spacing: float = 2.0
## A floor stack stays this far (px) from solid furniture, a doorway box and another stack, so a
## walker keeps a lane round it.
static var floor_clear: float = 22.0
