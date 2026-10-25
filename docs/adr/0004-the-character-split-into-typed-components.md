# The Character split into typed components

`character.gd` had grown to 1558 lines, 59 vars and 87 public methods, against gdstyle's `quality/max-file-length`
(1000), `max-class-variables` (15) and `max-public-methods` (20), which issue #76 turns on with no exclusion. Its body
helpers `character_visuals.gd` (1503 lines, 39 vars), `character_pose.gd` (28 vars) and `CharacterRig.Measures` (27)
were over too.

The body is split into typed components, one topic each, held as public properties of the body and built once:
`movement` (intent, posture, running, stamina, knockback), `inventory` (the carried items and held slot), `ammo`
(magazines and reloading), `weapon` (firing, melee, the raise, recoil, muzzle and aim), `stun` (a flash and bang),
`use` (an object interaction, a vehicle ride, the collision exceptions they leave), `anatomy` (the pose, rig, hands,
legs, kick, footsteps, dent, wound, occluder and ragdoll as the body steps them) and `wardrobe` (style, look seed, rank,
the outfit). Each is a `class_name` `RefCounted` but `wardrobe`, a Node child so a scene can author its style. Callers
name the component (`character.movement.posture()`); there are no forwarders. The body keeps what scenes author
(`radius`, `faction`, `max_health`, `start_slot`), what every domain reads as plain state (`health`, `is_dead`, `facing`),
its signals, and the contracts that name the body: hittable, pushable, `take_stun`, `blast_push`, `blood_origin`,
`world_root`, `report_shot`, `damage_taken`. A member keeps its name, except that a prefix the component already says is
dropped (`weapon_blocked()` → `weapon.blocked()`, `stun_view()` → `stun.view()`, `ammo()` → `ammo.rounds()`), and a
forward the body made to a part it held is called on the part (`hand_world(hand)` → `anatomy.hands.world(hand)`,
`foot_clamp(i)` → `anatomy.legs.ankle(i)`, `set_outfit(ids)` → `wardrobe.outfit.set_ids(ids)`). The body helpers split
the same way: the pose into springs, arms and gait; the rig's measures into measures and a fold; the visuals into
dress, limbs, shadow, laid-out body and trunk.

## Consequences

Every caller names a component, and so does every test prop: a key `component:prop` (`"movement:aim_point"`) is set
with `set_indexed`, the wardrobe's through `set_props(id, "Wardrobe", …)`. A duck-typed check asks for the property
(`"stun" in node`), not a method. A new member goes in the component of its topic; one that fits none starts a new
component, never the body. Components are built once and never per frame, and a hot loop takes its component into a
local once. Each character allocates more Objects at spawn, so a plain perf A/B between the two versions plays a
different fight (the sight cadence is keyed on instance ids) and is compared on the same fight. The architecture skill
names the component in every interface signature; `domain-character` and `domain-character-body` say what each
component holds.

## Considered options

- **Forwarders on the body** (`character.posture()` calling `movement.posture()`): rejected. The body keeps its 87
  public methods, so the rule still fails, and there are two names for everything.
- **Untyped helpers** (Dictionaries or a bag of vars per topic): rejected for the reason ADR 0003 gives. Types are
  lost, and a misspelt name reads null.
- **Split by size** (`character_a.gd`, `character_b.gd`, or an inheritance chain `CharacterBase` → `Character`):
  rejected. A reader cannot tell where a member lives. gdstyle counts per file, so a chain would pass while the
  body's surface stayed 87 methods wide.
- **Every component a Node child:** rejected. The body steps them in a fixed order inside its own
  `_physics_process`, which Node children's own processing would not keep. Child ready order would also leave holders
  null in each other's `_ready`. Only `wardrobe` is a Node, for its scene-authored export, and the body finds it in
  `_enter_tree`, before any child's `_ready`.
- **An exclusion or a higher threshold for the character:** rejected by #76.
