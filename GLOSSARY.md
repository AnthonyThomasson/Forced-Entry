# Forced-Entry

A top-down Godot game in seventeen domains under `scenes/`; these are the words its code, tests, skills and tickets
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
already built; a generated one stands in the centre of a district), each side's count, loadout and optional start points, the human (its side, whether it leads), whether
to wait for the navigation maps, and the debug overlays it starts with. Unnamed keys take the defaults, so the
invaders' default kit is the same everywhere.
_Avoid_: config (the setup window's choices, which are read into a spec), match settings

**Match handle**:
What building a match returns, a plain record of the match as built: its world, house, rooms and doorways (the
house's alone), the district when one was generated, the navigation region and overlays, its combatants, its squads by
side and the human's stack radio. Main wires its HUDs onto it; a test reads it.
_Avoid_: match state, match object

### The world

**House**:
The building a match is fought over, the one the AI's rooms and doorways describe: defenders spawn in it and the
invaders enter it. In a district it is the tower in the centre block; a test world may also be a lone house standing
by itself. Every other tower is scenery to the AI, outside the house.
_Avoid_: building (any structure), base

**District**:
The whole world a match is generated into: a 3×3 grid of blocks, the streets between and round them, and a ring of
shells past the outer street. One seed reproduces all of it. The house is the centre block's tower.
_Avoid_: city, map (the navigation map), level

**Block**:
One cell of the district's grid: a tower and the sidewalks round it. The streets run between blocks.
_Avoid_: lot, plot, cell

**Tower**:
An enterable building of a district whose ground floor is built: the walls, doors, furniture and lit rooms of a floor
plan, with one front door onto its block's street, at most one back exit and one elevator lobby. It reads as tall (a
long shadow, a podium, an awning over its door) but has nothing above its ground floor. Nobody spawns in a tower that
is not the house.
_Avoid_: building, skyscraper

**Shell**:
A roofless closed building past the district's outer street: a solid outer wall with no doorway, a floor and a few
partition walls, bare, under construction or derelict. It cannot be entered, is no room for the AI and is left off the
navigation map.
_Avoid_: ruin, building (a tower)

**Elevator lobby**:
The empty placeholder room in every tower, marked on its floor "WIP ELEVATOR LOBBY", where stairs and elevators to
the upper floors will go. It holds no furniture and has one interior doorway and no door to the street. In the house it
is an ordinary room to the AI.
_Avoid_: lobby (a tower's front room), elevator

### Game tests

**Simulation test**:
A game test that declares a world (an arena, a hand-laid layout or a generated house), the actors and objects in it
and which behaviours are on, runs it on the sim clock and asserts what happened: a `GameTest`, `tests/**/*_test.gd`,
named by its id (`projectile/pistol_shot_wounds`). It is what proves a behaviour.
_Avoid_: GdUnit test, integration test; for a test of one AI situation against Von, say scenario test (a Von test)

**Von recording**:
The Von answers of one `requires_von` test, kept beside it as `<name>_test.von.json`: each ask's key (state text, question
and sorted option descriptions) with the pick Von gave. Replay answers from it, so the test needs no server.

**Replay mode** / **record mode** / **live mode**:
How a Von test's decisions are answered. Replay (every normal run) reads the recording; record (`--record-von`) asks a live
server and rewrites the recording; live (`--include-von`, `--require-von`) asks the server and touches no file. All three
deliver each answer the same number of physics frames after its ask.

**Live-only test**:
A `requires_von` test marked `live_only` that never replays: it tests the Von transport itself, or a fight no replay
reproduces. It is skipped without a server.

**Own-process test**:
A test marked `own_process`, run by `run_tests.sh` after the others in an engine process of its own, because its replay
matches its recording only in a fresh process (a debt that needs a follow-up ticket).

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

### The decision

**Decision job**:
One NPC decision as a resumable job (`decision_job.gd`): the claim against the frame's pool, the snapshot build, the order-refusal step, the group piece, the throw piece, the grenade piece and the planner's walk, run piece by piece (the radio callouts are read again as the last of them ends, the last thing before the walk). The controller only asks it for a decision (`request`) and advances it (`advance`); a claim over a job in flight drops that job without a signal, and a refused one leaves the job and the NPC's wish as they were.
_Avoid_: decision walk (the planner's part of it), decision task

**Work unit**:
What `DecisionBudget` counts: a pool of `per_frame` units a physics frame shared by every NPC, spent by pieces at their static `cost_*`. Counted, never timed, so a decision starts the same frame on any machine. A unit is about a millisecond (`decision-prices.md`): the default pool is 4 a frame and a typical decision lands over two to three frames. The pool is served oldest claim first (`decision_roster.gd`), at most one decision beginning in a frame.
_Avoid_: tick, time slice, budget (the pool's own name is `DecisionBudget`)

**Piece**:
One step of a decision job with its own price: the snapshot build's start, one analysed hostile, its finish, the order-refusal step, a step of the group, throw or grenade piece, or one planner level. A frame whose pool is untouched runs the next piece even if it costs more than the pool.
_Avoid_: stage, chunk

**Throw piece**:
The decision job's piece between the order-refusal step and the walk: the `grenade_ready` search for a throw the NPC could make, in steps of a count (a block of raw throw-spot candidates, the rank pass, one route), each priced by `DecisionBudget`'s `cost_throw_*`. Its answer is the one-shot search's and lands in the snapshot's facts before the planner reads it (`ThrowSearch`, `ThrowScan`; the spots themselves, `ThrowSpots`).
_Avoid_: grenade piece (the other piece's name), throw stage

**Group piece**:
The decision job's piece between the order-refusal step and the throw piece: it builds ahead of the walk the option groups the root reads whatever the situation, `leads` (and `entries` first while a stun can be thrown), a lead or a doorway a step (`GroupBuild`, `GroupSteps`, priced by `DecisionBudget`'s `cost_group_unit`), only for a decision that starts at the root. Its groups equal the one-shot build's and are stored in the snapshot's demand, so the planner finds them built. The **grenade piece**, after the throw piece, builds the throws at the hostile the search found one at, one grenade kind a step (`decision-groups.md`).
_Avoid_: lead piece, prefetch

### Where an NPC acts

**Confinement**:
An NPC's four rules for where it may act: its territory (a defender keeps inside the house), the room a `defend_room`
order keeps it to (`docs/leadership.md` LD8), its squad leash (a follower holding no order fights within the leash of
its leader, LD23) and the room a stack held for its leader's go is to enter, which a member of it keeps out of (LD13, D38). All of them must hold at a point. It is one perception part, `confinement`
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

### Doors

**Doorway**:
The gap in a wall between two rooms, or between a room and the street, as `WorldGen.get_openings` reports it: its centre
(`pos`) and its `width` (60 px inside, 69 px for the front and the exits), cut in the wall's centreline. A wall's collider
reaches half its thickness into the gap, so the free passage between the jambs is narrower by a wall's thickness. A
doorway with no door is an open gap.
_Avoid_: door (the leaf that may stand in it), opening (the data record of one)

**Door**:
The hinged leaf standing in a doorway: a `Door` (`scenes/objects/door/door.gd`), a body driven by code, in four materials
(hollow-core, solid, steel, glass-panel) and their styles. It opens one way only, is damaged, bursts open at a kick and is
knocked down at 0 HP. It publishes the door contract (architecture interface 24).
_Avoid_: door stack (the AI's stack of members at a doorway), vehicle door (a car's, `VehicleDoor`)

**Leaf**:
The swinging panel of a door, which the door's body is: a rectangle a little shorter than the door's `width` (`DoorConfig.leaf_slack`) and `leaf_thickness` thick (`leaf_size()`), turned about its
hinge between shut and `open_angle` (90°). Knocked down, it lies flat on the floor as a slab and is no longer a leaf in the doorway.
_Avoid_: panel, slab (the leaf lying down)

**Push side / pull side**:
The two sides of a door. The pull side is the room the door swings into (`swing_into`): the leaf comes toward someone
standing there as it opens. The push side is the room it swings away from: a kick or a blast from there drives the leaf the way it
opens and wears its latch; from the pull side it only damages the door.
_Avoid_: front/back, inside/outside (a door between two rooms has neither)

**Latch side**:
The side of a door's doorway opposite its hinge, where the latch jamb and the handle are: where someone stands to work the
door (`latch_side_spot(from)`). The hinge side is the other.
_Avoid_: handle side, open side

**Ajar**:
A door open part way: more than shut and less than wide open. A door is shut at 0°, wide open at its `open_angle`, ajar between; one
passes a character once its `gap()` is wide enough. An ajar or open door is not latched: one kick from its push side throws it open, a
walker turns it about its hinge, away from the walker (`docs/doors.md` DR10).
_Avoid_: half-open

### The player's view

**View**:
What the screen shows of a match for the human: the live world inside the view cone, the memory outside it and nothing that
moves out of the cone. It is built for one character, the human in a played match; Watch and Endless have none.
_Avoid_: fog of war, vision mask, player view (the node's name)

**View cone**:
The exact area one character sees right now: the cone round its facing out to its view distance, joined to the near bubble round
it, bounded by whatever breaks its line of sight (walls and tall furniture, not low furniture or a glass-panel door).
_Avoid_: field of view (only the cone's angle), sight cone, vision cone (the NPCs' debug drawing of the same area)

**Cone job**:
One rebuild of the view cone, stepped `slice_units` of engine work a physics tick (`ViewCone.begin` / `step`, run by `ViewPipeline`) and published when done: the cone shown is the exact cone of the pose the job started from, usually 2 to 4 frames old (up to 6, at most 10 for the longest job), in the world as it was then. A change of the world between slices restarts it from the live pose; a change of the viewer's pose alone does not.
_Avoid_: rebuild (the whole of it in one frame is still `ViewCone.rebuild`), pose lag (the old one-frame wait, gone), decision job (the AI's)

**Published pose**:
The eye and facing a cone job started from, which the cone shown is the exact cone of (`PlayerView.published_pose()`): a pose the viewer stood at usually 2 to 4 frames ago (at most 10), never one made up.
_Avoid_: current pose, live pose (the viewer's now)

**Memory**:
The picture of the world as the human last saw it, drawn in greyscale outside the view cone and black where it never looked. It
holds only what was on screen when seen, starts empty with the match and never fades.
_Avoid_: fog, explored map, the AI's memory of what it knows

**Moving / at rest**:
Whether a thing is drawn only inside the view cone or is remembered where it lies. The living, bullets, grenades in flight,
hit particles, flying debris, blood spray, a burst's look and a vehicle under way are moving; a dead body once its ragdoll
sleeps, a dropped item, a spent casing, a grenade lying still, a parked vehicle and the house and street are at rest.
_Avoid_: dynamic / static, live / baked

**Seen area**:
The part of the world the view cone shows live this frame (the cone last published). A character or a blood pool wholly outside it is not repainted, since
nothing would show it.
_Avoid_: visible region, culled

### Lint

**Lint rule**:
A project-specific check over the tree that the engine's analyzer cannot make, one module per rule. It reports lines
and never fixes them, one failing rule fails the lint, and a justified exception is a visible allow entry with a
reason.
