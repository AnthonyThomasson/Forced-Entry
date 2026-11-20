# The wall fade (`mirror/wall_fade.gd`, interface 27)

Side file of `domain-art`. #193 rule 9: walls, doors and tall pieces between the camera and a character fade so the character is never hidden; the rest stay whole.

## Parts

| File | Role |
|---|---|
| `wall_fade.gd` (`WallFade`, a `Node3D`) | The frame: the foci, the grid lookups, stepping the fades. Main's `View3D` makes it (`fade`; `rig`, `source`) and calls `listen(carrier)`. |
| `fade_book.gd` (`FadeBook`) | What it looks after: `watch`ed meshes, their units, a rebuilt segment, a freed mesh, the fade carried to a mesh built again. |
| `fade_grid.gd` (`FadeGrid`) | Where units are looked for: cells of `WallFadeConfig.cell` px, movable units re-filed by a polled slice. |
| `fade_unit.gd`, `fade_box.gd` (`FadeUnit`, `FadeBox`) | One faded thing (its instances, level and footprint) and the ray-to-footprint question. |
| `fade_hold.gd`, `fade_shadow.gd` (`FadeHold`, `FadeShadow`) | What a unit tells General's `FadedTwins` (its body, index and whether it is more than half faded, so the player's aim looks through its twin: `Pointer.aim_hit`) and its instances' shadows (off past half faded). |
| `fade_hang.gd` (`FadeHang`) | The two ends of a hung piece: on a wall unit its `followers`, on a hung unit its `wall`s. |
| `wall_fade_config.gd` (`WallFadeConfig`) | `radius`, `fade_time`, `faded_amount`, `tall_height`, `half_width`, `cell`, `steps`, `poll_frames`, `hang_pad`, `hang_frames`. |

## Rules

- **What is looked at.** `listen(carrier)` connects `MeshCarrier.built(body, mesh)`, so every mesh a builder makes for a wall, a door or a furniture body is taken, whenever its builder was registered. A mesh with a signal `segment_replaced(index, part)` and a method `segments()` (`WallMesh`) is one unit per segment; any other mesh is one unit of every `GeometryInstance3D` under it (`TableMesh`, a furniture rig, `DoorMesh`). A unit under `tall_height` is dropped at once (a low table never hides anyone). A body that is no plain `StaticBody2D` (furniture, a door) is movable.
- **Hung pieces.** A mesh with `hangs_on_wall == true` (a `FurnitureRig`: menu board, wall stain, mirror) is a hung unit, not filed in the grid and never looked at itself: each frame it is attached (`admit`) to the wall units whose footprint, grown `hang_pad` px, holds its middle, and is marked hit whenever one of them is, so it fades and returns with the wall (a rebuilt segment keeps its followers). A hung piece that finds no wall for `hang_frames` frames (shoved away) is filed as an ordinary tall unit.
- **Foci.** `focus_targets()` of the sim's `Camera2D` (General): the player following, every combatant spectating; each read duck-typed, dead ones skipped.
- **In the way.** The ground line from a focus toward the camera (the rig's yaw) first meets the unit's footprint, as a strip `half_width` to each side of it (`FadeBox.strip_entry`: the line grown across, not ahead), within `radius` and under the unit's top (the ray rises with the pitch: at 80 degrees a 96 px wall hides only what stands within about 17 px of it, so only a wall right in front or a piece hung over the focus, whose footprint holds it, fades). It fades over `fade_time` to `faded_amount` of its pixels (`MeshNodes.fade`, a dither) and back the same way, never a pop. A door fades as its leaf stands; a door swung or knocked flat keeps its closed footprint until it is polled again.
- **Cost.** A focus asks only the units in the grid cells its reach touches; a movable unit is checked for a move a slice of `poll_frames` a frame (it is found where it was polled to, so a blast can leave one a few frames stale). An instance is written only when its level (a step of `steps`) changes; nothing is allocated per frame.
- **Rebuilds.** A rebuilt wall segment takes the fade of the old one at once (keyed wall + index); a piece built again (a dent, `remirror`) takes its predecessor's fade by its body (kept a few frames).

- **The aim looks through it.** A unit more than `FadeHold.HELD_AT` (half) faded is held in General's `FadedTwins` (its body's instance id, its index, its footprint on the plan), released when it comes back, is rebuilt, its mesh leaves or the `WallFade` itself leaves the tree (`FadeBook.release_all`); a moved unit gives its new footprint. `Pointer.aim_hit` skips a twin hit inside a held footprint, so the cursor over floor seen through a faded wall aims level (the fade dithers the mesh only, the twin stays solid). Written when the unit passes the half or moves, never per frame.

## Seams (interface 27)

`MeshCarrier.built(body, mesh)` (Art); General's `CameraController.focus_targets() -> Array[Node2D]` (the camera's own list, read only); Objects' `WallMesh.segments()` and `segment_replaced`. Read-outs: `count()`, `fading`, `written`, `looked`, `unit_of(key, index)`, `grid`; `step(delta, yaw, foci)` is one frame (a test calls it by hand).

## Tests and limits

`tests/art/wall_fade_rules_test.gd`, `fade_box_strip_entry_test.gd`, `wall_fade_hook_test.gd`, `wall_fade_furniture_test.gd` (a wardrobe and a fridge rig), `wall_fade_view_test.gd`, `tests/general/pointer_aim_fade_test.gd` (the aim looks through a faded wardrobe and wall), `tests/objects/wall_hung_fade_test.gd`, `overhead_fade_test.gd`, `mirror_follows_shapes_rule_test.gd`, and windowed `wall_fade_windowed_test.gd` (pictures to `WALL_FADE_SHOT_DIR`). Limits: a furniture piece shown by a proxy box (no mesh of its own yet) and a vehicle are not faded; the fade is see-through, no low-stub variant; a unit more than half faded casts no shadow (`FadeShadow` sets each part's `cast_shadow` off and back to the setting it had, since a stippled shadow darkened the character and Godot 4.4 spatial shaders have no shadow-pass identifier to skip the discard); the dither is in screen pixels, so it swims a little as the camera turns.
