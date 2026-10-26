# AI perception and the team split into typed parts, with perception reading its tuning live

`agent_perception.gd`, the NPC's perception facade, had 51 vars and 60 public methods in 1527 lines, against gdstyle's
`max-class-variables` (15), `max-public-methods` (20) and `max-file-length` (1000), which issue #76 turns on with no
exclusion (lines as gdstyle counts them, one more than `wc -l`, here and below). Its doorway geometry `agent_entry.gd`
had 18 vars in 1735 lines; the snapshot's `snapshot_options.gd` 22 public methods in 1426 lines and `snapshot_vocab.gd`
17 vars and 24 public methods; the stack seam's `door_stack.gd` 31 public methods; `agent_throw.gd` 24 and
`agent_tactics.gd` 21; and the team's `player_stack.gd` and `squad.gd` 30 and 26 vars.

Perception copied 17 of the NPC's tunables into its own fields and 15 into the snapshot's vocabulary on every
decision. ADR 0006 moved every tunable into per-NPC topic nodes that behaviour reads live. The controller applies the
copy just before it senses, and every copied field has its topic field's type, so a live read gives the snapshot the
same values. Perception and the vocabulary now read `tuning.<topic>.<name>` (`apply_config(npc_tuning)` sets
perception's `tuning` and the vocabulary's). Perception's nine geometry modules (vision, hostility, memory, tactics,
the doorway geometry, the door views, throw, grenades, suspicion) still take copies, because the human's stack, the
squads and the reference tests build them with no NPC.

The facade splits by topic into eight typed parts, each a `RefCounted` reached by preload const with no `class_name`,
held as a public property, built once in `setup`, and holding the perception node (a Node owner may be held):

- `sight`: the sight sense `vision`, what is in view `visible_now`, the tracks, `blind`, and the sight cadence;
- `house`: the rooms, `openings`, `entry_point`, what it has learned of the house, its post, and learning by sight;
- `contacts`: the characters it knows of, with the hostility rules;
- `hearing`: hits, footsteps, shots by room, suspicion, radio callouts;
- `orders`: its leader's order (`current`, `process`, `end`, `take_ended`, the ambush's end on contact);
- `grenades`: the grenade geometry `throw`, the live grenades `live`, the evade plan, what it carries, the last burst;
- `entry`: the doorway geometry `doorways` and the claims heard `ledger`, the stack seam `entry.stack(opening, into)`;
- `views`: the doorway views and the walk that keeps out of them (`ordered`, `walk_route`, `threshold_ahead`, ...).

The facade keeps the lifecycle (`setup`, `apply_config`, `bind`, `observe`, `sense`, `fill_goal`), the reads the
controller and combat make every tick (`under_fire`, `engaged_fresh`, `note_engaged`, `has_line_to`, `quick_facts`,
`check_lead`, `combat_spots`) and the debug reads (`memory_size`, `debug_memory`). Callers name the part, and no
forwarder stays. Both phases of the sight cadence stay keyed on the perception node's own instance id
(`perception.get_instance_id()` in the `sight` and `house` parts, never the part's own), which
`tests/ai/perception_cadence_suite.gd` checks.

The doorway geometry is a `RefCounted` built by the perception, the human's stack and each squad. Its defend and
ambush posts, its slot layout (E20 to E22) and its shared layout cache become three parts, `posts` (`EntryPosts`),
`slots` (`EntrySlots`) and `layouts` (`EntryLayouts`), which take the geometry as their first parameter, `entry`, at the
call and never store it. `geometry` and `warm_geometry` stay on it. The snapshot's grenade and order option groups move
to two sibling modules, `SnapshotThrows` (`_throws`) and `SnapshotOrders` (`_orders`), unchanged, and
`SnapshotOptions.begin()` goes. The vocabulary's room lookups move to a static helper, `HouseRooms`, and its `bind` to
a plain `character` var. The stack's slot statics move to a static helper, `StackLayout`, and its three one-line
forwards go. AgentTactics privatises six methods only it calls, and AgentThrow `release_point` (in-file only) and
`zone_radius` (two reference tests read it, as they read its other privates), its `carried` and `count` moving to the
`grenades` part.

The squad's nine follow tunables are the same for every squad and nothing writes them. They become a static holder,
`SquadFollowConfig` (ADR 0003), and the squad's stack reads become a `stacks` part holding the squad. The human's stack
keeps its exports, its bind contract and its radio. Its reservation becomes a data leaf, `reservation`, which holds no
owner and `_withdraw` clears in place, and its step-up timer becomes a `step_up` part holding the stack.

Decisions taken while the parts were built:
- **Who names a member (ADR 0006's rule, applied throughout).** A part member read from outside its part is public on
  it, one used only inside keeps its name. So `contacts.sightings`, `grenades.live`, `grenades.throw`,
  `grenades.character_rids()`, `views.sync_walks()`, `house.learn_room()` and `house.learn_next` are public, while
  `orders._ended_order`, `views._warming_since`, `house._post_set` and `house._seed_house` stay private. The entry
  part's geometry is `entry.doorways`. The squad's `stacks.ledger` and `stacks.entry` are public, its `_stacks`,
  `_stacks_cache` and `_stacks_at` private; the human's stack's `reservation.claim_frame` / `claim_pos` keep their
  names, and `step_up._stepping` / `_stepping_since` stay private. `EntryLayouts.warmed_frame` and `StackLayout.laid` /
  `on_wall` are public. `StackLayout.stack_side` keeps its name, since a `side` would be shadowed by its parameters.
- **A `RefCounted` owner under `max-parameters` (5).** `EntryPosts.defend_spot(entry, room_key, place, map, space)` and
  `ambush_spot(entry, geometry, place, map, space)` take the member's place as one `place: Vector2i` (x which post, y of
  how many). The private slot and post chains carry the entry in the per-call context dict they already take
  (`c["entry"]`, `f["entry"]`), never stored. `AgentEntry._wall_length` is static, and `EntryLayouts.shared_on` takes
  only the map.
- **Build sites.** `EntrySlots`, `SquadStacks`, `PlayerStackReservation` and `PlayerStackStepUp` are field
  initializers, as the geometry's `vision` and `views` are; nothing reads its owner at construction.
- **The snapshot modules** get only the wiring they read: `SnapshotThrows` `setup`, `know` and `begin`;
  `SnapshotOrders` `setup` and `bind`.
- **The test doubles.** The `FakePerception` double that `Behavior.setup` reads
  (`tests/ai/combat/engaged_retargets_to_visible_test.gd`) gains a null `views`, the part `Behavior.setup` hands its
  locomotion; the other (`combat_waits_for_facing_test.gd`), which only `Combat.setup` reads, needs none.

## Consequences

- Every file named above is within all three limits: the perception facade at 14 vars, 15 public methods and 418
  lines, the doorway geometry at 14, 13 and 488, the options at 18 public in 933 lines, the vocabulary at 3 vars and 20
  public, `door_stack.gd` at 19 public in 351 lines, AgentThrow at 20, AgentTactics at 15, the human's stack at 15 vars
  and the squad at 14; every new part, module and helper is within them too (the largest, `EntrySlots`, 961 lines).
  The Von text is unchanged: the option groups, sections and vocabulary words move byte for byte, and live reads give
  the copies' values.
- A runtime retune now reaches perception and the vocabulary at once, as it reaches behaviour, rather than at the next
  decision.
- 83 call sites in 19 AI files name a perception part. The 43 room lookups outside the vocabulary name `HouseRooms`,
  and the squad's follow tunables name `SquadFollowConfig` (47 sites in 13 files). `tests/ai/ai_parts_free_suite.gd`
  holds the perception's eight parts among an NPC's pieces, and a doorway geometry and its three parts, bare and an
  NPC's, by `WeakRef`: all free with their owner.
- Each NPC allocates 13 more objects (eight perception parts, three geometry parts, two snapshot modules), which shifts
  every instance id. Performance is compared on the same fight, never on a plain match run.
- The architecture skill's "Typed components" convention names these parts and the two decisions above.

## Considered options

- **Keep perception's copies:** rejected. They were the facade's and the vocabulary's var budget (17 and 15), and the
  one change, a retune reaching perception at once, is one nothing waits on.
- **Live reads in the nine geometry modules too:** rejected for now. The human's stack, the squads and the probes build
  them with no NPC, so each would need a tuning stand-in, for no gain under the limits.
- **The follow tunables as per-squad data:** rejected. Nothing tunes a squad apart; a holder matches LD21 to LD23's
  constants.
- **A forwarder for `on_stack_side` on the geometry:** rejected. Both callers name `x.slots.on_stack_side(x, ...)`.
- **The geometry's parts holding it:** rejected. It is a `RefCounted`; a part holding it is a cycle that never frees.
- **Exclusions or a higher threshold:** rejected by #76 and ADR 0004.
