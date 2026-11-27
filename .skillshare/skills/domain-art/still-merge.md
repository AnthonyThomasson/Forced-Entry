# The still world, merged (`mirror/still_merge.gd`, interface 27)

`MeshCarrier.merge` (`StillMerge`) is offered every still mesh it carries (no update hook, turn, rider or `seen_first`
group, so no door, vehicle or character). `build_all` copies those that may join into the chunk of their square of
ground (`MergeChunk`: one rendering-server instance, no node, so tree walks never meet it) and hides each one's own
instance **in the rendering server only**: the node, its `visible`, layers and parameters stay, so everything that reads
or writes them goes on. Numbers: `MirrorMergeConfig`.

**One build, none after it.** `build_all` runs as the view is built (the end of `View3D.light_world`, after the lights
set the sun's caster layers; 133 ms in a match's district, headless). After it `offer` does nothing and no chunk is built or
rebuilt, so no played frame pays for one. What was not taken draws itself for the whole match:

- a piece still settling: in a real match about 600 meshes, most of them items set down on another piece's top;
- what moved since (shoved, knocked down, a layer changed) and what was built since (a dented piece's new mesh, a
  rebuilt wall segment);
- fewer than `chunk_members` of one square, casting and layers.

The price (10v10 district, seed 23, view built at the match's start, 2560 x 1440, about 15 s in): 397 visible draws
and 0.37 ms of render CPU, against 231 and 0.20 ms with chunks built in play too, and 663 and 0.53 ms unmerged. Those
builds landed in played frames (up to 0.9 ms of script each), which is why there are none.

**The rule for anyone who changes a mesh:** a move, a show or hide, and leaving the tree are heard by an internal `Watch`
child. Anything else that changes its pixels or passes must go through a `MeshNodes` writer or call
`MeshNodes.changed(node)` after the write (instance uniforms, `cast_shadow`, `layers`, `material_override`). A mesh
resource edited or swapped in place on a still mesh is heard by neither: build a new node, or call `changed`.

- A change is judged in the same frame, in `_process` (priority 1000) and again on `frame_pre_draw`: the member's vertex
  range collapses and the node draws itself. The copied look again: it returns. Moved, other layers or freed: forgotten.
- Never merged: a mesh ever given a glow, a mirrored one, a material `toon_merged.gdshader` has no kind for, one on an
  awake rigid body.
- Chunk vertices are in world coordinates. The corners round to floats another way than the GPU places a mesh of its
  own, so the picture differs in single art pixels on an edge or between texels, now and then an outline for a surface.
  The same-picture test allows 512 differing pixels on each of its held district frames; frames of a 10v10 fight at
  2560 wide measured up to about 900 of such flips (552 and 888), nothing stale.
- A test that changes a mesh's material and looks at the picture, or demands the same picture to the pixel, turns
  merging off before the build (`tests/_render/frozen_frame.gd`, the `general/twin_*_picture` tests). One that builds
  again calls `release`, offers, then `build_all`.

Tests: `tests/art/still_merge_built_with_the_view_test.gd`, `still_merge_none_built_in_play_test.gd`,
`still_merge_hears_every_writer_test.gd`, `still_merge_follows_changes_test.gd`, `still_merge_changes_windowed_test.gd`,
`still_merge_same_picture_windowed_test.gd`; the spare after the build:
`tests/art/toon_atlas_reserved_after_the_build_test.gd`.
