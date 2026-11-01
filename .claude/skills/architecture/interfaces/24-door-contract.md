24. **The door contract: Objects' `Door` ↔ Character, AI, Testing** (`scenes/objects/door/door.gd`; spec `docs/doors.md`; World-Gen builds
    it through 2, the Use key and the AI drive it through this one)
    A `Door` is an `AnimatableBody2D` on `PhysicsLayers.SOLID` in the group `doors` (the one name Navigation, Testing and the AI find a door
    by), one per doorway, driven by code (`docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`); its origin is the middle of
    its leaf, angles are degrees from shut. A caller reads and calls only what is listed here.
    - **State:** `hinge` (the world point on the jamb the leaf turns about), `swing_into` (unit vector into the room it swings into: that
      room's side pulls, the other pushes), `open_angle` (90), `width` (the doorway's free width between the jambs), `angle()`,
      `open_amount()` (0 shut .. 1 wide open; 1 once down), `is_down()` (knocked down: lying flat, no collider, no shadow, unusable),
      `gap() -> float` (the width a character can pass, at most `width`; `width` once down), `leaf_pose(angle) -> Transform2D` (the leaf's
      middle at that angle, x axis along the leaf) and `leaf_size() -> Vector2` (length, thickness), `damage.hp` / `damage.max_hp`.
    - **Use:** `toggle(by)` (an open door, or one swinging open, swings shut; a shut or ajar one swings fully open, in
      `DoorConfig.swing_time`), `turn_by(degrees, by)` (from where it is heading, positive opens, clamped to shut..`open_angle`; a scroll
      notch is `DoorConfig.step_degrees`), `open_fully(by)`; `by` is the user or null. A knocked-down door ignores all three. A swing stops
      short at a wall, furniture or a body it cannot nudge clear (DR8).
    - **Where to stand:** `latch_side_spot(from: Vector2) -> Vector2`, beside the latch jamb on the side of the doorway `from` lies on: where
      the AI works the latch from.
    - **Signal:** `changed` (a swing began or ended, the door was hurt, its panes shattered, it fell). Events: `&"door"` (10).
    - **Hittable (3) and pushable (5):** `get_surface()`, `take_hit(hit)`, `take_damage(amount)`, `apply_impulse(v, at)`, `get_mass()`. A kick
      (a shove of `DoorConfig.burst_impulse` or more, then `take_damage`) or a blast from the push side wears a shut door's latch
      (`DoorMaterialConfig`); a door whose latch gives, or an ajar one, bursts fully open at `DoorConfig.burst_speed`; from the pull side
      a kick or blast turns an ajar door toward shut; a walking push or a punch never counts against a latch (DR5, DR10).
    - **The character's side** (`character.use.doors`, `CharacterDoors`, `character/character_doors.gd`; takes no input event, so an NPC
      calls it as the player's controller does): `door_in_reach() -> Node2D` (the standing door nearest the aim whose leaf has a point within
      `CharacterDoorConfig.reach` of the body and ahead of it, else null), `reaches(door) -> bool`, `use(door := null) -> bool`
      (`door.toggle`), `open_fully(door := null) -> bool` (never shut: how the AI works a door in its way, DR14) and
      `turn(steps, door := null) -> bool` (`turn_by(steps * DoorConfig.step_degrees)`; `steps` may be a share of a notch); each acts on
      the door given while it is in reach, false with none. `use.use_target() -> StringName` is `&"door"` when a door in reach is nearer
      than every boardable vehicle handle (19), `&"vehicle"`, or `&""`; `use.try_use()` acts on it at once, while the human's controller
      holds a door back to the key's release unless the wheel turned it meanwhile.
    - **Callers:** the human's Use key (`Keybinds.USE`, E; `Keybinds.scroll_notches(event)` while it is held, DR6, DR7); the AI's
      locomotion (DR14: finds a door on its walk by the group and reads `gap()`, `is_down()`, `angle()`, `leaf_pose(0.0)`, `width`, `swing_into`
      and `latch_side_spot(from)`, duck-typed, and calls `use.doors.open_fully`); Testing (13: `use()`, `turn_door(steps)`, a layout's `door`).
    - **Built by** `DoorFactory.spawn` (2). **Left out of every nav bake** (9). Its **shadow** is an occluder child on `LightMasks.WALL` (20).
