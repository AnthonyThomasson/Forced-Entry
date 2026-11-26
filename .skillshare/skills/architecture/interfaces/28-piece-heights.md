28. **Objects ↔ World Generation: real heights, `PieceHeights`, and carried items, `PieceCarries`** (`objects/art/piece_heights.gd`, static, `RefCounted`; the heights themselves are the `ObjectMesh*Config` holders'
    values, so a mesh and its height are one number; tests `tests/objects/piece_heights_test.gd`). Objects' twins (`ObjectTwins`, 29) and meshes are built from it, and World Generation's
    district pre-warm reads `spec_of`. Nothing outside Objects asks it in play: a bullet, a sight line, the AI's cover (`AgentCover`'s `is_cover`: `SightRay.top_of`) and a grenade's burst
    (`Explosion.shields`, `docs/grenades.md` G7) read the piece's twin, which holds these heights. There is no catalogue `coverage` number.
    - `PieceHeights.top_of(definition: Dictionary) -> float`, `base_of(definition) -> float`, `parts_of(definition) -> Array[Dictionary]`: for a catalogue row (`WorldGen.object_definition(key)`:
	  `size`, `art`, `art_opts`), px above the floor, 1 px a 3D unit, 42.3 px a metre (`BodyHeights`, interface 11). A **part** is `{ base, top, rect }`: where it starts and ends and the share
	  of the footprint it covers (`rect` in the footprint's unit square, the painter's canonical frame: back-left corner (0, 0), x across, the front toward +y). `top_of` is the highest part's
	  top, the piece's mass (a prop on it, a bowl on a bar, is left out; a hat on a coat rack is an item, a body of its own); `base_of` the lowest part's base (a mirror hangs at 46, an awning's valance stands at 80).
	  The eight small items (`ItemsCatalog`: plate 1.5 to crate 16 px) read `ObjectMeshItemConfig`; a plate, cup, bowl and book lie within a step (10 px, `DoorFallConfig.step_over`), a walk-over body (`docs/stacked-items.md`). Multi-part: a sofa (seat, two arms, back), a chair (seat, back), a bed (mattress, headboard), a counter (top, backsplash), a noodle booth (seats, backs, table).
    - `PieceHeights.top_of_spec(spec) -> float`, `base_of_spec(spec) -> float`, `parts(spec) -> Array[Dictionary]` for a live piece's `FurnitureSpec.of(piece)`, and `spec_of(definition) -> FurnitureSpec`.
    - **Cost.** A lookup builds a small array from the holders and the mesh scripts' own `height_of` rules; no mesh is built. Referencing the class preloads the 13 mesh scripts it asks
	  (`TableMesh`, `CounterMesh`, ...): their code loads once with the script, which is what a match with the 3D view loads anyway; a caller reads a piece's heights once when it is
	  spawned or first needed and keeps them, not each query. Splitting the rules out of the mesh scripts would move every `height_of` the meshes share; not worth it until a caller's load time says so.
    **What an emptied piece carries, `PieceCarries`** (`objects/art/piece_carries.gd`, static, `RefCounted`), read by World Generation (2) to set those things as items of their own (`docs/stacked-items.md` SI13; the row's fields: `domain-objects/carries.md`).
    - `PieceCarries.carries(definition: Dictionary) -> bool` — whether the piece of a catalogue row carries things (its
	mesh and art leave them out). `RoomFurnisher` counts such a piece's footprint with the solids, `ItemsCatalog`
	gives it no top items at random, and `RoomItems` and `DistrictPrewarm` skip every other piece.
    - `PieceCarries.canonical(definition: Dictionary, spec: FurnitureSpec) -> Array` — the carrying rows in the canonical
	frame of `spec`'s footprint (its own `carries`, else what a loose shelf, shop piece or cyberware shelf holds):
	`DistrictPrewarm` walks them at both orientations (`spec` from `PieceHeights.spec_of`).
    - `PieceCarries.rows(definition: Dictionary, base: Node2D) -> Array[Dictionary]` — the placed rows of the furniture
	node `base`, `{ key, at, rotated, size, lift, on_top, patch }` (`at` a plan point in `base.position`'s space): which
	`maybe` rows are there and which palette colour each has follow where the piece stands. `RoomItems.carry` sets them.
    - `PieceCarries.patch_of(row: Dictionary) -> Dictionary` — what a canonical row changes in its item's catalogue row
	(a placed row already holds it as `patch`).
    - `PieceCarries.patched(item: Dictionary, patch: Dictionary) -> Dictionary` — a copy of the item's catalogue row with
	the patch applied, what World-Gen hands `ObjectFactory.spawn_on` and `FurnitureArt.requests`.
    - `ObjectArtDecorConfig.prop_colors: Dictionary` — the prop palette (name to a `Color`, or to a list of them).
	`DistrictPrewarm` reads the list a row's `palette` names, to warm the item's art in every colour it can take.
