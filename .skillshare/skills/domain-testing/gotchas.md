# Testing: gotchas

Side file of `domain-testing` (`SKILL.md`).

- **A body added this frame is not in the physics space:** a shape query or ray on that frame misses it (`TestWorld`
  waits one physics frame after placing vehicles).
- **A click at a world point needs a still view.** The test camera eases in from where the last test left it and an
  injected mouse event is handled a frame after it was aimed. Wait for the canvas transform to hold still first
  (`OrderMenu.view_still`, `tests/_ai/order_menu_probe.gd`); it counts drawn frames (`Engine.get_process_frames()`), since
  a window's first frames run several physics frames each.
- **A test camera reads its screen centre only while current:** a test that adds its own camera calls `make_current()`
  (`tests/general/camera_zooms_out_driving_test.gd`).
- **A replayed Von test is a normal test** (no pacing, any shard); a live, recording or live-only one is paced in real time.
  `--fixed-fps 60` outruns the wall clock, so game-time timers (HTTP timeouts, the launcher's probe) would fire early; the
  session sleeps each frame to 1/60 s while such a test is open. A cold Von start takes about 5 s. A live or recording
  ask stalls the main thread until Von answers (`VonBlockingAsk`, 10 s at most, then the test FAILs), so no game time
  passes meanwhile and the answer lands on the same frame as in a replay.
- **Recordings** are `<name>_test.von.json` beside a `requires_von` test. Everything the NPCs read in a test goes into the key
  (state text, question, option descriptions), so a test that changes what an NPC sees (a map, a wording, a tuning that
  shifts a band) needs `--record-von --id=<id>` again. Commit the recording with the change that staled it.
  A recording replays the same frames only while the world does: a frag's blast strikes bodies nearest first so the world's
  random stream is drawn for the same body each run (`Explosion._bodies_near`), but the engine orders the contacts of touching
  rigid bodies by the slots they were allocated in, so a furniture piece a blast shoves settles a thousandth of a pixel
  differently from one run to the next in one process, and a snapshot wording at a band edge can then miss its recording.
  `own_process` (`runner-flags.md`) is the last resort for one such test; a long fight of NPCs is `live_only`.
- **A test that ends mid-wait** leaves its coroutine parked: Godot may report "ObjectDB instances leaked" at exit, harmless.
- **An NPC thinks on its first tick, so the world must be live before actors enter:** `MatchBuilder.stage` waits two
  physics frames, then until `NavBuilder.ready` holds on the planning and steering maps (a map's iteration is built on a
  worker thread; under load an NPC snapped onto the empty map walked to the origin). The wait is real time, so the test
  clock is stopped while the world builds (`_building` in the session).
- **The defender preset is `tuning.hostility.on_trespass`, and an arena counts as its house:** turn
  `ai.hostile_on_trespass` off to test a reaction to something else.
