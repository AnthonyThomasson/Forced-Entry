8. **Interaction ↔ Character & Objects** (kept deliberately isolated so it iterates alone)
   The character composes a `CharacterInteraction` component (`interaction/`) and exposes only
   opaque forwards: `use.try_interact()` (the player's **Space** toggle), `use.interactions_in_reach()`
   and `use.interact_with(object, id)` / `use.end_interaction()` (for a controller/AI), `use.is_busy()`
   (movement/actions lock) and `use.interaction_label()` (HUD). It discovers objects through the
   **interactable contract** — every world object implements `get_interactions() -> Array` (plain
   data dicts: `id`, `label`, optional `move_to` / `requires_item`), advertised via the optional
   `interactions` object field. The character never learns what an interaction *means*. The component touches only its host's
   `global_position` (a `move_to` action snaps the body onto the object and back), `facing` (the reach query sits ahead of the body, on
   `PhysicsLayers.SOLID`, interface 11, excluding the body's own `get_rid()`), `movement.aim_point` (the player's Space picks the reachable object
   nearest the cursor) and `inventory.has_item(id)` (an action's `requires_item`), and takes Godot's own collision exception
   (`add_collision_exception_with`) with the object a `move_to` puts it on. When an interaction ends the component hands
   the object to the character's `use.keep_clear_of(body)`, which keeps their collision exception until the character's circle no longer
   overlaps it (then drops it; a freed body is forgotten), and calls `use.stop_clearing(body) -> bool` when the character goes straight back
   onto that object, so its exception stays.
