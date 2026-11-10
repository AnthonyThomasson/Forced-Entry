# Perf · The fight fingerprint (`tests/_perf/fight_fingerprint.gd`, #203)

What a revision's match is made of, one line a physics frame, so two plays can be diffed and the first frame they differ on named
(`perf-nondeterminism.md`). Each of the four match guards (`match_5v5_stress`, `grenade_match_stress`, `match_10v10_stress`,
`match_npc_vision`) calls `Perf.record_fight(t, self, characters)` first thing in `run`; it covers the warm-up and the whole
window, and does nothing, and costs nothing (no signal connected), unless the environment holds `GAME_TEST_FINGERPRINT_DIR`.

- **Emit:** `GAME_TEST_FINGERPRINT_DIR=DIR tools/run_tests.sh --id=perf/match_5v5_stress`. `run_tests.sh` hands DIR to every engine
  process (`--base` and the shards included) as an absolute path and creates it. A guard writes `DIR/<test id with / as __>.fp`
  (`perf__match_5v5_stress.fp`), flushed every frame, closed when its world is freed.
- **Format:** text, one line per physics frame, tab-separated fields. The first is the frame number (0 on the first physics frame
  after `record_fight`); then one field per NPC in spawn order; then `S:` and `D:`.

  `<frame>` TAB `<i> <x>,<y> <gx>,<gy> <act> <health>` (per NPC, `i` = 0, 1, 2 ...) TAB `S:<x>,<y>;<x>,<y>` TAB `D:<i>,<i>`

  `i` is the NPC's index in the match's `combatants` (the viewed invader of `match_npc_vision` last), never its node name or
  instance id (both follow allocation). `x,y` the position rounded to whole pixels. `gx,gy` its navigation agent's target position
  rounded (`-` with none). `act` the controller's `current_act()` (decision path, `hold` idle, `-` for no AI controller; it can hold a space), a hostile it names (`t_<instance id>`) written `t_<index>` of that NPC (`t_?` for none), never an id.
  `health` to one decimal. A freed NPC's field is `i gone`. `S:` the frame's shots (EventBus `shot`), the muzzle rounded, in
  the order posted; `D:` the indices of the NPCs that died that frame. `grenade_match_stress`'s thrower puppet is no NPC of the
  match and not in it (its throws show as shots).
- **Diffing** (for the same-fight A/B tool): two files are the same fight when equal line for line. The first line that differs
  (`cmp`, or `diff` stopped at the first hunk) names the first differing frame by its first field; a file that is a prefix of
  the other differs at the frame it ends on.
- **The allocation-padding switch:** `s.switch(&"testing.allocation_padding", true)` makes `TestWorld.build` allocate 777 loose
  nodes and 333 each of physics bodies, areas and shapes (`AllocationPadding`) before it builds the world, freed with it.
  Its only use is to play a fight with and without it and compare fingerprints: allocation must not steer a fight. Off unless a test
  asks. Its own test is `tests/_harness/allocation_padding_test.gd` (`--self-test`).
