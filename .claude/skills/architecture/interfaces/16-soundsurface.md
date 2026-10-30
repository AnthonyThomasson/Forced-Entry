16. **Objects → Audio: `SoundSurface`** (a floor tells Audio what it is made of; Audio stays a leaf)
    - `SoundSurface.register(rect: Rect2, material: String, pattern: String = "") -> int` /
      `SoundSurface.unregister(id)` — Objects' `Floor` registers its world rect with its `floor_material` and
      the painter's `pattern` in `_ready` and unregisters in `_exit_tree` (the same way it already feeds
      `BloodSurface`); a floor whose definition sets `sound_surface: false` (the street round a house) registers none.
    - `SoundSurface.at(pos) -> StringName` — what the ground is at a world point (`wood tile stone concrete
      carpet`, or `outdoor` when no floor covers it; the newest floor wins). Read only by the Audio domain's
      `Sound` service, to voice a footfall.
    Everything else Audio hears arrives as an EventBus event (interface 10): the gun, projectile and character
    domains only *post*; none of them references Audio.
