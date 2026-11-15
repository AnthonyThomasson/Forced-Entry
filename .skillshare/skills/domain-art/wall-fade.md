# The wall fade (`mirror/wall_fade.gd`, interface 27)

Side file of `domain-art`. #193 rule 9: walls, doors and tall pieces between the camera and a character fade so the character is never hidden; the rest stay whole.

## Parts

| File | Role |
|---|---|
| `wall_fade.gd` (`WallFade`, a `Node3D`) | The frame: the foci, the grid lookups, stepping the fades. Main's `View3D` makes it (`fade`; `rig`, `source`) and calls `listen(mirror)`. |
| `fade_book.gd` (`FadeBook`) | What it looks after: `watch`ed meshes, their units, a rebuilt segment, a freed mesh, the fade carried to a mesh built again. |
| `fade_grid.gd` (`FadeGrid`) | Where units are looked for: cells of `WallFadeConfig.cell` px, movable units re-filed by a polled slice. |
| `fade_unit.gd`, `fade_box.gd` (`FadeUnit`, `FadeBox`) | One faded thing (its instances, level and footprint) and the ray-to-footprint question. |
| `wall_fade_config.gd` (`WallFadeConfig`) | `radius`, `fade_time`, `faded_amount`, `tall_height`, `half_width`, `cell`, `steps`, `poll_frames`. |

## Rules

- **What is looked at.** `listen(mirror)` connects `WorldMirror.built(body, mesh)`, so every mesh a builder makes for a wall, a door or a furniture body is taken, whenever its builder was registered. A mesh with a signal `segment_replaced(index, part)` and a method `segments()` (`WallMesh`) is one unit per segment; any other mesh is one unit of every `GeometryInstance3D` under it (`TableMesh`, a furniture rig, `DoorMesh`). A unit under `tall_height` is dropped at once (a low table never hides anyone). A body that is no plain `StaticBody2D` (furniture, a door) is movable.
- **Foci.** `focus_targets()` of the sim's `Camera2D` (General): the player following, every combatant spectating; each read duck-typed, dead ones skipped.
- **In the way.** The ground line from a focus toward the camera (the rig's yaw) first meets the unit's footprint, grown `half_width`, within `radius` and under the unit's top (the ray rises with the pitch: a 96 px wall reaches about 136 px). It fades over `fade_time` to `faded_amount` of its pixels (`MeshNodes.fade`, a dither) and back the same way, never a pop. A door fades as its leaf stands; a door swung or knocked flat keeps its closed footprint until it is polled again.
- **Cost.** A focus asks only the units in the grid cells its reach touches; a movable unit is checked for a move a slice of `poll_frames` a frame (it is found where it was polled to, so a blast can leave one a few frames stale). An instance is written only when its level (a step of `steps`) changes; nothing is allocated per frame.
- **Rebuilds.** A rebuilt wall segment takes the fade of the old one at once (keyed wall + index); a piece built again (a dent, `remirror`) takes its predecessor's fade by its body (kept a few frames).

## Seams (interface 27)

`WorldMirror.built(body, mesh)` (Art); General's `CameraController.focus_targets() -> Array[Node2D]` (the camera's own list, read only); Objects' `WallMesh.segments()` and `segment_replaced`. Read-outs: `count()`, `fading`, `written`, `looked`, `unit_of(key, index)`, `grid`; `step(delta, yaw, foci)` is one frame (a test calls it by hand).

## Tests and limits

`tests/art/wall_fade_rules_test.gd`, `wall_fade_hook_test.gd`, `wall_fade_furniture_test.gd` (a wardrobe and a fridge rig), `wall_fade_view_test.gd`, `mirror_follows_shapes_rule_test.gd`, and windowed `wall_fade_windowed_test.gd` (pictures to `WALL_FADE_SHOT_DIR`). Limits: a furniture piece shown by a proxy box (no mesh of its own yet) and a vehicle are not faded; the fade is see-through, no low-stub variant; a unit more than half faded casts no shadow (`FadeUnit.apply` sets each part's `cast_shadow` off and back to the setting it had, since a stippled shadow darkened the character and Godot 4.4 spatial shaders have no shadow-pass identifier to skip the discard); the dither is in screen pixels, so it swims a little as the camera turns.
