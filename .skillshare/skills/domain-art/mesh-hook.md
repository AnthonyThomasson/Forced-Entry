# The mirror's mesh hook and the vision hook (`scenes/art/mirror/`, `scenes/art/post/`, interface 27)

The full rules behind interface 27's hook; the how-to a mesh job follows is `meshes.md`.

## `WorldMirror.builders`: key -> `Callable(node) -> Node3D`

Set before `mirror(root)`; Main's `main_view3d.gd` `_register_meshes()` calls each domain's `register(mirror.builders)` (Main knows every domain; Art imports none).
The node a builder returns is in **3D units** (Art's kit converts from px, `RenderConfig.unit` once), in the **body's frame**: its origin is the body's, and the
mirror turns it with the body (a 2D turn clockwise is `-angle` about +y). It follows the body's whole transform, written only when it changed, and replaces every proxy of that body.

- **Keys.** The kinds `MirrorProxy.WALL`, `DOOR`, `CHARACTER`, `VEHICLE`, `FURNITURE` (every `ObjectArt` piece), `FLOOR`. A finer key wins over its kind and is for furniture and floors alone:
  `MirrorProxy.furniture_key(art)` (`"furniture:table"`, read as the piece's `look.art`) and `MirrorProxy.floor_key(art)` (a floor's `art`), so a furniture job registers per id. A body with
  no key, or whose builder returns null, keeps its proxy.
- **Floors** are not bodies: the builder gets the floor and returns its mesh in a frame whose origin is the floor's corner, placed once when `mirror()` runs or when the floor joins the
  `floors` group mid-match, never followed.
- **`track(node: Node2D, builder) -> Node3D`**: shows one node in the tree that is no physics body (a dropped item, debris, a bullet, a casing) by the mesh `builder(node)` makes (null: nothing
  tracked), in a frame with the node's origin. Same rules as a body: written only when its transform changed, hidden while its `visible` is false, freed when it leaves the tree. A node's
  height off the ground is its mesh's own.
- **`track_group(group, builder)`**: every node of `group` under the root, those already there (also when called before `mirror()`) and each as it joins, on the next frame once its `_ready` has run;
  the spawning domain only `add_to_group`s, never holds the mirror. A physics body of a tracked group is shown by that builder, not by proxies. A node is built once; a builder that gives null for it
  leaves it unshown.
- Tests: `tests/art/mirror_mesh_hook_test.gd`, `mirror_hook_keys_test.gd`.

## The vision hook (phase 3's mask; `ToonMask`, `toon.gdshader`, `decal.gdshader`)

Three global shader uniforms, declared by `ToonMaterial.make()` / `ToonMaterial.decal()` through `ToonMask.install()`: `vision_mask` (a texture's red channel: 1 seen, 0 unseen),
`vision_mask_xf` (world `(x, z)` in 3D units to the mask's uv) and `vision_unseen` (the brightness an unseen spot keeps; **1 by default: everything visible**, whatever the mask holds).
`ToonMask.set_mask(texture, world_rect_px, unseen_brightness)`, `clear()`, `mask_active()`, `mask_world_rect()` are the whole interface. The mask is read only while `vision_unseen` is below 1
(a uniform branch: the default costs nothing) and scales the light, not the albedo (the highlight term adds `1 - albedo`, which a dimmed albedo would brighten). Art builds no mask; the
outline pass is not masked. Test (windowed: shaders compile only there): `tests/art/toon_vision_hook_windowed_test.gd`.
