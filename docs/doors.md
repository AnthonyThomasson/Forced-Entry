# Doors

How the houses' doorways and the doors in them behave: issue #21 "Add doors". A doorway is the gap in a wall between two
rooms (or between a room and the street); a door is the hinged leaf that can stand in it. Rules DR1 to DR14; each is
enforced by the tests named under it (`tools/run_tests.sh <id>`), following the convention of `docs/tactical-entry.md`. The
research behind the numbers is `docs/research/doors-in-room-entry.md` (scale: 1 m is about 58 px, a character's body radius
14 px). The tactical use of doors by the AI (entry on a shut door, cracking it, breaching, defenders shutting doors) is the
follow-up ticket #159 and is not in this spec.

Rules marked "(later stage)" are the spec of work still to come: their text is the brief's, their tests are written with
the stage that builds them, and each section grows from one line to its full rule then.

## DR1. Doorway size

Every floorplan's doorway is 52 px wide (about 0.9 m) inside the house and 60 px (about 1 m) for the front and the `exit`
doorways, about the width of a door beside characters 28 px across. The width is the gap
`WorldGen.get_openings` reports (`width`) and the one `WallFactory` cuts into the walls, in both mirror states of a plan.
Every floorplan still passes `LayoutRules` and the furnisher (no "no room for required zone"), and every plan still bakes and
connects over its seeds.

Tests: `worldgen/doorway_widths` (every floorplan, both mirror states: 52 px inside, 60 px at the front and exits, read through
`get_openings`; the widths are the brief's numbers, kept in the test), `worldgen/house_doorways_connected`,
`worldgen/layout_rules`, `worldgen/house_rooms_furnished`.

## DR2. Which doorways get a door (later stage)

The front and exit doorways always get a door; an interior doorway's chance comes from its more private room's type (bathroom,
netrunner den: always; bedroom, office, ripperdoc: mostly; kitchen, living spaces, studio: rarely; between two hallways:
never). A house definition may force or forbid a door on one opening and name its door sets. The roll is seeded per door from
the run seed in a stream of its own, so a seed's furniture layout never moves.

## DR3. Swing and hinge (later stage)

A door opens one way only. An interior door swings into its more private room (a tie: seeded), an exterior door into the house.
Its hinge sits on the jamb nearer that room's corner (a tie: seeded), so the fully open leaf (90°) lies along the wall. The
swing arc is kept free of furniture, clutter and the neon tube as the doorway clearance is. A mirrored plan mirrors its hinges.

## DR4. State at the start (later stage)

Front and exit doors start shut. An interior door is seeded per door: shut, ajar (15 to 35°) or open, by weights
(0.6 / 0.15 / 0.25).

## DR5. What a door blocks (later stage)

A standing door (shut, ajar or open) is a solid leaf: it stops bodies like a wall, is struck by rounds at every height and lets
them through by its material's penetration, blocks the AI's sight and casts a shadow, except the glass-panel door, which sight
and light pass through. It is in neither nav bake: paths go through doorways as before.

## DR6. Use (E) (later stage)

The `use_vehicle` action becomes `use` (default E, rebindable; a saved `use_vehicle` binding carries over). In a vehicle, Use
gets out. Otherwise it acts on whichever is nearest in reach ahead: a standing door or a vehicle door. Tap: an open door
swings shut, a shut or ajar one swings fully open, in about 0.4 s.

## DR7. Gradual opening (later stage)

While Use is held, each wheel notch turns the door by 10°, wheel up opening and down closing, between shut and fully open, and
it stays there; the wheel does not zoom the camera meanwhile, and releasing Use after scrolling does not toggle.

## DR8. A swing meets something (later stage)

A swinging door nudges any character in its arc out of the way (the opener too); it stops short at walls, furniture and a body
that cannot move further, and stays there.

## DR9. Damage (later stage)

Each door has its material's HP. Rounds, punches, kicks and blasts count against it, each by its material's factor for that
kind of hit; dents and holes show. A glass-panel door's first round shatters its panes; the frame stays.

## DR10. Burst open (later stage)

Kicks and blasts on a shut or ajar door from the side it swings away from wear down its latch; when the latch gives, the door
swings fully open at once. A character walking into it never counts. From the other side a kick or blast only damages the door.

## DR11. Knocked down (later stage)

At 0 HP the leaf comes off its hinges and falls flat into the room the last blow pushed it toward: walk-over, no cover, blocking
no shot, sight or light, and no longer usable. The doorway is clear.

## DR12. Sound (later stage)

Synthesized per material: the swing (a creak), the latch as it shuts, a burst's bang, the splinter and thud of a fall, a steel
door's clang, glass shattering; posted as `&"door"` events and played by `Sound`.

## DR13. Materials and styles (later stage)

Hollow-core wood (flush, panelled), solid wood (panelled, plank), steel (riveted, peephole), glass-panel (wood frame with
panes), each drawn in the run-down look, each with its HP, penetration and latch (an interior door is concealment, not cover;
steel stops a pistol, not a rifle).

## DR14. The AI opens doors in its way (later stage)

An NPC whose walk leads through a door not open wide enough to pass stops beside it on its latch side, faces it, uses it until
it is fully open, and walks on, leaving it open. A door that cannot open wide enough makes the walk a blocked one (the
existing re-decide). A knocked-down door is no obstacle. A shut door blocks sight, so the room behind it stays unsearched until
opened.
