# Doors

How the houses' doorways and the doors in them behave: issue #21 "Add doors". A doorway is the gap in a wall between two
rooms (or between a room and the street); a door is the hinged leaf that can stand in it. Rules DR1 to DR14; each is
enforced by the tests named under it (`tools/run_tests.sh <id>`), following the convention of `docs/tactical-entry.md`. The
research behind the numbers is `docs/research/doors-in-room-entry.md` (scale: 1 m is about 55 px, a character's body radius
14 px). The tactical use of doors by the AI (entry on a shut door, cracking it, breaching, defenders shutting doors) is the
follow-up ticket #159 and is not in this spec.

The doors of the old AI families' scenario tests are switched off (`worldgen.doors`) until #159 makes those families
door-aware.

## DR1. Doorway size

Every floorplan's doorway is 52 px wide (about 0.9 m) inside the house and 60 px (about 1 m) for the front and the `exit`
doorways, about the width of a door beside characters 28 px across. The width is the gap
`WorldGen.get_openings` reports (`width`) and the one `WallFactory` cuts into the walls, in both mirror states of a plan.
Every floorplan still passes `LayoutRules` and the furnisher (no "no room for required zone"), and every plan still bakes and
connects over its seeds.

Tests: `worldgen/doorway_widths` (every floorplan, both mirror states: 52 px inside, 60 px at the front and exits, read through
`get_openings`; the widths are the brief's numbers, kept in the test), `worldgen/house_doorways_connected`,
`worldgen/layout_rules`, `worldgen/house_rooms_furnished`.

## DR2. Which doorways get a door

The front and the `exit` doorways always get a door. An interior doorway's chance comes from its more private room's type
(`DoorRules.ROOMS`: each room type's `rank`, how private it is, and `chance`; the doorway's chance is that of the higher-ranked
of its two rooms, the larger when both rank alike):

| Room type | Rank | Chance |
|---|---|---|
| bathroom, netrunner den | 4 | 1.0 (always) |
| bedroom, home office, ripperdoc | 3 | 0.85 (mostly) |
| garage, laundry room | 2 | 0.5 |
| kitchen, kitchenette, living room, kitchen-living, studio, security vestibule | 1 | 0.15 (rarely) |
| hallway | 0 | 0.0 (so between two hallways: never) |

A floorplan may force or forbid a door on one opening, a front or exit one too (its say wins; the plans use it only inside) (`door: true` / `false` on the opening in `HouseDefinitions`; the plans use
it for a nook left open between the great room and a bedroom, a kitchen door forced, a glass office door forced) and names its
door sets (`door_sets`: the `DoorCatalog` doors its `front`, `exit` and `interior` doors draw from, and any set an opening's
`door_set` picks, such as the patio's or the office's). With none named, a kind draws from `DoorRules.SETS`: solid wood
(panelled, plank) at the street and at an exit, hollow-core (flush, panelled) inside. The flats and the loft (`studio_flat`,
`one_bed_flat`, `two_bed_flat`, `office_loft`, `railroad_flat`, `micro_flat`, `corner_flat`) have steel doors (riveted, peephole)
at the street; the houses solid wood; `open_plan_home`'s patio exit and `office_loft`'s office door are glass-panel.

Each doorway rolls from a stream of its own, `hash([run seed, "doors", its index in the plan])`, that always draws the same values
(the chance, the two ties, the door of its set, its start state and angle) whatever it turns out to be, so a door never shifts
another's roll nor the furniture layout of the seed: it is the same with `worldgen.doors` off (the switch, `WorldGenDoorConfig`,
which builds no doors and leaves the doorways as open archways) as on. The house reports each opening's `door` and its doors
(`WorldGen.get_openings`, `WorldGen.get_doors`: `{ node, opening, material, style }`).

Tests: `worldgen/door_placement` (every floorplan, both mirror states: front and exits always a door, a bathroom and a netrunner
den always, bedrooms, offices and ripperdocs mostly, kitchens, living spaces and studios rarely, a forced and a forbidden opening
held, the doors drawn from the house's sets, the furniture the same with the switch off), `worldgen/door_rules_suite` (the rules
table: two hallways never share a door, which no floorplan builds).

## DR3. Swing and hinge

A door opens one way only. An interior door swings into its more private room (the higher `DoorRules` rank; a tie: seeded), an
exterior door into the house. Its hinge sits on the jamb nearer that room's corner along the wall (in the middle of the wall:
seeded), 6 px in from the gap's edge, where the walls' ends stand, so the fully open leaf (`open_angle`, 90°) lies out from that
jamb along the wall. A mirrored plan mirrors its hinges, as the doorway is mirrored with the rooms. The swing arc (a quarter disc,
the leaf's length, from the hinge across the doorway into the room) is kept free of furniture, clutter and the neon tube as the
doorway clearance is: it lies inside that box (`HouseSpawner.OPENING_CLEARANCE` deep each side of the wall, as wide as the
doorway), which the furnisher and the dresser keep clear, so nothing is added to the spawner's `blocked` areas for it. The fit is tight at the front and exits (the
open leaf reaches 50 px out and 30 px along from the doorway's middle, exactly the box), so a change to the clearance, the leaf or the
doorway widths is caught by the test, not by the spawner.

Tests: `worldgen/door_swing_and_hinge` (every floorplan, both mirror states: the swing room, the hinge on the corner jamb, the open
leaf along the wall, no furniture, clutter or neon tube in the arc, both outcomes of a tie).

## DR4. State at the start

Front and exit doors start shut. An interior door is seeded per door, from its own stream (DR2): shut, ajar (15 to 35°) or open
(`open_angle`), by the weights `DoorRules.START_WEIGHTS` (0.6 / 0.15 / 0.25).

Tests: `worldgen/door_start_state` (front and exits shut, interior doors in all three states by the weights over the seeds, the
same per seed).

## DR5. What a door blocks

A standing door (shut, ajar or open) is a solid leaf in the world: a body on the solid layer that stops characters like a wall
(`tests/objects/door_blocks`: a puppet walking into a shut door stops at it), is struck by rounds at every height (`coverage` 100)
and lets them through by its material's `penetration` by the usual rule (a hollow door slows a pistol round by 9%, a steel one by
81%, which the pistol's `projectile_min_speed` does not survive: the round goes on through hollow, stops in steel; a rifle
round goes through steel), blocks the AI's sight and casts a shadow (a light occluder on the walls' mask that turns with the leaf).
The glass-panel door is the exception: its surface says `transparent`, which sight reads (an NPC on one side sees a puppet on
the other through it, not through a wooden door) and it casts no shadow; a round still meets it (penetration 5). A knocked-down
door blocks nothing (DR11).

It is in neither nav bake (planning, steering): paths go through a doorway as before and the walker deals with the leaf
(`docs/adr/0010-doors-are-driven-bodies-left-out-of-the-nav-bake.md`).

Tests: `objects/door_blocks` (the body, the rounds, sight and the shadow), `navigation/door_not_baked` (both maps path through a
shut door's doorway).

## DR6. Use (E)

The `use_vehicle` action is `use` (`Keybinds.USE`, default E, label "Use (door, vehicle)", rebindable; a binding saved under
`use_vehicle` comes back as `use`, and one saved under `use` beside it wins). In a vehicle, Use gets out, even with a door in
reach. Otherwise it acts on whichever is nearest: a standing door in reach ahead, or a vehicle's door to get in by
(`CharacterUse.use_target()`: the distance from the body to the door's leaf, at its nearest point, against the distance to the
vehicle door's handle). A door is in reach (`character.use.doors.door_in_reach()`) when its leaf has a point within
`CharacterDoorConfig.reach` (48 px) of the body that lies ahead of it (the side the character faces); of those, the one whose leaf is
nearest the aim. A knocked-down door is none. Tap: an open door (or one swinging open) swings shut, a shut or ajar one swings fully
open, in `DoorConfig.swing_time` (0.4 s). A vehicle is acted on at the press, as before; a door's toggle comes at the release of the
key, so that a hold can scroll instead (DR7), and a hold that does not scroll toggles at its release. The player's controller remembers the door the key went down on, so the release and the wheel act on that door while it stays in reach, whichever door the aim is nearest by then (`use(door)`, `turn(steps, door)`). `character.use.doors` takes no input event: the test puppet's `use()` / `turn_door(steps)` call `character.use.try_use()` / `character.use.doors.turn(steps)` as the player's controller does, and the AI (DR14) works a door with `character.use.doors.open_fully(door)`.

Tests: `character/door_use_key` (E held moves nothing, its release opens a shut door fully and the next E shuts it; with a door and a
car's door both in reach E acts on the door when it is the nearer and boards when the handle is, and leaves the open door as it is;
seated, E gets out with a door in reach; an ajar door swings fully open), `general/use_vehicle_key` (the `use` action, its default, label, group, settings row, no
clash; a `player` boards and gets out), `general/settings_file` (the old saved name comes back as `use`).

## DR7. Gradual opening

While Use is held on a door (the press began on one), each wheel notch turns it by `DoorConfig.step_degrees` (10°), wheel up
(`ZOOM_IN`) opening and down (`ZOOM_OUT`) closing, between shut and fully open, and it stays there. A trackpad's two-finger scroll turns
it by the notches the camera counts that scroll as (`Keybinds.scroll_notches`: `CameraConfig.trackpad_zoom_sensitivity` notches per unit
of `delta.y`). The player's controller takes those events before the camera reads them, so the camera does not zoom meanwhile, and
releasing Use after scrolling does not toggle. With Use not held, or no door in reach (`doors.turn` is false), the scroll goes on to the
camera and zooms it as before.

Tests: `character/door_scroll_open` (three notches up turn the door 30°, a notch down back 10°, the camera's zoom unchanged, E let go
leaves the angle; a trackpad scroll turns it by the notches the camera counts it for; fully open and shut are the limits; between two doors the one E went down on is turned, not the one the aim moves to; the puppet's `turn_door` and `use`; with E not held
or held with no door in reach the wheel zooms), `general/camera_wheel_zoom` (unchanged).

## DR8. A swing meets something

A swinging door nudges any character in its arc (the quarter disc its leaf sweeps) out of the way, the one who opened it too:
before the leaf turns on, the physics space is asked what stands where it will be; a character is moved straight away from the
leaf by what clears it, no faster than `nudge_speed` (600 px/s; at the tip of the longest leaf, a front doorway's 48 px, the swing peaks near 280 and a burst runs at 450). The swing stops
short, and stays there, at a wall, at furniture (the furniture is not pushed) and at a body that cannot move further: a
character with a fridge or a wall at its back, or whom the leaf outruns, is not squashed or shoved through it.

Tests: `objects/door_nudges` (a puppet in the arc, the opener and a chair; a puppet pinned against a fridge),
`objects/door_nudge_speed` (a nudge slower than the leaf stops it).

## DR9. Damage

Each door has its material's HP. A round or a fragment, a punch, a kick and a blast count against it, each by its material's
factor for that kind of hit (`round_factor`, `melee_factor`, `kick_factor`, `blast_factor`); a kick is the strike whose shove, in the same
frame, was `burst_impulse` or more, anything softer from a hand is a punch. The leaf shows its dents and bullet holes (a `Deformable`
on it; its collider is kept) and throws debris of its material. A glass-panel door's first round or blast shatters its panes: it is drawn
without its glass, its hits sound as wood from then on, and the frame stays, standing, with its remaining HP.

| Material | HP | penetration | round | melee | kick | blast |
|---|---|---|---|---|---|---|
| hollow-core | 80 | 10 | 1.0 | 1.0 | 1.5 | 1.5 |
| solid wood | 250 | 45 | 0.8 | 0.5 | 1.0 | 1.2 |
| steel | 1200 | 90 | 0.5 | 0.1 | 0.05 | 1.0 |
| glass-panel | 80 | 5 | 1.0 | 1.0 | 1.5 | 1.5 |

Tests: `objects/door_damage` (rounds, a punch, a kick, a frag's blast and fragments, a kick on steel, each against its factor; the
panes).

## DR10. Burst open

A kick or a blast on a shut or ajar door from the side it swings away from (its push side: the strike drives the leaf the way it
opens) wears down its latch by the strike's own damage (a kick deals 14, a frag up to 60); when the latch's `latch_hp` is gone, the
door swings fully open at once (`burst_speed`, 540°/s: a burst is faster than a swing, 0.17 s). A hollow door's latch (20) holds the first
kick and gives to the second; a solid wood door's (60) to the fifth; a steel door's (50) to no kick (a boot cannot move its bolt) but to a
frag; a glass-panel door's (20) to the second. A walking push (a shove of about 900 a frame) and a punch (900) are below
`burst_impulse` (1500; a kick is 2200) and never count. From the other side (the pull side) a kick or a blast only damages the door,
and a door that has burst stays unlatched.

Tests: `objects/door_kick_burst` (a hollow door's second kick, the pull side, steel, solid at the fifth, punches, a walker).

## DR11. Knocked down

At 0 HP the leaf comes off its hinges and falls flat into the room the last blow pushed it toward (a kick's shove, a round's or
a blast's direction; the room it swings into when the blow had none): it lies on the floor beyond the doorway, `fallen_length` (100 px)
long, its length along the way it fell, drawn face up at the lying bodies' rung. Walk-over (no collider), no cover, blocking no shot,
sight or light (its shadow is gone), and no longer usable (`toggle`, `turn_by` and `open_fully` do nothing); the doorway is clear
(`gap()` is its whole width, `open_amount()` 1).

Tests: `objects/door_knocked_down` (four kicks from the east lay a hollow door west; four rounds from the west lay one east; a puppet
walks over one, a round and an NPC's sight pass).

## DR12. Sound

Every door sound is synthesized in code like the other families (no audio files). A door posts a `&"door"` event
`{ position, door, material, stage }` on the EventBus at each stage of its life, at the middle of its doorway, and `Sound` voices
it through its pooled positional voices (category `door`: at most 4 at once, the oldest cut off first, heard out to 1200 px, the
same range, jitter and `audio.sound` switch as the rest): one voice per event, the profile `leaf/<material>/<stage>`
(`SoundDoors`), `material` the door's (`hollow`, `solid`, `steel`, `glass`).

| Stage | Posted when | Sounds like |
|---|---|---|
| `open` | a swing starts to open (a Use, a notch of the scroll) | the swing: the handle's click, then a creak; wood creaks (hollow brighter, solid lower and slower), a steel door groans lower still, a glass-panel door's frame creaks like wood |
| `shut` | the leaf arrives at shut (the latch as it closes) | a click, the latch seating and a thud; a steel door clangs |
| `burst` | the latch gives (DR10) | the bang: the latch cracking and the leaf slamming the wall, wood splintering, steel clanging |
| `down` | the leaf falls (DR11) | the splinter and thud of the fall; a steel door's is a heavy clang that rings on |
| `glass` | a glass-panel door's panes shatter (DR9) | a crack, a rush and the shards tinkling down (this stage has a sound for the glass-panel door only) |

**No spam.** A gradual scroll (DR7) turns the door a notch at a time, each notch a swing opening it a little further; only the first
of a movement creaks. The door remembers when it last began opening (`_opened_at`); a swing opening it within `DoorConfig.creak_gap`
(0.6 s) of that carries on the same movement and posts no `open`, and every opening swing renews the time, so a run of notches is
one creak (the clip is half a second) however long the scroll lasts. A movement ends when the door rests for the gap, or when a
closing swing begins (a reversal): a notch after a rest, and an open, shut, open in quick succession, creak at each opening. A
closing swing posts nothing until its leaf arrives at shut, so a scroll back down to partly open is silent, and a toggled door
creaks once on the way open and clicks once on the way shut. A burst and a fall are single events (a burst is not also a creak).

Tests: `audio/door_sounds` (a hollow door used open and shut, burst by two kicks and felled by four, a steel door used open and shut
and burst by a frag, a glass-panel door's frame opened and its panes shattered by a round: each posts one `&"door"` event with its
stage and material and plays one voice of `leaf/<material>/<stage>` at the door; five scroll notches in a row, and six a quarter second apart (longer than the gap), creak once, a notch
after a rest creaks again, and a door opened, shut and opened again at once creaks at each opening; the steel door's latch, burst and fall ring on past the wooden door's, its groan is lower than the creak,
the glass shatters bright), `audio/bank` and `audio/prewarm_covers_every_variant` (every door profile renders and is pre-warmed).

## DR13. Materials and styles

Hollow-core wood (flush, panelled), solid wood (panelled, plank), steel (riveted, peephole), glass-panel (wood frame with panes),
each drawn in the run-down look (the top edge of the leaf in the style's pattern, a hinge pin and a handle, scratched wood or rusted
steel, grime), each with its HP, penetration and latch (the table in DR9; the latch in DR10): an interior door is concealment, not
cover, and steel stops a pistol, not a rifle (research §3, §4). The catalogue (`DoorCatalog`) has one definition per material and
style; the leaf's art and a knocked-down door's face are the door painter's.

Tests: `objects/door_materials` (every material and style spawns, draws, each style differently, with its HP and penetration);
`objects/door_contract` (the contract the Use key and the AI drive).

## DR14. The AI opens doors in its way

An NPC whose walk leads through a door not open wide enough to pass (`gap()` below its body's diameter and a 6 px margin: 34 px for a
body of radius 14), whatever primitive is walking (a move, a search, a follow, a defend, a throw's walk, the entry's approach and cross),
stops beside it on its latch side (`latch_side_spot`, within 20 px of it), faces it, uses it until it is fully open (`open_fully` through
`character.use.doors`, never a toggle, so a second NPC reaching a door the first opened does not shut it) and walks on, leaving it
open. The door is found on the next 90 px of the walk's path by the group `doors` and read through the door contract (interface 24),
so the AI imports nothing of Objects. A door open wide enough, or knocked down, is no obstacle. A second walker finding another at
the latch waits 40 px further out from the wall until the door is passable, so two never stand pressed against each other at the
doorway. A door used twice that stops short of opening wide enough (a chair or a body held in its arc, the swing stopped) is given up
on: it is refused for 45 s and the walk is a blocked one (the existing way-blocked handling: the decision re-runs, `decision_reason`
"way blocked"). While it is refused, a walk whose way runs through its doorway goes by another doorway of the house first (the
nearest by walking length whose two legs cross no refused door), and a walk with no other way stands short of the door and tells the
decision its way is blocked every 1.5 s. The tactical entry's point man meets a shut door on its cross and does the same: a stop-gap
until #159, which gives a stack its side, the opener's role, cracking and breaching; none of that is built here. A shut door blocks
sight (DR5), so the room behind it is not covered by sight, and so not counted searched, until the door is open and the NPC is in.

Tests: `ai/movement/door_in_the_way` (real Von, hand-laid house: two invaders search the one room behind a shut door, one opens it
from the latch side, goes in, leaves it open, the room not searched while it was shut), `ai/movement/door_blocked_rerouted` (real
Von: a chair in the swing holds the nearer door shut, the walk is a blocked one and the defender goes in by the other doorway),
`ai/movement/door_second_walker_leaves_open` (real Von: two defenders reach the door together; the leaf never turns back toward shut).

## Trying doors by hand

The **Gun range** sandbox (`sandboxes/player_gun_range_sandbox.gd`, from Tests → Sandboxes; never run by the suite, nothing asserted)
has four small rooms built onto the outside of the range's north wall (y < 0), 240 px square side by side from x -360 to 600, each
opening onto the range through a 52 px doorway, and a 52 px doorway between each neighbouring pair: all seven catalogue doors once.
On the range side, each with a floor label naming its material: a hollow-core `flush` door (shut, swinging into its room), a solid
wood `panelled` one (ajar, swinging out into the range), a steel `riveted` one (shut, swinging into its room) and a glass-panel
`panes` one (shut, swinging into its room, with a dummy inside it seen through the panes). Between the rooms: a hollow `panelled`
door (shut), a solid `plank` one (ajar) and a steel `peephole` one (open). Tap E beside a door to open or shut it (DR6), hold E and
scroll to open it by steps (DR7), kick it (V) from the push side to burst its latch (DR10; hollow gives to the second kick, steel to
none), shoot or kick a door down (DR9, DR11; the pistol stops in steel, the rifle does not) and shoot out the glass door's panes
(DR9).
