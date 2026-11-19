---
name: domain-interaction
description: Use when editing scenes/interaction/ or working on object interactions: the Space toggle, sit/lie actions, `move_to` snapping, the interactable contract.
---

# Interaction domain

`scenes/interaction/character_interaction.gd` (`CharacterInteraction`) is the whole domain, a component the character builds in `_ready()`. The character never learns what an interaction *means*: add or retune an action in the catalogue data of the object (`get_interactions()`, interface 8) and touch nothing here. Tests: `tests/interaction/`.

## Gotchas

- **Discovery is by contract.** The reach query (a cylinder of `reach` px from the floor to a standing head, `front_offset` ahead of `facing`, asked of the twin 3D space on `PhysicsLayers.TWIN_WORLD`, interface 29: what a piece fills is its 3D parts, a tipped one where it lies; the gap to the mouse is the plan distance to those parts, `_gap_to`) keeps every body with `get_interactions()` and at least one action whose `requires_item` gate passes. `use.interact_target()` (`CharacterUse`) weighs `nearest_in_reach()`, the object nearest `movement.aim_point`, against a house door and a vehicle's door, and `use.try_interact()` runs a random valid action of the winning object (Space). A controller (the AI) picks object and action with `interactions_in_reach()` + `interact_with(object, id)`.
- **A `move_to` action overlaps the object on purpose.** The character is snapped onto the object under a temporary `add_collision_exception_with`, so a seat or bed is not shoved and the character is not ejected. Re-entering the object just left calls `use.stop_clearing(body)` first and keeps the exception it still has.
- **Exit is deferred out of the physics step** (`_end` → `_teardown`): moving the body and restoring its collision mid-solve made the physics lurch. The character stays busy (`use.is_busy()`) for the frame in between.
- **Collision comes back only once clear.** `_teardown` hands the object to `use.keep_clear_of(body)` (`CharacterUse`, `CLEAR_MARGIN`), which lifts the exception when the body has left the object, so restoring collision never finds an overlap to eject from.
- **A piece is reached by its real body.** The reach is to a piece's 3D body (a chair's 28 px square, as wide as its 2D footprint was); a body exactly on the 46 px rim is out (Jolt, unlike the 2D engine, does not count touching). A world with no twin space finds nothing (every staged world has twins). Paged: `TwinSpace.intersecting`.

**Interfaces:** 8 (Interaction ↔ Character & Objects), 11 (`PhysicsLayers.TWIN_WORLD`), 29 (`TwinSpace.space_of`, `owner_of`, `twin_for`).
