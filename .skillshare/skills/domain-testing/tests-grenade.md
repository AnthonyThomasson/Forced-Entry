# Grenade tests (tag `grenade`)

The rules are `docs/grenades.md` (G1 to G19, each with its tests named under it); `tools/run_tests.sh grenade` runs them, the
scenario tests replay recorded Von (`--record-von` refreshes, `--require-von` runs live). They are spread by domain (`tests/items/`, `tests/projectile/`,
`tests/physics/`, `tests/character/stun_*`, `audio/grenade_sounds`, `general/camera_shakes_on_explosion`,
`ui/stun_screen_whiteout`) with the AI ones in `tests/ai/grenade/`.

**Probes** (`tests/_ai/`, not tests):
- `grenade_probe.gd` (`const Probe`): `arm(character, stuns, frags)` (a test world keeps the default inventory, so each
  test arms the thrower as Main does, at the start of `run`), `throw_at`, `live`, `raw` / `booms` / `stuns` (bus events with
  their sim time) and the spec's numbers (`MAX_RANGE`, `FLASH_RADIUS`, …) so a test checks the doc and not the code.
- `grenade_spec_probe.gd` (`const GrenadeSpec`): what a blast or a stun does at a distance by the spec (`blast_damage`,
  `flash_scale`, `expected_blind`, `expected_deaf`, `everywhere`: the audio tests' range table).
- `grenade_ai_probe.gd` (`const GrenadeAi`): the AI's reads and a scene round a grenade (`offered`, `acts`, `callouts`,
  `grenades`, `place`, `line_clear`, `safe_from_frag`, `shielded`, `plain_escape`: `AgentThrow.escape` worked out the plain
  way, …) and `character_rids`, the rids of the `characters` group, which its rays look past.
- `suspect_probe.gd` (`const Suspect`): the suspect-room STUN ENTRY tests (`stun_entry_*`, G18): the bare Terrace house and
  a stack of two in the back garden; `check_stun_entry` requires the stack's first SEARCH / INVESTIGATE decision to be STUN
  ENTRY by the back door with a `bang` radioed; each test adds the one thing that makes the kitchen suspect. The wording
  they rest on is measured by `tools/von_scenarios/stun_entry_*.json`.
- `throw_spot_probe.gd` (`const Spot`): the throw-spot tests (G17): `throws` (the `grenade` zones of `debug_zones()`),
  `lob_clear`, `hand_lob_clear` (the lob from the thrower's hand, `Character.inventory.throw_release_offset`), `THROW_RANGE`,
  `walk`, `watch_first_combat`. A throw's `throw` event is at the hand, about 16 px from the thrower's centre.
- `grenade_ready` is answered by an existence search (the `domain-ai` skill's snapshot demand): `ai/grenade/grenade_ready_matches_full_search` reads two snapshots of one moment (one asks `demand.fact("grenade_ready")`, the other `demand.complete()`s its throw groups) and counts `views.walk_queries` for each; a `GrenadeAi.offered` read of a snapshot's `options` should `complete()` its demand first.
- `bang_probe.gd` (`const Bang`): the four `bang_fallback_*` tests, a stack of two at the back door (`rules`, `stack`,
  `arm`, `radio_mate`: a puppet teammate radioing its part of the stack).

**Scenarios and mechanisms.** The scenario tests in `tests/ai/grenade/` run the whole AI pipeline with real Von and
`require` the premise first (that the AI took the GRENADE / STUN ENTRY path), so a different Von choice reads as a set-up
finding. The mechanisms they cannot reach are scripted-Von tests: `grenade_range_drift`, `throw_dropped_when_lob_blocked`
and `throw_committed_in_windup` use `von_script(rules, 30)` (slow answers) to change the world while a question is in
flight; `evade_replans_when_spot_in_line` moves a rolling grenade once it is at rest (a resting `ThrownGrenade` stays where
it is put) and posts the `grenade` rest event it would post, which a turned-away NPC hears.

Gotchas:
- A hall of 100 px or less with a sofa in it is sealed in the navmesh (the lane left is under an agent body wide), and a route
  to the far side then runs outside the house: give a scenario hall at least 140 px when the NPC must walk past furniture.
- To teleport a character use `global_position`; to move a piece of furniture onto a lob, `freeze` it first and make the
  teleport a frame later, or the physics step puts a free body back.
