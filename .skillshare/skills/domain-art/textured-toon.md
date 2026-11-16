# The textured toon (`post/toon_tex.gdshader`, `ToonMaterial.textured`, `MeshNodes.textured`)

The 2D painters' art, painted unshaded, on a mesh, shaded by the toon bands. One planar projection straight down in MODEL space, `uv_rect` (an instance uniform, set in units from the px `rect`) the footprint the art covers; a top face (normal up) shows the art, a side face the art's edge texels stretched down and darkened a step (`MeshKitConfig.textured_side_dim`), a clear texel the vertex colour; `opts.tiled` repeats the art (floor, road); `opts.cutout` draws nothing where the art is clear (a flat sprite laid over solids, as a character's head art over its dome). A material per texture, tiling and cut-out (a weak cache like the decal's: instance uniforms cannot be samplers), so draw calls are unchanged (one per node) and what grows is materials: `ToonMaterial.textured_count()`. An opaque texel is the art times `base_color` only (the vertex colour is NOT multiplied in: a mesh with coloured parts, as a furniture mesh, keeps its tones for where the art is clear); tint with `base_color`.

The light, bands, fade and vision read are `toon_common.gdshaderinc`, shared with `toon.gdshader` and `decal.gdshader`; `toon_surface.gdshaderinc` holds `base_color`, `figure`, `emissive`. Tests: `tests/art/mesh_textured_suite.gd`, `toon_tex_windowed_test.gd` (`TEXTOON_SHOTS=<dir>` saves the shots).

## Rules and limits

- **Top or side:** a face is a top when its model normal has `y > 0.5` (a slope within 60 degrees of flat), a side otherwise; an underside (never seen from above) takes the side rule. The kit's faces are flat, so it is decided per face (`flat` varyings). A tiled side wraps along the axis it runs along (by its normal's larger horizontal part), so a long road or wall side repeats the art's edge.
- **Model space:** the art follows the node's yaw, scale and stretch (model space is the rest pose). A `Skeleton3D`-skinned mesh would slide the art over its bones: none is used today.
- **Units:** `uv_rect` is baked from `RenderConfig.unit` when `textured` is called, not read live; call it again after a unit change. One `uv_rect` per node, so a MultiMesh's parts share it.
- **Cost:** never call `textured` per frame with a fresh texture: each new texture is a new material and a shader parameter set. Hold the texture (a piece's flat render is cached by `PixelArt`) and call once when the mesh is shown.
- **Tint:** a node never tinted is white; a tint it already has stays unless `opts.tint` names one.
