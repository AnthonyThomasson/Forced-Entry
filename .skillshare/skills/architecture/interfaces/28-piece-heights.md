28. **Objects → AI, Projectile: real heights, `PieceHeights`** (`objects/art/piece_heights.gd`, static, `RefCounted`; the heights themselves are the `ObjectMesh*Config` holders'
    values, so a mesh and its height are one number; tests `tests/objects/piece_heights_test.gd`). Not read by gameplay yet: the 0 to 100 catalogue `coverage` still decides shots
    until the real-cover jobs cut over; AI cover picking, the bullet and the blast then read these tops.
    - `PieceHeights.top_of(definition: Dictionary) -> float`, `base_of(definition) -> float`, `parts_of(definition) -> Array[Dictionary]`: for a catalogue row (`WorldGen.object_definition(key)`:
	  `size`, `art`, `art_opts`), px above the floor, 1 px a 3D unit, 42.3 px a metre (`BodyHeights`, interface 11). A **part** is `{ base, top, rect }`: where it starts and ends and the share
	  of the footprint it covers (`rect` in the footprint's unit square, the painter's canonical frame: back-left corner (0, 0), x across, the front toward +y). `top_of` is the highest part's
	  top, the piece's mass (a prop on it, a bowl on a bar or a coat rack's hat, is left out); `base_of` the lowest part's base (a mirror hangs at 46, an awning's valance stands at 80).
	  Multi-part: a sofa (seat, two arms, back), a chair (seat, back), a bed (mattress, headboard), a counter (top, backsplash), a noodle booth (seats, backs, table).
    - `PieceHeights.top_of_spec(spec) -> float`, `base_of_spec(spec) -> float`, `parts(spec) -> Array[Dictionary]` for a live piece's `FurnitureSpec.of(piece)`, and `spec_of(definition) -> FurnitureSpec`.
    - **Cost.** A lookup builds a small array from the holders and the mesh scripts' own `height_of` rules; no mesh is built. Referencing the class preloads the 13 mesh scripts it asks
	  (`TableMesh`, `CounterMesh`, ...): their code loads once with the script, which is what a match with the 3D view loads anyway; a caller reads a piece's heights once when it is
	  spawned or first needed and keeps them, not each query. Splitting the rules out of the mesh scripts would move every `height_of` the meshes share; not worth it until a caller's load time says so.
