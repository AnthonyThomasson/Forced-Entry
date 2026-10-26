# The AI orchestrator and behaviour split into tuning topics and typed parts

`goal_controller.gd`, the AI's orchestrator, had 141 vars (113 exports, every NPC tunable) and 21 public methods in 1204
lines, against gdstyle's `max-class-variables` (15), `max-public-methods` (20) and `max-file-length` (1000), which
issue #76 turns on with no exclusion. Behaviour's `behavior.gd` had 76 vars and 42 public methods in 2227 lines,
`entry.gd` 116 vars in 2857 lines, `combat.gd` 29 vars and 25 public methods, `locomotion.gd` 38 vars in 1020 lines,
and the decision planner and the server launcher 24 and 18 vars.

The controller's exports are the one authoring surface of an NPC: a defender and an invader differ only in data on
their scenes, and tests, switches and the dev command server retune one NPC. Static holders (ADR 0003) would make
those values global, and an exported `Resource` overridden on an inherited scene is shared by every instance. So 111
tunables move to per-NPC topic nodes under the controller's `Tuning` child: `NpcTuning` holds fifteen
`Npc<Topic>Tuning` nodes (`decision`, `context`, `tactics`, `combat`, `coverage`, `memory`, `senses`, `radio`,
`entry`, `entry_geometry`, `entry_guard`, `grenades`, `watch`, `hostility`, `pace`), each only exports, and the
controller holds it as `tuning`. They carry a `class_name` because an export must name a global class. The controller
keeps `goal`, its node path, the bind contract (`rooms`, `openings`, `entry_point`, `squad`) and its wiring, and splits
its decision cadence, its radio and its squad and grenade reflexes into three parts (`_cadence`, `_comms`,
`_reflexes`); the inspector's three focus methods become one var, `debug_focus`, and the planner owns its Von client.

Behaviour's modules (`Behavior`, `Entry`, `Combat`, `Locomotion`, `Watch`, `SearchCoverage`) read the topics live,
`tuning.<topic>.<name>`, rather than copying them each decision; perception and the planner still copy theirs at each
decision. Behaviour, entry, combat, locomotion, the planner and the launcher split per concern into parts reached by
preload const, as the AI's modules always were, with no global name: behaviour's running leaf (`task`), `fight`,
`errand`, `entries`, `grenades`, `orders` and `gait`; entry's shared leaves `state` and `world` and its parts `claim`,
`approach`, `readiness`, `orders`, `grenade`, `listen`, `pie`, `sweep`, `hold` and `radio`; combat's `throw`;
locomotion's `crowd`, `give_way`, `stall` and `doors`; the planner's `_walk` and `confines`; the launcher's `_probe`.

Two rules were settled while the parts were built:
- **Who names a member.** A part member read from outside its part is public on it: no underscore, and any prefix the
  part's name already says is dropped (`entry_ready_timeout` → `tuning.entry.ready_timeout`, `throw_stage` →
  `combat.throw.stage`, `_bang_stage` → `entry.grenade.stage`, `_apply_entry` → `behavior.entries.apply`). A member
  used only inside its part keeps its name, underscore included (`entries._detour_first`, `throw._slot`).
- **Who holds its owner.** Behaviour's, locomotion's and the controller's parts hold their Node owner (`behavior`,
  `loco`, `controller`), which ADR 0005 allows. `Entry` and `Combat` are `RefCounted`, so their parts never hold them:
  entry's parts hold only the `state` and `world` leaves, and a part method that needs the entry or a sibling part
  takes the `Entry` facade as its first parameter, `entry`, at the call, and never stores it. Combat's `throw` holds
  only the locomotion and the body, and entry's leaves and the data leaves (the cadence, the running leaf, the
  planner's walk and confines, the probe) hold no owner (`tests/ai/ai_parts_free_suite.gd`: an NPC's behaviour, entry,
  combat, locomotion and planner, with their parts and leaves, 36 pieces, all free with it).

## Consequences

Callers name the topic or the part: `tuning.senses.view_distance`, `brain.tuning.radio.callout_ttl`,
`_behavior.grenades.poll_throw()`, `_behavior.entries.take_calls()`, `_entry.state.phase`, `_combat.throw.stage`,
`_loco.crowd.held_by()`, `_planner.confines.room`. Tests set a tunable as an indexed path (`set_props(id,
"GoalController", {"tuning:entry:ready_timeout": 3.0})`), and the Testing world sets switch and child props with
`set_indexed`; `tests/ai/npc_tuning_suite.gd` proves the topic refs are there before the NPC joins the tree and that two
NPCs share no value. The spectator inspector rings a point by setting the controller's `debug_focus`. Von reads the
same requests: the snapshot, the planner's walk and `debug_state()` keep their shapes.

A tunable changed at runtime now reaches behaviour's modules on their next read, where it used to wait for the next
decision's copy; perception and the planner still take it at the next decision. Only tests retune at runtime, and
none depends on the wait.

The controller ends at 15 vars, 18 public methods and 589 lines, behaviour at 15, 19 and 585, entry at 12, 19 and
531, combat at 15 and 19 (its static facing test, `Combat.faces`, is public), locomotion at 13 and 11, the planner at
13 vars and the launcher at 15; every part and topic is within all three limits. A new tunable goes in its topic node;
a topic past 15 splits. Each NPC allocates about 45 more objects (sixteen tuning nodes and 29 parts), so a plain perf
A/B plays a different fight (the sight cadence is keyed on instance ids) and is compared on the same fight. The
architecture skill's interfaces 7 and 21 name the tuning, and its "Typed components" convention covers the AI's
parts, the two rules above and the tuning nodes.

## Considered options

- **ADR 0003 static holders:** rejected. About 28 tunables are set per NPC by tests, switches or the presets, and a
  static would set them for every NPC.
- **An exported `Resource` per topic:** rejected. An override on an inherited scene is saved as a sub-resource every
  instance shares, unless it is `local_to_scene`, so one test's retune would retune every defender.
- **A static / per-NPC split of the tunables:** rejected. It puts one topic in two homes.
- **Copy each decision, as before:** rejected for behaviour's modules. The copies were their var budget (40 vars: 15
  in `behavior.gd`, 11 in `entry.gd`, 9 in `combat.gd`), and the one change, a retune taking effect at once, is one nothing waits on.
- **`class_name` parts:** rejected. The AI's modules are preload consts, and a global name per part would add about 30
  names for no caller outside the AI.
- **Entry's parts handed a sibling part at each call:** replaced by handing the `Entry` facade. A part often needs two
  or three siblings and the leaves, and one `entry` parameter reaches them all without a cycle or a parameter list
  past `max-parameters`.
- **Exclusions or a higher threshold:** rejected by #76 and ADR 0004.
