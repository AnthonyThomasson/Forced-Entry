# The still world, merged (`mirror/still_merge.gd`, interface 27)

`MeshCarrier.merge` (`StillMerge`) is offered every still mesh it carries (no update hook, turn, rider or `seen_first`
group). A settled one is copied into the chunk of its square of ground (`MergeChunk`: one rendering-server instance, no
node, so tree walks never meet it) and its own instance is hidden **in the rendering server only**: the node, its
`visible`, layers and parameters stay, so everything that reads or writes them goes on. Numbers: `MirrorMergeConfig`.

**When chunks are built** (a build in a played frame is a long frame): `build_all` builds every chunk as the view is
built (the end of `View3D.light_world`, after the lights set the sun's caster layers; about 0.2 s for a 10v10 district,
111 chunks). In play only what moved, woke or was built again waits (a knocked piece come to rest, a dented one): one
chunk a frame at most, of `play_vertices`, from three meshes up.

**The rule for anyone who changes a mesh:** a move, a show or hide, and leaving the tree are heard by an internal `Watch`
child. Anything else that changes its pixels or passes must go through a `MeshNodes` writer or call
`MeshNodes.changed(node)` after the write (instance uniforms, `cast_shadow`, `layers`, `material_override`). A mesh
resource edited or swapped in place on a still mesh is heard by neither: build a new node, or call `changed`.

- A change is judged in the same frame, in `_process` (priority 1000) and again on `frame_pre_draw`: the member's vertex
  range collapses and the node draws itself. The copied look again: it returns. Moved, other layers or freed: forgotten,
  and offered again once it rests. A chunk is never rebuilt.
- Never merged: a mesh ever given a glow, a mirrored one, a material `toon_merged.gdshader` has no kind for, one on an
  awake rigid body.
- Chunk vertices are in world coordinates. The corners round to floats another way than the GPU places a mesh of its
  own, so the picture differs in single art pixels on an edge or between texels: under 512 of a frame.
- A test that changes a mesh's material and looks at the picture turns merging off first
  (`tests/_render/frozen_frame.gd` does).

Tests: `tests/art/still_merge_built_with_the_view_test.gd`, `still_merge_follows_changes_test.gd`,
`still_merge_changes_windowed_test.gd`, `still_merge_same_picture_windowed_test.gd`.
