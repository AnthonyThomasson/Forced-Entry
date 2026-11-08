---
name: domain-character
description: Use when editing scenes/character/ (character.gd, player_controller.gd, Character*Config holders, character scenes) or working on how a character moves, holds a weapon, dies or is drawn.
---

# Character domain

Owns the player character, built so other character types can exist. It reads intent from a pluggable controller child (interface 7) and is the one pushable that is not a `RigidBody2D`: it integrates knockback into its own walk.

**Side files** (read the one your task touches):
- Posture, running and stamina, walking into furniture, the stun's effect on the walk → `movement.md`.
- Firing, reload and magazines, the raise against a wall, loadout, grenade reads, the stunned look and one-handed fire → `weapon.md`.
- Style, outfit, hit zones, armour in `take_hit`, weight → `wardrobe.md`.
- The body (skeleton, pose, rig, hands, punch, kick, legs, ragdoll fall, all pixel art and the redraw key) → `body.md`.
- The Use key, a house door in reach, the scroll that turns it, a door in the way → `doors.md`.

## Components

The three verbs (control, animate, draw) live in separate files wired through the scene tree. Scene scripts carry no `class_name` except a typed component's. A draw file sits on its own child `Node2D`.

`character.gd` (control: state and physics, never draws) holds typed `RefCounted` components as public properties and steps them itself. Callers name the component; the body keeps no forwarders.

| Property | File | Owns |
|---|---|---|
| `movement` | `character_movement.gd` | the controller's intent, posture, running and stamina, knockback, the push slow |
| `use` | `character_use.gd` | what occupies the body: an interaction, a vehicle ride, its doors (`use.doors`: `doors.md`), the collision exceptions both leave |
| `inventory` | `character_inventory.gd` | items carried, the held slot |
| `weapon` | `character_weapon.gd` | using the held item: firing, melee, the raise, recoil, muzzle and aim, each hand's stance |
| `ammo` | `character_ammo.gd` | magazines carried, the reload |
| `stun` | `character_stun.gd` | a grenade's flash and bang on the body |
| `anatomy` | `body/character_anatomy.gd` | the animate parts (pose, rig, hands, legs, kick, footsteps, ragdoll, dents, wound, shadow): `body.md` |
| `wardrobe` | `character_wardrobe.gd` | a `Node` child (`Wardrobe` of `character_base.tscn`, found in `_enter_tree` before any child's `_ready`): style, look seed, rank and the `Outfit` worn; it steps nothing |

Also here: `character_footsteps.gd`, `character_push.gd` (the shared `shove`), `player_controller.gd`.

**Tuning:** one `class_name` static holder per topic (`grep -r "class_name Character.*Config" scenes/character`). In `character/`: `CharacterPostureConfig`, `CharacterPaceConfig`, `CharacterPushConfig`, `CharacterDoorConfig` (the reach for a door), `CharacterStunConfig`, `CharacterHitConfig`, `CharacterShadowConfig`, `CharacterArtConfig`, `CharacterStyleConfig`, `CharacterBodyConfig`, `CharacterStanceConfig`, `CharacterRagdollFallConfig`, `CharacterVisionConfig` (what the character sees by: `fov_degrees` 110, `view_distance` 2520, `awareness_radius` 48, `see_over_coverage` 60, the NPCs' default sight; the body's `sight()` hands them out as a dictionary, which the Vision domain reads duck-typed to draw a view of any one character, interface 25). The body's own are in `body/` (`body.md`).

## Ordering

A parent's `_physics_process` runs before its children's, so the hands see the character's fresh `facing`. `_physics_step` pulls the controller's intent after `movement.tick`, `stun.update` and `inventory.tick` (so a due gun fires this frame), then the ride (`use.control`) overrides it, then `ammo.update`; a ride or an interaction holds the body (`use.hold_frame`), else the walk frame runs. `facing` is pointed at `movement.aim_point` each frame; the node is never rotated, so hand math stays in local space.

## Runtime shapes

`character.gd` builds its body `CircleShape2D` in `_ready()` and `body_strike.gd` builds each strike's query circle. The editor's "no shape" warning on `Player/CollisionShape2D` is expected. The body runs in `MOTION_MODE_FLOATING` (top-down): in grounded mode a body it walks "down" into would be ridden as a platform and lend the character its launch velocity.

## Death

`_apply_damage` (from `take_hit`, `take_damage`) calls `_die(direction)` at zero health. `_die` cancels a reload (`ammo.cancel()`), calls `anatomy.die()`, leaves layer 1 and ends what held the body: `use.end_interaction()`, `use.abandon()` (a vehicle ride: the body falls where it is, the door left as it is). It then takes `movement.momentum()` in the posture it died in, stands the body (`movement.stand_up()`, `movement.fold(0.0)`, so the ragdoll starts from the standing skeleton) and calls `stun.clear()`. `anatomy.die()` stops the bleeding, frees the shadow occluder and moves the body to `CharacterArtConfig.ragdoll_z_index` (`DrawLayers.LYING`: under the living and a vehicle's chassis and roof, over blood pools; test `vehicle/fallen_body_under_vehicle`). `anatomy.fall` builds the ragdoll with the body's momentum (`movement.momentum()`: walk + knockback, including the killing blow's shove). The held item is dropped through `Item.drop(self, momentum + toss)`; a returned node removes the slot, so `inventory.current_item()` may be null on a corpse. Then `died` is emitted. While dead `_physics_process` only steps the ragdoll. `blood_origin()` is the position alive and the trunk's middle once fallen; when the ragdoll first settles `anatomy.step` calls `Physics.bleed_out`.

## The body's shadow (interface 20, `docs/lighting.md` L6)

A living character casts a shadow: `anatomy.attach()` builds a `LightOccluder2D` through `LightMasks.occluder` (none while `LightMasks.shadows` is off) on `LightMasks.CHARACTER`, shaped by `CharacterShadowConfig`. It follows the body unrotated; `anatomy.turn_shadow()` turns it to `facing` only when the facing has turned. `anatomy.die()` frees it: a 2D occluder has no height, so a body on the floor would throw a shadow as long as a wall's. Test: `lighting/occluders_walls_pieces_characters`.

## Events a character posts

- `&"footfall"` from `character_footsteps.gd` (stepped by `anatomy.step` after the pose): `{ position, foot, speed, running, character, crouched }`. A landing is the foot's stride phase rising through cos 0, above `MIN_WALK` walk amount; none while an interaction holds the character or once dead. Audio voices it, the AI hears by it (`docs/hearing.md` H1), and the sole goes to the `BloodFootprints` child (Physics). Tests: `tests/physics/footprints_trail_test.gd`, `tests/audio/footstep_surface_sound_test.gd`, `tests/ai/perception/footsteps_heard_by_gait_test.gd`.
- `&"reload"` twice (`start`, `done`; `CharacterAmmo._post`). A reload cancelled by running, switching items, an interaction or death never posts `done`. Test: `tests/audio/reload_sound_test.gd`.
- `&"hit"` for a landed punch or kick (`_on_punched`, `_on_kicked`, `KICK_HAND`), with `attacker = self`, `outcome = &"punch"` and the victim's `material`, so a punch counts as an attack for AI hostility; also `hit_landed`.
- `&"stun"` from `stun.take` (`weapon.md`).

## Walking into furniture

`movement.walk`'s `_apply_pushes()` shoves each pushable the body slid into through `CharacterPush.shove(piece, dir, impulse, at_world, speed)`, shared with the leg press (`body.md`). The impulse lands at the **contact point**, so a piece pushed near an end turns about a point near the far end. The shove is capped so the contact point is carried at no more than `speed × CharacterPushConfig.carry_factor` along the push, using the piece's effective mass at that point, so a turning end is never flung ahead of the walker. Another character (no `linear_velocity`) takes the shove uncapped. The slow-down (`slow_per_weight`, floor `slow_min`) applies at once and eases back at `slow_release`/s, so a lost-contact frame does not snap speed. Tests: `tests/character/walk_into_furniture_speed_test.gd`, `walk_into_sofa_turns_test.gd`.

## Riding a vehicle (interface 19, `docs/vehicles.md`)

`use` composes the Vehicles domain's `CharacterVehicleUse` (preloaded and added by `use.attach()` in `_ready`) and forwards its vehicle calls; `use.try_use()` is the one entry for E (`doors.md`; refused while dead or in an object interaction, and stands a crouched character up), `use.vehicle()`, `use.is_in_vehicle()`. While the ride lasts, `use.is_busy()` is true and `try_interact` / `interact_with` are refused.

The Vehicles domain poses the body with `use.set_ride_pose(at, toward, fold, step)`: the first pose cancels a reload and disables the collision shape (`set_deferred`); each pose sets position, `facing`, aim and the drawn height (`movement.fold`) and drops the cached rig. While riding, `inventory.current_item()` returns null (the item put away: nothing fires or draws in the hands) and `use.hold_frame` replaces the rest of the frame: no movement, knockback or push, stamina refilling, `anatomy.pose.update` with the ride's step as the motion and no stun look. `use.end_ride()` re-enables the shape.

**Clearing a body just left** (interfaces 8, 19). `use.keep_clear_of(body)` keeps the collision exception with an object an interaction's `move_to` put the character on, or a vehicle it rode, until the character's circle (+`CLEAR_MARGIN`, on `PhysicsLayers.SOLID`) no longer overlaps it, checked once a physics frame (`use.restore_cleared()`); a freed body is forgotten. Going straight back calls `use.stop_clearing(body)`, so the exception stays.

## Scenes and groups

`character_base.tscn` is the bare character (body, shape, Hands, Visuals, Wardrobe) with **no controller** and the one place that composition is declared. `ai/npc.tscn` inherits it (`domain-ai`; `npc_defender.tscn` and `npc_invader.tscn` override data only) and `main.tscn`'s `Player` instances it with `player_controller.gd`. A composer adds a `control()` child before the character enters the tree (`_find_controller()` runs at `_ready`); the Testing domain adds its puppet `ScriptedController`.

Every character joins the group `characters` in `_ready` (interface 7): how the AI's perception, `Explosion` and a vehicle find characters in the world. `faction` is exported (`&"player"` by default; the NPC presets set `&"household"` / `&"invader"`) and read by AI perception to tell allies from potential hostiles.

**Interfaces:** 3 (hittable), 4 (Physics), 5 (pushable), 6 (Items ↔ Character), 7 (Character ↔ Controller), 8 (Interaction), 10 (EventBus), 11 (`PhysicsLayers.SOLID`, `DrawLayers.LYING`, `LightMasks.CHARACTER`, `FillBatch`, `ViewLayers`, `SeenArea`), 12 (Art), 15 (`GameLog`), 18 (`stun.view()`, read off `Sound.focus`), 19 (Vehicle), 24 (the door contract, `use.doors`), 20 (the occluder; `is_dead` / `radius` read by the lighting), 25 (`sight()`, `facing`, `died` read by the Vision domain).
