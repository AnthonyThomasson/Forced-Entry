# Von tests: a recording replays only if live and replay play the same frames

Side file of `domain-testing` (`SKILL.md`), with `runner-flags.md` ("Von tests").

**Where the world is built differs.** A live or recording run builds the world from the launcher's `_process`, a replay from a
`physics_frame` signal, and the next run of a process from wherever gdUnit resumed. Anything that counts frames from the build must
start where the bodies are placed (the continuation after `MatchBuilder.stage`'s nav wait), never in `setup`. The nav updater's
`RebakeTimer` did not: it kept or lost its first frame by that point, every tick and re-bake fell a frame apart against the same fight,
an NPC re-pathed on a mesh whose corner was 0.14 px off, and a fresh recording failed its own replay on a differently worded option (a fire
spot "behind the wall in the kitchen" vs "from an ambush behind cover"; an ally "in sight standing still" vs "last seen just now"). It
is `NavUpdater.start()` now, called by `stage`; `navigation/updater_tick_phase` begins a stage from four frame phases and compares the
ticks.

**Probe a replay that misses.** In `DecisionStub.decide` write each ask's frame and state text to a file, in the recording run and in
the replay; the first ask whose text differs names the fact. Then dump the NPC's path and the map's iteration per frame and the
updater's ticks and landings (`NavBake._land`): a tick or landing a frame apart is a phase, a path corner a hair apart after equal
ticks is physics. A third run of the same process failing where the first passes is allocation order (below).

**Own process** (`"own_process": true`, `runner-flags.md`) is for a fight the engine settles in allocation order (`ai/grenade/combat_frag_take_cover`:
a frag settles furniture). `ai/combat/defend_room_stays_inside` once failed runs 2 and 3 of a process for another such reason: the
kitchen's south wall and the hall's north wall are coincident colliders (a shared wall built twice, until #194's walls job), a ray into that
seam ties between two bodies, the engine breaks the tie by allocation order, and the pick, "Hall" or "Kitchen", moved a sleeping fridge a
hair across the re-bake threshold. With bullets and sight as 3D rays it replays in-process (`--repeat=3`), so it has no tag; a fight
that fails a later run of a process and passes the first has this kind of tie.
