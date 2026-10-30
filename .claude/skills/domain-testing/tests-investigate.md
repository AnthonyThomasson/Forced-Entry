## Investigation tests (tag `investigate`)

`tests/ai/investigate/` pin down how gunfire heard outside or inside the house is worded for Von
and answered (issue #40: defenders leaving the house). The shared helper is `tests/_ai/investigate_probe.gd` (`const Probe :=
preload(...)`): `world(s, kind)` (the terrace house, one NPC in the hall, radio and trespass hostility off, Von left to the caller),
`gunfire(at)` (a hit event nobody known fired, heard from `Probe.OUTSIDE` / `Probe.INSIDE`), `levels` / `asked_about_investigating`.
Scripted ones (`investigate_outside_lead_offers_stay`, `investigate_lone_lead_is_asked`) check the wiring. The three `*_von` tests
(`requires_von`, `--include-von --require-von`) check what a real Von decides: the defender stays in, still investigates gunfire inside,
and an invader still investigates the same gunfire outside. After rewording any of what Von reads about leads, run them with
`tools/von_probe.py` (its `investigate_outside_lead_*` scenarios).
Footsteps (`docs/hearing.md` H1, tag `hearing`): `ai/perception/footsteps_heard_by_gait` (scripted: puppets walk, run and crouch lanes at set distances behind a
wall from a held defender, read off `debug_memory()["footsteps"]` and the `footfall` events' `character` / `crouched`) and `ai/investigate/footsteps_lead` (real Von).

`defenders_stay_in_house_quiet` (scripted) and `defenders_stay_in_house_quiet_von` (real Von, invaders outside as at the start of a match)
watch every defender of a generated house (`tests/_ai/house_probe.gd`: `house(s, seed, defenders, invaders)` declares the house and a
match over it, `s.declared_match`, placed and armed as Main's; `side(t, faction)` reads one side's NPCs off `t.world.match_handle`; `watch`, whose failure message carries each
defender's trail and what Von was last asked) and sweep with `--seed=N`. `move_stops_on_arrival` gives
the scripted Von a real server's reply time by raising `DecisionStub.latency_frames` in `run` (`von_script` registered it, so it is restored after the test).
