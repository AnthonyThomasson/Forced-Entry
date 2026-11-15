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
  the spawning domain only `add_to_group`s, never holds the mirror. A physics body of a tracked group is shown by that builder, not by proxies. A node is built once; a builder that gives null for
  it leaves a physics body its proxies and any other node unshown, and is not asked again until `remirror`. A node must be in the group by the end of its `_ready` (the mirror looks next frame); one that joins later is taken up by `mirror.remirror(node)`. While a group is tracked every `Node2D` that enters the tree is queued (a dictionary entry),
  so for hundreds of short-lived pieces a second (a casing, a spark) use `MeshNodes.batch` instead of a node and a mesh each.
- Tests: `tests/art/mirror_mesh_hook_test.gd`, `mirror_hook_keys_test.gd`, `mirror_mesh_lifecycle_test.gd`.

## Keeping a mesh in step: which to use

| The mesh changes by | Use |
|---|---|
| a **pose** that changes often without the 2D transform changing (a limb, a facing, a wheel's spin, an open lid) | a `mirror_update(body: Node2D)` method on the mesh node: called each frame the mesh **shows** (not while hidden; a sleeping or static body's too), after the transform is written. Set transforms of the node's parts there, cheaply: nothing is rebuilt. |
| a **shape** that changes now and then (a dent, a new outfit, a posture that changes the solids) | `WorldMirror.remirror(node)` (a physics body, a floor or a tracked node): builds the mesh again at once through its builder and frees the old one. The domain asks Main to call it from the signal it already has (a hit, a posture change); `MeshCache` makes a repeat cheap. |
| a **shape that follows the body's own colliders** (a wall's segments) | `follows_shapes() -> true` on the mesh node: the mirror does not build it again when a collision shape comes or goes (a shape queued to be freed never does); the mesh listens to its body's own signal and replaces what changed. |
| a mesh of one node that needs neither | a `_process` on the mesh node itself also works (it runs hidden too), the simplest thing for a spinning fan; nothing in the mirror is needed. |

- **A mesh unique to one node** (a dented panel, a posed limb) is `MeshKit.build()` straight into `MeshNodes.instance`, freed with its node: only meshes many pieces share go through `MeshCache`
  (bounded by `MeshKitConfig.cache_limit`, the one asked for longest ago dropped), and a decal's material and texture go with its last decal.
- **Death.** A mirrored body with a `died` signal has its mesh hidden and no longer followed when it dies. A mesh node with `on_body_died(body: Node2D) -> bool` decides: true keeps it shown and
  following (and `mirror_update` running), so the same mesh can switch to a dead pose: Character's `BodyMesh` does, following the 2D ragdoll's joints. A separate set of parts is a group `track_group`ed with
  their own builder.
- **Reparenting.** A tracked node (`track`, `track_group`) survives `reparent` or a `remove_child` and re-add: out of the tree its mesh is hidden and not followed; back in, shown and placed. Freed out
  of the tree, its mesh is freed with it; one kept out (a pool) keeps its hidden mesh and a row, so a pool is bounded. A queued-free node's mesh goes at once. A body (not tracked) that leaves the tree loses its mesh and gets a new one when it returns.
- **Own meshes hide with their body's shapes:** while a body has collision shapes and every one is disabled (a character seated in a vehicle) its own mesh is hidden, as its proxies are.
- **Not followed:** a `StaticBody2D` moved by a script is written once, so it does not follow (use an `AnimatableBody2D`, or give its mesh a `mirror_update`, even an empty one, and it is read each frame). A
  tracked node is shown by its own `visible`, not `is_visible_in_tree`: under a hidden parent it stays shown, so hide the node itself (the 2D `World` is hidden in 3D, so the parent is hidden always).

## The vision hook (phase 3's mask; `ToonMask`, `toon.gdshader`, `decal.gdshader`)

Three global shader uniforms, declared by `ToonMaterial.make()` / `ToonMaterial.decal()` through `ToonMask.install()`: `vision_mask` (a texture's red channel: 1 seen, 0 unseen),
`vision_mask_xf` (world `(x, z)` in 3D units to the mask's uv) and `vision_unseen` (the brightness an unseen spot keeps; **1 by default: everything visible**, whatever the mask holds).
`ToonMask.set_mask(texture, world_rect_px, unseen_brightness)`, `clear()`, `mask_active()`, `mask_world_rect()` are the whole interface. The mask is read only while `vision_unseen` is below 1
(a uniform branch: the default costs nothing) and scales the light, not the albedo (the highlight term adds `1 - albedo`, which a dimmed albedo would brighten). Art builds no mask; the
outline pass is not masked.

**Fade and glow** (per instance, default off, a branch the shader does not take): `MeshNodes.fade(node, amount)` (1 whole, 0 gone) drops pixels by an ordered dither of the picture's own pixels, so a wall between
the camera and the player thins out as pixel art with no blending or sorting; `MeshNodes.glow(node, color, strength)` is a glow whatever the light (a lamp, a screen, a flash), dimmed by the vision mask. Both work on
a toon node and a decal, not a batch part. **A wall that must fade is its own instance** (never merged into one mesh with its neighbours): `WallFade` fades them one by one (`domain-art`). Test:
`tests/art/toon_decal_fade_glow_windowed_test.gd` (a decal takes the shadow too). **Figure:** `MeshNodes.figure(node, on)` marks a character's part for the pixel post (a silhouette-only outline, no creases); a body without `BodyMesh` (the proxy capsule) is not marked and keeps its creased outline. Test (windowed: shaders compile only there): `tests/art/toon_vision_hook_windowed_test.gd`.
