24. **The door contract: Objects' `Door` ↔ Character, AI, Testing** (`scenes/objects/door/door.gd`; spec `docs/doors.md`; World-Gen builds
    it through 2, the Space key and the AI drive it through this one)
    A `Door` is an `AnimatableBody2D` on `PhysicsLayers.SOLID` in the group `doors` (the one name Navigation, Testing and the AI find a door
    by), one per doorway, driven by code (`docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`): the 2D follower of a 3D
    leader in the twin space (#194 doors3d: standing, an `AnimatableBody3D` `DoorBody` its swing turns, the leaf 84 px high under the
    lintel; knocked down, a free `DoorSlab` rigid body, D18, `docs/doors.md` DR11); its origin is the middle of
    its leaf, angles are degrees from shut. A caller reads and calls only what is listed here.
    - **State:** `hinge` (the world point on the jamb the leaf turns about), `swing_into` (unit vector into the room it swings into: that
      room's side pulls, the other pushes), `open_angle` (90), `width` (the doorway's free width between the jambs), `angle()`,
      `open_amount()` (0 shut .. 1 wide open; 1 once down), `is_down()` (knocked down: a free body lying where physics left it, walk-over when flat and an obstacle when leaning, unusable),
      `gap() -> float` (the width a character can pass, at most `width`; once down what its fallen leaf leaves of the doorway: `width` when it lies flat), `leaf_pose(angle) -> Transform2D` (the leaf's
      middle at that angle, x axis along the leaf) and `leaf_size() -> Vector2` (length, thickness), `damage.hp` / `damage.max_hp`.
    - **Use:** `toggle(by)` (an open door, or one swinging open, swings shut; a shut or ajar one swings fully open, in
      `DoorConfig.swing_time`), `turn_by(degrees, by)` (from where it is heading, positive opens, clamped to shut..`open_angle`; a scroll
      notch is `DoorConfig.step_degrees`), `open_fully(by)`; `by` is the user or null. A knocked-down door ignores all three. A swing stops
      short at a wall, furniture or a body it cannot nudge clear (DR8).
    - **Where to stand:** `latch_side_spot(from: Vector2) -> Vector2`, beside the latch jamb on the side of the doorway `from` lies on: where
      the AI works the latch from.
    - **Signal:** `changed` (a swing began or ended, the door was hurt, its panes shattered, it fell). Events: `&"door"` (10).
    - **Hittable (3) and pushable (5):** `get_surface()`, `take_hit(hit)`, `take_blow(kind, amount, impulse)`, `take_damage(amount)`, `apply_impulse(v, at)`, `get_mass()`. A kick
      (`take_blow(&"kick", ...)`) or a blast from the push side wears a shut door's latch
      (`DoorMaterialConfig`); a door whose latch gives, or an ajar one, bursts fully open at `DoorConfig.burst_speed`; from the pull side
      a kick or blast turns an ajar door toward shut; a walking push or a punch never counts against a latch (DR5, DR10).
    - **The character's side** (`character.use.doors`, `CharacterDoors`, `character/character_doors.gd`; takes no input event, so an NPC
      calls it as the player's controller does): `door_in_reach() -> Node2D` (the standing door nearest the aim whose leaf has a point within
      `CharacterDoorConfig.reach` of the body and ahead of it, else null), `reaches(door) -> bool`, `use(door := null) -> bool`
      (`door.toggle`), `open_fully(door := null) -> bool` (never shut: how the AI works a door in its way, DR14) and
      `turn(steps, door := null) -> bool` (`turn_by(steps * DoorConfig.step_degrees)`; `steps` may be a share of a notch); each acts on
      the door given while it is in reach, false with none. `gap_to(door, point) -> float` is how far the leaf is from `point` at its nearest point. `use.interact_target()` is `{ kind: &"door", object }` when a door in reach ahead is the
      thing nearest the mouse among the objects, doors and boardable vehicle handles (8, 19); `use.try_interact()` acts on it at once, while the human's controller
      holds a door back to the key's release unless the wheel turned it meanwhile.
    - **What a door asks of a character** (so a swing clears one, DR8): the group `characters`, the exported `radius` (7), its 3D walker's
      `shift(aside, leaf)` (`TwinSpace.walker_of`: moves it clear of the leaf, false when something stops it), duck-typed; the door imports nothing of Character.
    - **Tuning read across the boundary:** `DoorConfig.step_degrees` (the Character's wheel step, `turn`), `DoorConfig.open_angle` (the
      angle World-Gen gives a door that starts open: `Door.open_angle` is the same number) and `DoorConfig.swing_time`; the rest of
      `DoorConfig` stays in Objects.
    - **Callers:** the human's Space key (`Keybinds.INTERACT`; `Keybinds.scroll_notches(event)` while it is held, DR6, DR7); the AI's
      locomotion (DR14: finds a door on its walk by the group and reads `gap()`, `is_down()`, `angle()`, `leaf_pose`, `leaf_size()`, `width`,
      `swing_into` and `latch_side_spot(from)`, duck-typed, and calls `use.doors.open_fully` on any door not at its open stop, which it tells
      by `NavBuilder.leaf_in_map` (9); the entry's pie skip asks whether a doorway's standing door
      shuts the view, reading `is_down()`, `gap()`, `width` and `get_surface()` (`transparent`), DR14, `docs/tactical-entry.md` E3); Testing (13: `use()` (Space), `turn_door(steps)`, a layout's `door`).
    - **Built by** `DoorFactory.spawn` (2). **Left out of every nav bake** (9) **but at its open stop**: then Navigation carves its leaf
      where it stands, reading `is_down()`, `angle()`, `open_angle`, `leaf_pose(angle)` and `leaf_size()` duck-typed (`NavLeaves`, 9); a knocked-down door's `fallen_footprint() -> PackedVector2Array` (its leaning footprint, empty when it lies flat or stands) is carved the same way. In 3D its leaf mesh casts the shadow (20).
