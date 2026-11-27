# The mesh hook and the vision hook (`scenes/art/mirror/`, `scenes/art/post/`, interface 27)

The full rules behind interface 27's hook; the how-to a mesh job follows is `meshes.md`.

## `MeshCarrier.builders`: key -> `Callable(node) -> Node3D`

Set before `carry(root)`; Main's `main_view3d.gd` `_register_meshes()` calls each domain's `register(carrier.builders)` (Main knows every domain; Art imports none).
The node a builder returns is in **3D units** (Art's kit converts from px, `RenderConfig.unit` once), in the **body's frame**: its origin is the body's, and the
carrier hangs it on the body's twin (`TwinSpace.twinned`), which stands and turns as the body does (a character's mesh is turned by the carrier: a 2D turn clockwise is `-angle` about +y); nothing writes it. A body with no twin (a non-solid piece) has it placed once, a child of the carrier.

- **Keys.** The kinds `MeshKinds.WALL`, `DOOR`, `CHARACTER`, `VEHICLE`, `FURNITURE` (every `ObjectArt` piece), `FLOOR`. A finer key wins over its kind and is for furniture and floors alone:
  `MeshKinds.furniture_key(art)` (`"furniture:table"`, read as the piece's `look.art`) and `MeshKinds.floor_key(art)` (a floor's `art`), so a furniture job registers per id. A body with
  no key, or whose builder returns null, is shown by nothing (no stand-in box).
- **Floors** are not bodies: the builder gets the floor and returns its mesh in a frame whose origin is the floor's corner, carried on the floor's twin, once, when the space twins it.
- **`track(node: Node2D, builder) -> Node3D` and `track_group(group, builder)` are the `MeshFollower`'s** (Main's view: floor stencils and lying items): `track` shows one node in the tree that is no physics body
  (a dropped item, a stencil) by the mesh `builder(node)` makes (null: nothing tracked), in a frame with the node's origin; `track_group` every node of `group` under the followed world, those already there
  (also when called before `follow()`) and each as it joins, on the next frame once its `_ready` has run; the spawning domain only `add_to_group`s. Written only when the node's transform changed, hidden
  while its `visible` is false, freed when it leaves the tree. A node is built once; a null builder leaves it unshown until `remirror`. A node must be in the group by the end of its `_ready`; one that joins
  later is taken up by `follower.remirror(node)`. While a group is tracked every `Node2D` that enters the tree is queued (a dictionary entry), so for hundreds of short-lived pieces a second (a casing, a spark)
  use `MeshNodes.batch` with a `MeshPool` (its places taken and given back, no hole; Projectile's `ShotLayer` does) instead of a node and a mesh each. `follower.md`.
- Tests: `tests/art/mirror_mesh_hook_test.gd`, `mirror_hook_keys_test.gd`, `mirror_mesh_lifecycle_test.gd`, `mirror_follows_rebuilt_colliders_test.gd`.

**Still meshes** (`still_rows.gd`). A mesh with no `mirror_update`, turn or rider, of a body in none of `MirrorVisionConfig.seen_first` (nearly every piece of a district), is
not looked at each frame: the body's `visibility_changed`, `ViewLayers.CHANGED` or the mesh's `tree_exiting` wakes it for the full look, and it stays woken while the body is on `MOVING`, marked moving or out
of the tree. A shown rule that depends on anything else needs its own signal there. Test: `tests/art/mirror_still_piece_shown_rules_test.gd`.

**Off the camera** (`mirror_reach() -> float`, optional): a mesh that says how far round its origin all it draws stays (3D units), none of it casting a shadow, has `mirror_update` called only while the
viewport camera reaches that sphere, asked again after the camera rig moves (`MeshCarrier.AFTER_CAMERA`). Test: `tests/art/mirror_pose_off_camera_test.gd`.

## Keeping a mesh in step: which to use

| The mesh changes by | Use |
|---|---|
| a **pose** that changes often without the 2D transform changing (a limb, a facing, a wheel's spin, an open lid) | a `mirror_update(body: Node2D)` method on the mesh node: called each frame the mesh **shows** (not while hidden or off camera (`mirror_reach`); a sleeping or static body's too), after the transform is written. Set transforms of the node's parts there, cheaply: nothing is rebuilt. |
| a **shape** that changes now and then (a dent, a new outfit, a posture that changes the solids) | `MeshCarrier.remirror(node)` (a body or floor; a tracked node: `MeshFollower.remirror`): builds the mesh again at once through its builder and frees the old one. The domain asks Main to call it from the signal it already has (a hit, a posture change); `MeshCache` makes a repeat cheap. |
| a **shape that follows the body's own outlines** (a wall's segments) | nothing on the node: the carrier builds a mesh again only on `remirror` or a body's `reshaped`, never because a collider came or went (a body holds no 2D shape); the mesh listens to its body's own signal (`segment_rebuilt`) and replaces what changed. |
| a mesh of one node that needs neither | a `_process` on the mesh node itself also works (it runs hidden too), the simplest thing for a spinning fan; nothing in the mirror is needed. |

- **A mesh unique to one node** (a dented panel, a posed limb) is `MeshKit.build()` straight into `MeshNodes.instance`, freed with its node: only meshes many pieces share go through `MeshCache`
  (bounded by `MeshKitConfig.cache_limit`, the one asked for longest ago dropped), and a decal's material and texture go with its last decal.
- **Death.** A carried body with a `died` signal has its mesh hidden and no longer looked at when it dies (it stays on its twin). A mesh node with `on_body_died(body: Node2D) -> bool` decides: true keeps it shown and
  shown (and `mirror_update` running), so the same mesh can switch to a dead pose: Character's `BodyMesh` does, following the 2D ragdoll's joints. A separate set of parts is a group `track_group`ed by the follower with
  their own builder.
- **Reparenting.** A tracked node (the follower's `track`, `track_group`) survives `reparent` or a `remove_child` and re-add: out of the tree its mesh is hidden and not followed; back in, shown and placed. Freed out
  of the tree, its mesh is freed with it; one kept out (a pool) keeps its hidden mesh and a row, so a pool is bounded. A queued-free node's mesh goes at once. A body (carried) that leaves the tree loses its mesh and gets a new one when it is twinned again.
- **A seated character's mesh is hidden:** the carrier asks the body's `use.is_riding()` (duck-typed); no collision shape is read.
- **A moved body** is followed by its twin, which `TwinSpace` writes when the body moves (a rigid body, a character, a driven body: interface 29), so a bare node a script moves is followed only if it is a plan handle the space twins. A followed node is shown by its own `visible`, not `is_visible_in_tree`: under a hidden parent it stays shown, so hide the node itself (the 2D `World` is hidden in 3D, so the parent is hidden always).

## The vision hook

The player's view in 3D is global shader uniforms the toon shaders and the outline read: `vision-hook.md`.

**Fade and glow** (per instance, default off, a branch the shader does not take): `MeshNodes.fade(node, amount)` (1 whole, 0 gone) drops pixels by an ordered dither of the picture's own pixels, so a wall between
the camera and the player thins out as pixel art with no blending or sorting; `MeshNodes.glow(node, color, strength)` is a glow whatever the light (a lamp, a screen, a flash), dimmed by the vision mask. Both work on
a toon node and a decal, not a batch part. **A wall that must fade is its own instance** (never merged into one mesh with its neighbours): `WallFade` fades them one by one (`domain-art`). Test:
`tests/art/toon_decal_fade_glow_windowed_test.gd` (a decal takes the shadow too). **Figure:** `MeshNodes.figure(node, on)` marks a character's part for the pixel post (a silhouette-only outline, no creases); a body without `BodyMesh` (the proxy capsule) is not marked and keeps its creased outline. Test (windowed: shaders compile only there): `tests/art/toon_vision_hook_windowed_test.gd`.
