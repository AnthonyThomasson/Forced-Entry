# Flat (albedo-only) paint: `PixelArt.render_flat`

The 3D render (#193) textures its meshes with the 2D painters' art and lets the toon lights shade it, so the texture must carry
no light of its own. `render_flat(painter, size, color, opts := {})` paints the same painter on a canvas whose `light` is
`Vector2.ZERO`, in the painter's canonical frame (front +y).

- **No baked light.** `bevel`, `bevel_relative` (`d = normal . light = 0`, under the 0.3 threshold) and `cast_shadows` (its step is
  zero) do nothing; `glare` returns early at zero light (a ceramic or glass finish keeps its grain/speckle, loses the specular).
  The finishes (grain, brushing, fleck, weave) and `Decay` stay: they are albedo detail. Random detail is seeded by the same
  `_key` as the lit paint, so it matches the 2D art's.
- **Canonical, one texture.** No facing turn and no lighting step: the texture is the same whatever way the piece turns, so the
  caller turns the mesh, not the art. The key is `_key(...) + "|flat"`; 2D keys end `|f<turns>` or `|a<angle>`, so they and their
  pixels are untouched (`tests/art/flat_paint_albedo_test.gd`).
- **Emissive twin.** `emissive_flat(...)` is what the painter drew `glowing`, in the art's colours (null when nothing glows), filed
  from the same paint.
- **Prewarm.** `PixelArt.warm` takes `{ painter, size, color, opts, "flat": true }` (no `facing`) beside `render` requests;
  `finish_warming` files them. The worker paints flat requests the same way (`_paint_images`).
- **Painters that read `c.light` directly** degrade to a fixed side: cabinet takes its neutral front tone, plant its fixed lit
  side, sofa its fixed arm ridge; shadow_painter drags by zero (not meshed).
- **Residue the flag cannot remove:** tones a painter picks by hand (`t.light` rim lines in table, wall, counter, head…) and
  its own `outline()` rings stay painted. A painter that must drop them reads `c.light == Vector2.ZERO` itself.
