24. **The door contract: Objects' `Door` ↔ Character, AI, Testing** (`scenes/objects/door/door.gd`; spec `docs/doors.md`; World-Gen
    builds it through interface 2, the Use key and the AI drive it through this one)
    A `Door` is an `AnimatableBody2D` in the group `doors` (the one name Navigation, Testing and the tests find a door by), one per doorway, driven by code (`docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`),
    on `PhysicsLayers.SOLID`; its origin is the middle of its leaf. Angles are degrees from shut. A caller holds the node and
    reads/calls only what is listed here; the parts (`look`, `damage`, `swing`) and the visuals are Objects' own, bar `hp` / `max_hp`.
    - **State (read):** `hinge: Vector2` (the world point on the jamb the leaf turns about), `swing_into: Vector2` (unit, from the doorway into
      the room it swings into: the pull side is that room's, the push side the other), `open_angle: float` (90), `width: float` (the doorway's free
      width between the jambs, twice the hinge's distance from the doorway's centre), `angle() -> float`, `open_amount() -> float` (0 shut .. 1
      wide open; 1 once down), `is_down() -> bool` (knocked down: off its hinges, lying flat, no collider, no shadow, unusable),
      `leaf_pose(angle) -> Transform2D` (the leaf's middle as it stands `angle` degrees open, its x axis along the leaf, hinge to latch) and `leaf_size() -> Vector2` (its length and thickness: how the Use key finds the leaf's nearest point), `gap() -> float` (the width a character can pass: the way from the leaf's free end to the latch jamb, at most `width`; `width` once down),
      `damage.hp` / `damage.max_hp` (the leaf's hit points).
    - **Use (call):** `toggle(by)` (an open door, or one swinging open, swings shut; a shut or ajar one swings fully open; in
      `DoorConfig.swing_time`), `turn_by(degrees, by)` (turn from where it is heading, positive opens, clamped to shut..`open_angle`,
      and stay; a notch of the scroll is `DoorConfig.step_degrees`, which the Use key's scroll reads through `use.doors.turn(steps)`), `open_fully(by)`; `by` is the character using it (or null). A
      knocked-down door ignores all three. A swing stops short at a wall, furniture or a body it cannot nudge clear and stays there
      (`docs/doors.md` DR8).
    - **Where to stand:** `latch_side_spot(from: Vector2) -> Vector2` — beside the latch jamb, out from the wall on the side of the
      doorway `from` lies on (`DoorConfig.latch_spot_out` / `latch_spot_in`): where the AI works the latch from.
    - **Signal:** `changed` — a swing began or ended, the door was hurt, its panes shattered, it was knocked down.
    - **Implements the hittable (3) and pushable (5) contracts:** `get_surface()` (coverage 100, the material's `penetration`, the
      surface material it sounds and throws debris as; a glass-panel door's surface also says `transparent: true`, which the AI's
      sight reads: sight passes it), `take_hit(hit)` (a round or a blast: dent or hole, debris, the glass-panel door's panes
      shatter, hit points by the material's factor), `take_damage(amount)` (a punch or a kick), `apply_impulse(v, at)` (remembered for
      the strike that follows; the door is driven, so it does not move) and `get_mass()`. A kick (a shove of `DoorConfig.burst_impulse`
      or more) or a blast from the push side wears the latch (`DoorMaterialConfig`: `latch_hp`), and a door whose latch gives bursts
      fully open at `DoorConfig.burst_speed`; a walking push or a punch never counts; from the pull side a hit only damages.
    - **Built by** `DoorFactory.spawn(opening, definition, parent) -> Door` (interface 2). **Left out of both nav bakes** by
      `NavBuilder` (interface 9), found by the group `doors`; its **shadow** is a `LightOccluder2D` child on `LightMasks.WALL` that
      turns with the leaf, none for the glass-panel door (interface 20).
    - **Callers:** the Character domain's `CharacterDoors` (`character.use.doors`, interface 7: `door_in_reach()` finds a door by the group
      `doors` and reads `is_down()`, `leaf_pose(angle())` and `leaf_size()`; `use()` calls `toggle(by)`, `turn(steps)` calls `turn_by(steps * DoorConfig.step_degrees,
      by)`) for the human's Use key (E, the wheel while held; `docs/doors.md` DR6, DR7), which the AI's controller will call in the same way, and the Testing
      domain's layouts and puppets (13: `use()`, `turn_door(steps)`).
