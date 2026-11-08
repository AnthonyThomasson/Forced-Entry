---
name: domain-interaction
description: Use when editing scenes/interaction/ or working on object interactions: the Space toggle, sit/lie actions, `move_to` snapping, the interactable contract.
---

# Interaction domain

`scenes/interaction/character_interaction.gd` (`CharacterInteraction`) is the whole domain, a component the character builds in `_ready()`. The character never learns what an interaction *means*: add or retune an action in the catalogue data of the object (`get_interactions()`, interface 8) and touch nothing here. Tests: `tests/interaction/`.

## Gotchas

- **Discovery is by contract.** The reach query (a circle of `reach` px, `front_offset` ahead of `facing`, on `PhysicsLayers.SOLID`) keeps every collider with `get_interactions()` and at least one action whose `requires_item` gate passes. `try_interact()` targets the object nearest `movement.aim_point` and runs a random valid action. A controller (the AI) picks object and action with `interactions_in_reach()` + `interact_with(object, id)`.
- **A `move_to` action overlaps the object on purpose.** The character is snapped onto the object under a temporary `add_collision_exception_with`, so a seat or bed is not shoved and the character is not ejected. Re-entering the object just left calls `use.stop_clearing(body)` first and keeps the exception it still has.
- **Exit is deferred out of the physics step** (`_end` → `_teardown`): moving the body and restoring its collision mid-solve made the physics lurch. The character stays busy (`use.is_busy()`) for the frame in between.
- **Collision comes back only once clear.** `_teardown` hands the object to `use.keep_clear_of(body)` (`CharacterUse`, `CLEAR_MARGIN`), which lifts the exception when the body has left the object, so restoring collision never finds an overlap to eject from.

**Interfaces:** 8 (Interaction ↔ Character & Objects), 11 (`PhysicsLayers.SOLID`).
