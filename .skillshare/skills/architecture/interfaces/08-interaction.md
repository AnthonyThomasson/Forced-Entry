8. **Interaction ↔ Character & Objects** (kept isolated so it iterates alone)
   The character's `use` (`CharacterUse`) composes the Interaction domain's `CharacterInteraction` and exposes only opaque forwards:
   `use.try_interact()` (the player's **Space**: acts on the reachable thing nearest the mouse among the object interactions below, a standing house door in reach ahead (24) and a vehicle's door (19), or ends the interaction in progress or gets out of the vehicle; `use.interact_target() -> Dictionary` is `{ kind: &"object" | &"door" | &"vehicle" | &"end", object }`, empty with none), the component's `nearest_in_reach()` (`{ object, specs, gap }`, the gap from the mouse to the nearest point of its colliders) / `begin_random(entry)` (called by `use`), `use.interactions_in_reach()`, `use.interact_with(object, id)` /
   `use.end_interaction()` (controller/AI), `use.is_busy()` (movement/actions lock), `use.interaction_label()` (HUD) and `use.active_interaction() -> Dictionary` (`{ object, id }` of the interaction in progress, `{}` when idle: Objects' bed mesh asks whether `id` is `"lie"` on its own piece).
   - **Interactable contract:** every world object implements `get_interactions() -> Array` (plain dicts: `id`, `label`, optional
     `move_to` / `requires_item`), advertised via the optional `interactions` object field. The character never learns what an
     interaction *means*.
   - **What the component touches on its host:** `global_position` (a `move_to` action snaps the body onto the object and back),
     `facing` (the reach query sits ahead of the body, on `PhysicsLayers.SOLID`, interface 11, excluding the body's own `get_rid()`),
     `movement.aim_point` (Space picks the reachable object, door or vehicle door nearest the cursor), `inventory.has_item(id)` (`requires_item`),
     and Godot's `add_collision_exception_with` for the object a `move_to` puts it on.
   - **Leaving an object:** the component hands it to `use.keep_clear_of(body)`, which keeps the collision exception until the character's
     circle no longer overlaps it (a freed body is forgotten); `use.stop_clearing(body) -> bool` when the character goes straight back onto
     that object, so its exception stays.
