## Grenade tests (tag `grenade`)

The rules are `docs/grenades.md` (G1 to G19, each with its tests named under it); `tools/run_tests.sh grenade` runs them, the scenario tests
with `--include-von --require-von`. They are spread by domain (`tests/items/grenade_*`, `loadout_grenade_counts`; `tests/projectile/frag_*`,
`grenade_friendly_fire`; `tests/physics/frag_blast_pushes`, `explosion_fx`; `tests/character/stun_*`; `tests/audio/grenade_sounds`;
`tests/general/camera_shakes_on_explosion`; `tests/ui/stun_screen_whiteout`) with the AI ones in `tests/ai/grenade/`, all through
`tests/_ai/grenade_probe.gd` (`const Probe := preload(...)`): `arm(character, stuns, frags)` (a test world keeps the default inventory, so each test
arms the thrower the way Main does, at the start of `run`), `throw_at`, `live`, `raw` / `booms` / `stuns` (bus events with their sim time) and the numbers of the spec
(`MAX_RANGE`, `FLASH_RADIUS`, ...) so a test checks the doc and not the code. What a blast or a stun does at a distance by the spec is
`tests/_ai/grenade_spec_probe.gd` (`const GrenadeSpec := preload(...)`: `blast_damage`, `flash_scale`, `expected_blind`, `expected_deaf`, and
`everywhere`, the audio tests' range table); the AI reads and a scene round a grenade are `tests/_ai/grenade_ai_probe.gd` (`const GrenadeAi :=
preload(...)`: `offered`, `acts`, `wait_act`, `callouts`, `grenades`, `hostile`, `place`, `line_clear`, `safe_from_frag`, `shielded`, `known_contact`, `watch_until_thrown`, `check_held_at_old_spot`, `check_sees_again`, `check_thrown_from_outside`, `shot_runs_into` (the line back from a `shot_from` memory crosses a room), `plain_escape` (`AgentThrow.escape` worked out the plain way, every candidate snapped, judged and routed) with the `escape_threat` / `escape_runner` it takes, and
`character_rids`, the rids of the `characters` group: what its rays and `throw_spot_probe.gd`'s look past). The scenario tests
in `tests/ai/grenade/` run the whole AI pipeline with the real Von server and `require` the premise first (that the AI took the GRENADE / STUN ENTRY path), so a
different Von choice reads as a set-up finding. A hall of 100 px or less with a sofa in it is **sealed in the navmesh** (the lane left is under an agent body wide) and
a route to the far side then runs outside the house: give a scenario hall at least 140 px when the NPC has to walk past a piece of furniture.
The suspect-room STUN ENTRY tests (`stun_entry_*`, G18) share `tests/_ai/suspect_probe.gd` (`const Suspect := preload(...)`: `world` the bare Terrace house
and a stack of two in the back garden, `arm`, `watch`, `first_search`, `check_stun_entry`: the stack's first SEARCH / INVESTIGATE decision must be STUN ENTRY by the back door
and a `bang` radioed); each adds the one thing that makes the kitchen suspect at the start of `run`. The wording they rest on is measured by `tools/von_scenarios/stun_entry_*.json`.
The throw-spot tests (`grenade_throw_spot_*`, `grenade_walks_to_throw_spot`, `grenade_shots_origin_throw_spot`, G17's throw spots) share
`tests/_ai/throw_spot_probe.gd` (`const Spot := preload(...)`: `throws` (the `grenade` zones of `debug_zones()`), `from_of`, its own `lob_clear` (one ray, nothing above 50 on the
line), `hand_lob_clear` (that lob from the thrower's hand, `Character.inventory.throw_release_offset`, along a band 8 px either side), `THROW_RANGE` (550), `walk` (a `NavBuilder.route` reach and length), `any_lob_along`, `note` / `describe`, which follow each decision walk with where the NPC stood when it began, and `watch_first_combat`, those walks until the NPC's first COMBAT decision and its throw). A throw's
`throw` event is at the hand, about 16 px from the thrower's centre. The mechanisms the scenarios cannot reach are scripted-Von tests: `grenade_range_drift`, `throw_dropped_when_lob_blocked` and `throw_committed_in_windup` use `von_script(rules, 30)`
(slow answers) to change the world while a question is in flight; `evade_replans_when_spot_in_line` rolls a grenade on by moving it once it is at rest (a resting
`ThrownGrenade` stays where it is put) and posting the `grenade` rest event it would post, which a turned-away NPC hears (a character moved with `global_position`, a piece of furniture shoved onto the lob: it must be `freeze`d first and
the teleport made a frame later, or the physics step puts a free body back), and the four `bang_fallback_*` tests run a stack of two at the Terrace house's back door through
`tests/_ai/bang_probe.gd` (`const Bang := preload(...)`: `rules` SEARCH > STUN ENTRY > that doorway, `stack`, `arm`, `radio_mate` for a teammate that is a puppet radioing its part of
the stack, `note_acts` / `took`).
