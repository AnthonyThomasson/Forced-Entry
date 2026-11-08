# Doors (`objects/door/`; spec `docs/doors.md`)

A door is neither furniture nor a wall: `Door` (`door/door.gd`, an `AnimatableBody2D` in the group `doors`) is a hinged leaf in a doorway,
moved kinematically by code (`docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`). Its surface (state, Use, hits, pushes)
is interface 24; `DoorFactory.spawn(opening, definition, parent)` builds it from World-Gen's `DoorCatalog` definition (interface 2).

Tuning: `DoorConfig` (swing time, `step_degrees`, burst, nudge, the leaf's size, the latch gap `latch_gap`, dents), `DoorPushConfig` (a
walker's push: resistance, friction, rest speed), `DoorMaterialConfig.materials` (per `hollow` / `solid` / `steel` / `glass`: hit
points, penetration, latch, the factor of each kind of hit, the surface material it sounds as, `weight`) and `ObjectArtDoorConfig`
(fittings, glass). Wood is the sound of every wooden door and of steel too (no metal ring); steel's `debris` is `metal`, the material
its chips and sparks are styled as.

- **Frame.** The origin is the middle of the leaf; `leaf_pose(angle)` gives it at an angle, and `place(parent)` sets it before the node
  enters the tree (a kinematic body takes its pose from the physics server as it enters). A wall's collider reaches half its thickness
  into the gap, so the hinge sits there on the jamb and the leaf fills the free `width`. The leaf turns about a pivot half
  `leaf_thickness` off the hinge, so it clears the jamb when open.
- **Parts** (`RefCounted`, preloaded): `door.look` (`door_look.gd`: material, style, colour, panes shattered), `door.damage`
  (`door_damage.gd`: `hp`, `latch`, the factor of a hit), `door.swing`
  (`door_swing.gd`: the angle, the turn's sign, the eased or steady turn toward a target) and `door.push` (`door_push.gd`: the spin a
  walker's shove gives an ajar leaf). `door.visuals` (`door_visuals.gd`) is the child that draws it.
- **A swing** (`_physics_process`) asks the physics space for the angle one step on first (a query of the leaf `probe_inset` slimmer all
  round): anything solid that is not a character stops it where it is; a character is moved straight away from the leaf by what clears
  it (`_nudged`, no faster than `nudge_speed`), and one that cannot be moved (a wall, furniture or another body behind it, or the leaf
  outrunning the nudge) stops it too. The opener is nudged like anyone (`tests/objects/door_nudges_test.gd`,
  `tests/objects/door_nudge_speed_test.gd`).
- **A push** (`apply_impulse`, `_pushed`; DR10): a shut door, a fallen one and a leaf already swinging take no push. An ajar or open leaf
  adds the moment of the shove about the pivot over `weight x DoorPushConfig.resistance` to `door.push.spin` (degrees a second, positive
  opening), held to `burst_speed`; with no swing running `_physics_process` turns the leaf by it, slows it by `friction` and rests it
  under `rest_speed`. It nudges no one: any character or loose piece of furniture the exact leaf shape overlaps (the slim probe would let it press them aside, a shove a frame), a wall or other furniture stops it; at open it stops, and a
  walker's push toward shut stops at it: `door.push.walker_shuts_open_leaf` (the leaf at `open_angle`, spin toward shut, no `_hurt` within a
  frame; a kick's shove and its `take_blow` land together, so a kick still turns it). Reaching shut it posts `shut` and is rigid again (`tests/objects/door_push_open_test.gd`, `door_push_stops_test.gd`, `door_push_open_limit_test.gd`, `door_open_stop_ignores_walkers_test.gd`). A hand's `_turn_to` and a `_burst` cancel it.
  A melee strike names its kind: `take_blow(kind, amount, impulse)` (`&"kick"` or `&"punch"`, `MeleeBlow.kind`); `take_damage` is a punch.
- **Damage.** `take_hit` (a round, or a blast: `speed_factor` 0, no height) dents the leaf (`door.visuals.deformable`, the collider
  kept), throws debris (`Physics.spawn_debris` with the door's surface, `_debris_surface`), shatters a glass-panel door's panes at the
  first hit (the frame stays; the surface becomes the frame's wood) and takes the material's factor of the hit off the hit points;
  `take_damage` is a punch. A kick or blast from the push side bursts an ajar door fully open at once, whatever its material
  (`_hurt`); on a shut door it wears `door.damage.latch` by the strike's damage (a kick only where the material has `kicks_latch`), and a
  latch that gives bursts it open. At 0 HP `_fall`: the door lies flat beyond the doorway on the side of the blow (the room it swings
  into when the blow had no direction), `collision_layer` 0, its occluder freed, drawn lying (`part: "fallen"`) at `DrawLayers.LYING`;
  `angle()` is `open_angle`, `gap()` the width, the Use calls do nothing. Tests: `tests/objects/door_damage_test.gd`,
  `door_kick_burst_test.gd`, `door_blast_burst_test.gd`, `door_blast_ajar_test.gd`, `door_hard_punch_stays_a_punch_test.gd`,
  `door_knocked_down_test.gd`, `door_materials_test.gd` there.
- **Art** (`art/door_painter.gd`, `door` in `ObjectArt.PAINTERS`): drawn through `ObjectArt.turned` (`PixelArt.render_turned` at the
  lighting step of the leaf's angle, repainted by `door_visuals.gd` when a transform notification crosses one). A resting door sleeps
  both its physics callback and visual polling; every swing, burst, moving shove and fall wakes it
  (`resting_door_runs_no_per_frame_callback_test.gd`). `part` `leaf` (the top edge of the standing
  leaf, 6 px thick: stiles, planks, rivets or panes, a hinge pin, the handle) or `fallen` (the lying face); `style`, `door_material`
  (steel rusts, wood is scratched), `broken` (shattered panes). Knobs: `ObjectArtDoorConfig`.
- **Light and sight.** The leaf builds its occluder (`LightMasks.WALL`, a child that turns with it; none for glass) like a wall's
  (`domain-lighting`); sight reads `get_surface().transparent` (glass) in the AI.
- **Events.** `door._post(stage)` posts `&"door"` (10, DR12) at `open` (`_turn_to` starting a swing that opens it, unless the door began
  opening within `latch_gap` of game time before, tracked by `_opened_at`, so a run of scroll notches sounds once), `shut`
  (`_physics_process` when a swing ends at 0, `_pushed` when a walker pushes it home), `burst` (`_burst`), `down` (`_fall`) and `glass`
  (`_shatter`). The door knows nothing of Audio (`tests/audio/door_sounds_test.gd`).
- **Used by** `character.use.doors` and the AI's locomotion through interface 24. Tests: `tests/objects/door_contract_test.gd` and the
  other `door_*_test.gd` there; the Use key's are `tests/character/door_use_key_test.gd`, `door_scroll_open_test.gd`.
