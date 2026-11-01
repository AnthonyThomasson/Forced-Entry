16. **Objects → Audio: `SoundSurface`** (a floor tells Audio what it is made of; Audio stays a leaf)
    - `SoundSurface.register(rect: Rect2, material: String, pattern: String = "") -> int` / `SoundSurface.unregister(id)`: Objects' `Floor`
      registers its world rect with its `floor_material` and the painter's `pattern` in `_ready` and unregisters in `_exit_tree` (as it
      already feeds `BloodSurface`). A floor whose definition sets `sound_surface: false` (the street round a house) registers none.
    - `SoundSurface.at(pos) -> StringName`: what the ground is at a world point (`wood`, `tile`, `stone`, `concrete`, `carpet`, or `outdoor`
      when no floor covers it; the newest floor wins). Only the `Sound` service reads it, to voice a footfall.
    - Everything else Audio hears arrives as an EventBus event (10); the other domains only *post*, none references Audio.
