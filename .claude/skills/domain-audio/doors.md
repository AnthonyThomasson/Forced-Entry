# The house doors' sounds (`sound_doors.gd`, `SoundDoors`; spec `docs/doors.md` DR12)

A door's leaf is the sixth family of the library. A vehicle's door is another thing: `SoundVehicles`' `door/<kind>/...`.

**Profiles** (category `door`, −2 dB, 4 voices, 1200 px; the topic `&"door"` is in interface 10):

| Profile | Stage | What it is |
|---|---|---|
| `leaf/latch` | `open`, `shut` | The one sound of every door, whatever its material: the latch's click, its seating and the leaf's thud (the solid wood door's `shut`); 0.3 s, no creak. |
| `leaf/burst` | `burst` | The one burst of every door: the latch cracking and the leaf slamming the wall, wood splintering (the solid wood door's); 0.5 s. |
| `leaf/<material>/down` | `down` | The fall: chips of wood flying, then the heavy thud on the floor and a rattle; steel a heavy clang (0.9 s, wood 0.6 s). |
| `leaf/glass/glass` | `glass` | The glass-panel door's panes shattering: a crack, a rush and shards tinkling down, bright; 0.85 s. |

`material` is `hollow` / `solid` / `steel` / `glass`. A material or stage with no profile (`glass` on a wooden door) is silent.
`LEAF_MATERIAL` (`solid`) is the row the latch and the burst are voiced from.

**Tables.** `MATERIALS` (per door material: `db`, `pitch`, the `thud` of the leaf coming home, its low `panel` resonances, a steel door's
`ring` partials, the wood's `splinters`: what the fall is built from), `LENGTHS`, `SOUND_DB` and `SOUND_DRIVE` (keyed `latch`, `burst`,
`down`, `glass`); `profile(material, stage)` names the sound of an event's stage, and `recipe(parts)` builds it.

**Voicing.** Like a vehicle's door, a house door is a thunk, not a creak: no creak, no panel ring above a few hundred Hz. A steel door's
hits sound as a wood door's (Objects' `DoorMaterialConfig.sound`), so a round or a kick on it plays no `impact/metal/...`. The door posts
one event per stage; it keeps a run of scroll notches to one `open` itself (`DoorConfig.latch_gap`, DR12), so the service does no limiting
of its own beyond the category's voices.

**Adding.** A door material: a row in `SoundDoors.MATERIALS` and a `DoorMaterialConfig` row (a door whose material has no row is silent). A
new sound: a profile in `SoundDoors.profile` / `profiles()`, its length and level in `LENGTHS` / `SOUND_DB`, a layer builder in `recipe`.

**Test.** `tests/audio/door_sounds_test.gd` (hand-laid layout): each stage of a hollow, steel and glass-panel door posts one `&"door"` event
and plays one voice at the doorway; every material opens and shuts with `leaf/latch` and bursts with `leaf/burst`; a run of scroll notches
sounds once; steel clangs on its fall; glass shatters bright.
