# Emptied pieces: `PieceCarries` (`scenes/objects/art/piece_carries.gd`)

The schema of what a piece carries (D21, `docs/stacked-items.md` SI13). A piece whose look would build loose things in (shelf books, shelving
boxes, shoes, a crate stack's crates, a pallet's wrapped boxes, a hotplate's plate and pan) builds none of them: they are items (rule 9) set where
they were drawn. **This file is the schema**; the first user is `RoomItems.carry` (World-Gen), which sets each row with `ObjectFactory.spawn_on(..., { rest_at })`.

## What says a piece carries

`PieceCarries.carries(definition)`: the catalogue row has `carries`, or it is a shelf with `art_opts.loose` (rows from `ShelfLoose.rows(spec)`).
`PieceCarries.canonical(definition, spec)` gives the rows in the piece's canonical frame; `PieceCarries.rows(definition, base)` the placed rows.

## A catalogue row (`carries`, canonical frame)

`{ key, at: Vector2, size: Vector2, lift, height, color, weight, maybe, on_top }`

- `key`: the item's catalogue key (`ItemsCatalog` / `LooseStockCatalog` / `HomeItemsCatalog` / `ShopItemsCatalog`: `crate`, `pallet`, `book_stood`, `pot`, `till`, `pack`, …).
- `at`: the item's centre in px from the piece's centre, x across, the front toward +y, before the piece's turns.
- `size`: footprint in px in that frame (turned with the piece).
- `lift`: px above the floor the item rests at (its `rest_at`); `height`, `color`, `weight`, `spines` (a run of books): what differs from the item's catalogue row.
- `on_top: true` (the home tops, SI14: a desk's monitor, keyboard, mug and papers, a counter's board): no `lift`: the item rests on the piece's top under it (`ObjectFactory.top_at`: a counter's slab, not its backsplash; on what already lies there) and has the catalogue item's size unless the row says `size` (a book is 12 by 9, lying landscape, as its prop was); its `color` is the prop palette's and is drawn as given (`art_opts.plain`, set by `PieceCarries.patch_of` for every `on_top` row: the mesh does not grade it to the run-down look); a desk's monitor takes the desk's neon (`RoomItems.carry`: its lit edge is an emissive glow of the rig); `at` is where the old painter drew the prop (its unit point through the painter's rect inset 3 px). `HomeItemsCatalog` has the kinds.
- `maybe: true`: the row is there for about half the pieces, by `hash([base.position, key, lift]) % 2` (a seed's layout says which; a crate stack's third crate).

## A placed row (`PieceCarries.rows`)

`{ key, at, rotated, size, lift, on_top, patch }`: `at` a plan point in the space the piece's `position` is in (`base.position + at.rotated(turns * 90 deg)`), `rotated` true for an odd
number of turns, `size` the footprint (canonical), `lift` px above the floor, `patch` the fields to apply to the catalogue row (`PieceCarries.patched(item, patch)`:
`size`, `color`, `weight`, and `height` / `spines` in `art_opts`). Placed items are flagged `carried: true` (what `options_for` and the nav read).

## Rules

- A carrying piece's `PieceHeights` leaves its contents out; a place with `carries` and no art (`crate_stack`, `wrapped_pallet`) has mass 0.
- A shop's fridge, snack machine and aisle are hollow too (`ShopHollow`, stock rows `ShopStock`, a glass front part the round meets as glass: `docs/stacked-items.md` SI16).
- The ripperdoc's cyberware shelf is hollow too (`CyberwareShelf`: posts and a board per tier; rows `cyber_arm`, `cyber_eye`, `cyber_chip`, `cyber_jar`, `plain` colour; SI16).
- A shelf is hollow (`ShelfMesh.hollow_parts`: boards, top, sides 4 px, back) and moves as the solid box of its extent (`PieceBody._as_solid`).
- Items taller than `step_over` that a place carries carve a nav hole like a floor stack (`navigation/house_items_carve_like_pieces`).
- New carrying row: add it to the piece's catalogue row and a test in `tests/objects/` (`emptied_*`), the `old_looks` test sets it beside the old look.

**Shop pieces (SI16).** A fridge's, snack machine's or aisle's `ShopHollow` and the cyberware shelf's `CyberwareShelf` answer `EnvironmentObject.get_surface_at_point(height, point)` (a round meets the glass front as glass, else `get_surface()`: interface 3); glass is not transparent, sight stops at it as at the old solid piece. The cyberware shelf steps up in three columns so every item shows from above. Their `art_opts.loose: true` is only the gate `PieceCarries.carries` reads (a piece with it carries); that they are hollow is by kind (`ShopHollow.has`, `CyberwareShelf.has`), so there is no solid variant.

**The shops' hollow pieces** (SI16). `ShopHollow` (a fridge, a snack machine, a shelf aisle: parts round open bays, a glass front part that is a collider and not drawn, `surface_at`), `CyberwareShelf` (posts and a board per column, items open to the camera) and `ShopStock` (the rows of bottles and packs; `windows` cuts the fridge's and machine's lit glow front, `ShopMesh._glass`, where each item stands, so the stock shows through; the machine's pane is flush with its face and each pack's window holds a lit tile of its colour, `ShopMesh._pack_faces`, `faces`) are their shape; `PieceBody._as_solid` moves them as the solid box. The old pieces are kept as `tests/_art/old_*.gd` and are the oracle of `art/shop_pieces_lit_windowed` (it reads the live tunables).
