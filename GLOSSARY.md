# Forced-Entry

A top-down Godot game in sixteen domains under `scenes/`; these are the words its code, tests, skills and tickets
share. The domains and their interfaces are the `architecture` skill.

## Language

### Matches

**Match builder**:
The one module that builds a match, `MatchBuilder` (`scenes/match_builder.gd`), beside Main: a match spec goes in and
a match handle comes out. Main's played, Watch and Endless matches, the Testing domain's worlds and the perf guards
all build through it, so a test measures the match Main plays.
_Avoid_: spawner (its placement helper, `match_spawner.gd`), match setup (the setup window's choices)

**Match spec**:
The plain description of one match the match builder takes: the house (a seed, a plan, an entrance, or a house
already built), each side's count, loadout and optional start points, the human (its side, whether it leads), whether
to wait for the navigation maps, and the debug overlays it starts with. Unnamed keys take the defaults, so the
invaders' default kit is the same everywhere.
_Avoid_: config (the setup window's choices, which are read into a spec), match settings

**Match handle**:
What building a match returns, a plain record of the match as built: its world, house, rooms and doorways, the
navigation region and overlays, its combatants, its squads by side and the human's stack radio. Main wires its HUDs
onto it; a test reads it.
_Avoid_: match state, match object

### Game tests

**Simulation test**:
A game test that declares a world (an arena, a hand-laid layout or a generated house), the actors and objects in it
and which behaviours are on, runs it on the sim clock and asserts what happened: a `GameTest`, `tests/**/*_test.gd`,
named by its id (`projectile/pistol_shot_wounds`). It is what proves a behaviour.
_Avoid_: GdUnit test, integration test, scenario (the real-Von tests of one AI situation)

**Wrapper suite**:
The gdUnit4 suite that runs one folder's simulation tests unchanged, one case per test id, its cases read from the
folder's files: `tests/<domain>/<domain>_suite.gd`, or `tests/ai/<topic>/<topic>_suite.gd` for an AI topic folder.
The harness's own tests have one apart, run only by `--self-test`.
_Avoid_: test suite (any gdUnit suite), runner

**Unit suite**:
A native gdUnit4 suite of pure logic (`tests/<domain>/<name>_suite.gd`, extends `UnitSuite`): gdUnit's own asserts on a
pure function, no world. It always supplements the simulation tests, never replaces them.
_Avoid_: unit test (for a simulation test), native test

**Change's tests**:
The game tests (`tests/**/*_test.gd`) a change added or modified since its merge-base with `origin/main`, committed or
not; deleted tests, test helpers and sandboxes are not among them. `tools/play_tests.sh` plays them in a window.
_Avoid_: new tests, my tests, ticket tests

### Runtime coverage

**Run source**:
What a coverage run measures: **matches** (seeded matches played with no human, the Von server live) or **tests** (the
game tests). A report combines the newest run of each source for one commit.
_Avoid_: mode (a match's Watch or Endless mode)

**Instrumented copy**:
A throwaway copy of the repo, in the repo's gitignored `artifacts/tmp/`, in which every statement of the game's
scripts counts its own hits, on the statement's own line so lines match the source. Only the copy is changed; the
real tree stays byte-identical. A run removes it however the run ends, unless kept (`--keep`, `instrument`).
_Avoid_: build, sandbox

**Statement map**:
The list of every counted statement of one instrumented copy: its file, line, kind (function entry, branch arm or
plain statement), function and inner class. Hits are read through it, so a map belongs to one build.

**Hit file**:
The hit counts a run produced, kept apart by unit: one per match, or one per test plus one for the hits made while no
test ran. The hit files of parallel processes merge into one with the same totals.

**Uninstrumented span**:
Code the scanner was not sure how to count and left without counters. The report lists it in its own section and never
reads it as dead.

**Uninstrumented run**:
Matches played with the probe but no counters: the baseline for the counters' cost and for whether they change what a
match does. A report never reads it.

**Failed under instrumentation**:
A game test that failed or timed out in the instrumented copy. Its hits still count; a wall-clock budget can fail from
the counters' cost alone, any other failure is worth checking in the real tree.

**Von starvation**:
A match whose NPCs got fewer Von decisions per game minute than a floor (half the rate of quiet single-process
matches), because the decision server was busy. Its NPCs hold steady, so AI and combat code reads as less run than it
is; the run and the report warn.

### Report tags

Zero hits means "did not run in the sampled matches or tests", never unreachable: every tag is a lead to confirm.

**Dead**:
No hits in any run, and nothing references it.
_Avoid_: unused, unreachable

**Dead branch**:
A dead branch in a live function: an arm of an `if`, `match` or loop that never ran, inside a function that did.

**Test-only**:
Hits in the tests, none in the matches.

**Untriggered system**:
No hits in any run, but referenced: wired up and never triggered in the sample.

**Rare**:
Ran in fewer than 10% of the matches.

**Live-but-unpinned**:
Hits in the matches, none in the tests: live code no test holds in place.

**Noise**:
Code that is not play: the test harness, the dev command server, the debug overlays, the settings menu. Tagged, never
hidden; matches never drive it, so its zeros say little.

### Where an NPC acts

**Confinement**:
An NPC's three rules for where it may act: its territory (a defender keeps inside the house), the room a `defend_room`
order keeps it to (`docs/leadership.md` LD8) and its squad leash (a follower holding no order fights within the leash of
its leader, LD23). All of them must hold at a point. It is one perception part, `confinement`
(`scenes/ai/perception/perception_confinement.gd`), refreshed each tick by the controller; the planner's COMBAT filter
reads the copy frozen into the decision snapshot, behaviour and Combat the live one. An option is judged where it acts
(the spot a grenade is thrown from, else its point), so a territorial defender inside may throw onto a spot outside.
_Avoid_: confines, territory (one of its three rules), leash (another), hold ground (the fight's answer to a contact
where it may not act)

### Tactical entry

**Stack**:
A doorway's stack: the members going into a room through one doorway together, each holding a numbered slot beside it
(slot 1, the point, nearest the door; on one side of the door, or both for a split stack), as the radio describes it
(`docs/tactical-entry.md`). The human invader is a member like any other.
_Avoid_: queue, team (all of a side's members), file (one side's line of slots)

**Claim**:
One member's place in a stack as it radios it: an `&"callout"` with an entry step (`claim`, `ready`, `bang`, `going_in`,
`in`, ... `abort`, `done`), the doorway, its slot and side, and the fields every reader settles the stack by, encoded and
decoded only by `StackClaim` (`scenes/ai/perception/stack/stack_claim.gd`). A member's latest claim replaces its
earlier one; the human's is a full claim too.
_Avoid_: reservation (the human's slot in an allied stack, E16, is one claim), callout (any radio call)

**Claim ledger**:
The claims one listener has heard, the latest per speaker, current for its ttl on the game clock: a `ClaimLedger`, one
each for an NPC's perception, the human's `PlayerStack` and a side's `Squad`, each hearing its own side within its own
range (the squad's unlimited).
_Avoid_: claims cache, heard callouts (the perception's memory of what allies say they do)

**Door stack**:
A doorway's stack built from its geometry and the claims a ledger holds: a `DoorStack`, the one place every slot rule is
settled (same-frame ties and move-up, the human's slot, sides, files, tail and dead ends, the crossing order, the
thrower, whether the stack is held for its leader's go and its release, the mode it goes in) and a slot becomes a
point, so every reader gets the same answer.
_Avoid_: stack layout (its `layout()`, what the markers draw), slot rules

**Stack member**:
One member's own claim in a stack, as it keeps it: a `StackMember` (`scenes/ai/perception/stack/stack_member.gd`)
holding its slot, side, claim frame and spot, step, grenades and order fields, and running claim, keep and settle
against a `DoorStack`, the side it asks for handed in. Each NPC's entry and the human's `PlayerStack` own one, and the
snapshot's slot guess, the perception's held room and the human's look for a team build one for a moment; its `me()` is what a `DoorStack` reads of a member asking about itself.
_Avoid_: me dict, reservation (the human's E16 slot is one stack member's claim)

### Squads and orders

**Attack doorway**:
The doorway into the AI defender leader's room that an attack from a threat its side's radio placed comes through: the
last doorway on the shortest way, doorway to doorway, from the threat's room (outside counting as a room) into the
leader's (`scenes/ai/team/attack_door.gd`, `docs/leadership.md` LD29). Its crew is ordered to ambush it.
_Avoid_: entry door, front door (an attack doorway may be any doorway of the leader's room)

**Rear guard**:
The member an AI defender leader keeps back when it orders three or more to ambush the attack doorway: the last spawned
that is not the leader. It holds no order, follows the leader and is free for the next order (`docs/leadership.md`
D34).
_Avoid_: lookout, sentry (it watches no approach of its own)

**Primed ambusher**:
An NPC holding the ambush of its live order at its post: its sight tests every character in its view cone every frame
and its body moves after every other in the frame, so it wins a same-frame tie with an entrant (`docs/leadership.md`
D37).
_Avoid_: posted ambusher (one still walking to its post is not primed), camper

### Lint

**Lint rule**:
A project-specific check over the tree that the engine's analyzer cannot make, one module per rule. It reports lines
and never fixes them, one failing rule fails the lint, and a justified exception is a visible allow entry with a
reason.
