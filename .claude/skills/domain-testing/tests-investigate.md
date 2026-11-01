# Investigation and hearing tests (tags `investigate`, `hearing`)

`tests/ai/investigate/` pins how gunfire heard outside or inside the house is worded for Von and answered (issue #40:
defenders leaving the house). Footsteps are `docs/hearing.md` H1.

- `tests/_ai/investigate_probe.gd` (`const Probe`): `world(s, kind)` (the Terrace house, one NPC in the hall, radio and
  trespass hostility off, Von left to the caller), `gunfire(at)` (a hit event nobody known fired, heard from
  `Probe.OUTSIDE` / `Probe.INSIDE`), `levels`, `asked_about_investigating`.
- Scripted tests check the wiring (`investigate_outside_lead_offers_stay`, `investigate_lone_lead_is_asked`); the `*_von`
  tests (`requires_von`, `--include-von --require-von`) check what a real Von decides: the defender stays in, still
  investigates gunfire inside, and an invader investigates the same gunfire outside. After rewording what Von reads about
  leads, run `tools/von_probe.py` (its `investigate_outside_lead_*` scenarios).
- `defenders_stay_in_house_quiet` (scripted) and `_von` (real Von, invaders outside as at a match's start) watch every
  defender of a generated house (`tests/_ai/house_probe.gd`: `house(s, seed, defenders, invaders)` declares the house and a
  match over it; `side(t, faction)` reads one side's NPCs off `t.world.match_handle`; `watch` carries each defender's trail
  and what Von was last asked into its failure message). Sweep them with `--seed=N`.
- `move_stops_on_arrival` gives scripted Von a real server's reply time by raising `DecisionStub.latency_frames` in `run`.
- Footsteps: `ai/perception/footsteps_heard_by_gait` (scripted puppets walk, run and crouch lanes behind a wall from a held
  defender, read off `debug_memory()["footsteps"]` and the `footfall` events) and `ai/investigate/footsteps_lead` (real Von).
