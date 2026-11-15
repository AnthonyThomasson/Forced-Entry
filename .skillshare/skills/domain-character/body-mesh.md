# Character body: the 3D mesh (`body/art/body_mesh.gd`, `character_meshes.gd`, `CharacterMeshConfig`)

In the 3D render (#193) the mirror shows a living character by `BodyMesh`, a low-poly body of Art's mesh kit (`domain-art/meshes.md`), in place of the proxy capsule; `CharacterMeshes.register(builders)` puts its builder under the `CHARACTER` hook key and Main's `_register_meshes()` calls it. It reads what the painters read, never a copy of it: the **joints** are `anatomy.rig()` (solved once per physics frame and shared with the 2D draw, so the body faces `pose`'s angles, holds what the hands hold, strides as the gait says and folds in a crouch by `CharacterPostureConfig`: P3), the **colours** are `visuals.dress` (shirt, pants, shoes, skin, each arm segment, each glove) and its resolved look (`PixelArt.look_of(dress.head_opts)`: hair, cap or helmet, vest and plate colours, a pack). The parts are shared unit solids (a cylinder, a ball, a box through `MeshCache`) scaled and placed between the joints by `mirror_update(body)`, written only when a joint moved by more than `BodyMesh.MOVED` (0.2 px, under one pixel of the 3D picture; a direction by `TURNED` 0.02: a breath or a head's spring settling is a write a few times a breath, not every frame; the last pose is one array sized once, copied into); `mirror_update` first calls `dress.refresh(body.wardrobe)` (the 2D visuals refresh only a body inside the 2D cull rect, the 3D camera sees more; the call answers at once when nothing changed, and the visuals' own refresh then returns false: harmless in 3D), and a new look (`dress.look_key`) re-tints and shows or hides the optional parts (vest, plates, pack, hair, headwear, a boot's shaft) in place, no rebuild, and poses again (a hidden part is not placed: `_place` skips it). The rig's heights are the drawing's (a head 100 px up), so they are squeezed to `CharacterMeshConfig.height` (58, the how-to's standing character); the horizontal reach is the 2D body's. A seated body (shapes disabled) is hidden by the mirror's own rule; a dead one goes with its death (no `on_body_died`: the ragdoll and the held item are later jobs of their own). Tests: `tests/character/character_mesh_test.gd` (the seams), `character_mesh_windowed_test.gd` (`CHARMESH_SHOTS=<dir>` saves the pictures; windowed only).

**The parts** (23 `MeshInstance3D`s per character, one set of shared unit solids; `BodyMesh`'s index constants; the cylinder's `LIMB_SIDES` is 6 so a limb reads as a few wide bands, not stripes):

| Part | Solid | Shadow | Shown |
|---|---|---|---|
| `TORSO` (shirt), `VEST` | trunk cylinder (10 sides) | casts | the vest when the outfit has one |
| `PLATE` x2 (front, back) | box | none | a plate in its carrier |
| `PACK` | box | casts | the style's look has a pack |
| `HEAD` | ball | casts | always |
| `HAIR`, `HEADWEAR` (cap or helmet) | ball | none | hair when bare-headed and not bald; headwear when a cap or helmet is worn |
| `FACE` | box, a wide visor band across the front, near black on a light skin and near white on a dark one | none | always: how the head's facing reads |
| `UPPER`, `FORE`, `THIGH`, `SHIN` x2 | limb cylinder | casts | always |
| `HAND`, `FOOT` x2 | ball, box | none | always |
| `BOOT` x2 (a boot's shaft) | limb cylinder | none | boots worn |

Twelve parts cast a shadow (the trunk, vest, pack, head and the eight limb segments), eleven do not (the small ones: a shadow of a plate, a fist or a shoe adds draw cost the pixel post's resolution does not show). The head's size (`head_scale` 1.6) and the limbs' (`limb_scale` 1.4) are larger than the 2D art's so the body still reads at the game's default zoom; there the outline pass dominates a 30 px figure and the face band is lost, which only the outline weight (`PixelPostConfig`, Art) would change. The windowed test's pictures: standing, facing away and crouched, at zoom 3 and zoom 1.

