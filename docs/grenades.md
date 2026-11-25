# Grenades

Two throwable grenades, for the player and for NPCs: a **stun grenade** (flash and bang: blinds, deafens, disorients) and a
**frag grenade** (a blast and real fragments). Behaviours G1 to G19 are the spec; each has a test, named under it, following the
convention of `docs/tactical-entry.md` and `docs/flanking-behavior.md`. The tests are in `tests/<domain>/` and
`tests/ai/grenade/` (`tools/run_tests.sh grenade`; the scenario tests replay their recorded Von answers; `--record-von` refreshes them),
and read the game only through the interfaces named in the rules, via `tests/_ai/grenade_probe.gd`.

This file was written with the tests, before the feature (issue #35, tests first), and amended as the build and its tests taught what the
rules needed (the amendments to G7, G11, G16, G17, G18 are marked in them). Issue #56 amended G13, G14 and G15 (the stunned look,
firing one-handed, the blind-fire roll, the stun's flash as a light; marked in them) and added the Performance section below, to
which issue #78 added its windowed numbers.

## The real-world weapons being simulated

**Frag (the US M67).** A 400 g steel sphere with about 6.5 oz of high explosive, thrown by hand. Its fuze burns 4 to 5 seconds after the
spoon (the lever) is released. The killing radius is about 5 m and the casualty radius about 15 m; fragments are thrown further still.
The thrower is expected to take cover. (GlobalSecurity, Wikipedia: Sources.)

**Stun (the US M84).** A cylinder that makes a flash of 6 to 8 million candela and a bang of 170 to 180 dB, within about 1.5 m. Its
fuze delay is 1 to 2.3 s. The flash blinds (flash blindness) and the bang deafens, gives tinnitus and upsets the inner ear, so a person
is disoriented, confused and loses coordination and balance, for seconds. Both are meant to be temporary. Police use it to
surprise and briefly incapacitate the people in a room so that an entry team can go in with less risk, and the team goes in the moment
it goes off (Wikipedia M84; the 1983 NCJRS abstract; patent US10215544's background: "an infiltration team storms into the room").
The patent's own subject, a device that sets off several charges in sequence, is not modelled.

**Clearing a room.** Doctrine for a room that may hold a threat puts a grenade into it before anyone goes in: a frag when the room is
to be cleared of everyone, a stun when the people in it are to be taken, and the entrants stay out of the doorway's line of sight
meanwhile (the stack, `docs/tactical-entry.md`). A thrower must have a clear path to where it throws, and everyone near a frag is in
its danger zone, the thrower and its own side too.

**What is not sourced.** Almost every number below is this game's, tuned for a top-down demo with 50 HP characters; the real figures
above only set the order of magnitude (a frag that kills close and wounds at a distance; a stun with a fuse about half a frag's,
whose effect lasts seconds). The list of the game's own rules is at the end.

## Behaviours

All distances are px (the game is about 64 px to the metre, so 550 px is about 8.5 m); times are seconds.

### Carrying and throwing

**G1. Slots.** The stun grenade is slot **7**, the frag grenade slot **8**. Each is a *count* carried (`Item.uses_left()`), spent one per
throw. When the last one is thrown the slot is empty and the character is holding its gun again (the lowest slot that takes ammo, as
`inventory.gun_slot()` says), else its fists. Selecting a slot it does not carry does nothing. A grenade is not a gun: while one is held
`inventory.gun_slot()` is still the gun, `ammo.rounds()` reads no ammo (-1), and `ammo.reload()` does nothing. `ItemRegistry.create(7, n)` and `create(8, n)`
make the items with `n` grenades; any other item answers `uses_left() == -1` (unlimited) and `is_throwable() == false`.
`Character.inventory.item_count(slot)` reads the count carried in a slot (0 when none). `Character.inventory.throw_stats(slot)` reads what a grenade carried in
a slot tells its holder about itself, `{ kind, max_range, danger_radius, fuse, flash_cover_reach, max_blind }` (`GrenadeItem.throw_stats()`, the one dictionary
`GrenadeConfig.stats_of` makes from the kind's row; `ThrownGrenade.throw_stats()` answers the same for a live one; `{}` for any other item or an empty
slot, and `flash_cover_reach` is INF for a frag, whose blast furniture shields from at any distance). These are the numbers the AI throws by (G17): it
keeps no copy of them.
Tests: `items/grenade_last_one_empties_slot`, `items/loadout_grenade_counts` (the registry), `items/grenade_throw_stats`, `items/grenade_throw_stats_blind`.

**G2. Throw.** With a grenade held, left-click (`weapon.shoot()`) starts a throw: a short wind-up (`windup` **0.3 s**, the hand drawn back in the
new `throw` stance: `hand_stance(0) == &"throw"` during it and not after) and then the grenade leaves the weapon hand, flying toward the
character's `movement.aim_point` and landing there, within about 40 px, but no further than `max_range` **550 px** (about 8.5 m, both kinds, the human's
throws too; issue #51 R14: in real matches the defenders an invader could not grenade were mostly 450 to 700 px off across a doorway): aimed past that,
it first touches down at the cap and may roll on a little (up to 100 px). Aimed just behind low cover (a sofa between where a lob would
touch down and the aim), it is lobbed over the cover instead of skidding into it, and comes to rest on the far side, rolling on a little
past the aim the same way (the planner, G3). The fuse starts on release; there is no cooking (holding it
with the pin pulled). The grenade passes its own thrower as it leaves the hand (G3). A throw cannot start while another is under way, while running, reloading or busy, and a character that dies
during the wind-up throws nothing. The throw posts `&"throw"` `{ position, kind, attacker }` (`kind` is `&"stun"` or `&"frag"`). The
spoon pops off as a tiny prop.
Tests: `items/grenade_throw_lands_at_aim` (lands near the aim, count 2 to 1, the event, the stance, the 0.3 s wind-up),
`items/grenade_throw_range_capped`, `items/grenade_none_dropped_on_death` (dying mid-wind-up), `items/grenade_lobbed_over_cover` (aimed
25 px behind a sofa: it flies over it, first touches down beyond it and rests behind it), `items/grenade_passes_its_thrower` (let go just outside a standing thrower's body on a path grazing it: it
flies on past and rests near its aim).

**G3. Flight.** *(Real 3D since issue #194, job 9: the grenade flies in the twin space (`TwinSpace`, `docs/adr/0014-twin-staging-and-plan-space.md`), where every wall, piece of
furniture, door, vehicle and body stands at its real height; there is no pseudo-height and no `coverage` test.)* A thrown grenade is a small sphere
(`GrenadeConfig.radius` **3 px**) that leaves the hand at the thrower's **release height** (`BodyHeights.release`: standing 1.7 m, about 72 px; crouched
1.3 m, about 55 px, by the posture of its holder) under gravity (`GrenadeConfig.gravity` **680 px/s²**), and is swept each physics frame through the twin space (`SmallFlight`, the one stepper
of `ThrownGrenade` and `DroppedItem`). It strikes what it meets at the height it meets it:
- **Furniture** lower than the arc is passed over and one it comes down on is **landed on** (the grenade bounces on a desk top, rolls on it and
  can come to rest there, 31 px up); a piece taller than the arc (a wardrobe's 78 px under a roof's 90 px peak is a narrow window, a bookshelf's 77 the
  same, anything a wall's 96) is struck and bounced off.
- **A doorway** is open only as high as its door (84 px); the wall's **lintel** over it, from 84 to 96 px, is struck like a wall. A throw through a
  doorway is the lowest arc that reaches, which passes under it; a lob aimed higher (a peak over about 81 px where it crosses the doorway)
  strikes the lintel and comes back.
- **A roof is the only ceiling** *(D11a)*. A room of a house or a tower (a `Floor` with `roofed`) has a roof slab in the twin space at the walls' height (96 px) that only a lob meets (not a ray of the player's aim or a sight); a
  grenade that flies up into it strikes it (a flight is held under the roof's underside over its hand, the middle of its throw or its aim), and the planner never plans a peak above it (the
  roof's underside less the grenade's size and `GrenadeArc.ROOF_SLACK` **3 px**, over the hand, the middle or the aim). Where no roof stands (the street, open ground, a roofless shell, an arena) nothing stops
  a grenade from above and a lob peaks up to `GrenadeConfig.max_apex` **150 px** (about 3.5 m), steep enough to drop behind low cover.
- **Walls, vehicles, doors and bodies** (a character's twin, the thrower's own for its first `GrenadeArc.THROWER_CLEAR` **40 px** of flight, since the
  hand is held beside the body) bounce it like any surface.
A strike that comes in faster than `GrenadeConfig.min_hop_speed` **40 px/s** (and rebounds more than the next frame's gravity takes back) **bounces**:
the velocity is reflected and scaled by the row's `restitution` **0.35** (the floor's and a wall's alike); a slower one **settles**, and on a surface that
faces up the grenade **rolls**, the surface slowing it by the row's `friction` until it is under 4 px/s and **at rest**. Every bounce off the floor or
a piece's top, and every strike of a wall faster than 30 px/s, posts `&"grenade"` `{ position, kind, stage }` with `stage = &"bounce"`, and the resting
grenade posts `stage = &"rest"` once; the Audio domain voices a bounce (G14's sounds). Nobody picks it up or throws it back, and a grenade that comes
back off a wall strikes its thrower like anyone. A grenade in flight or on the floor, until it goes off, is a node in the group `live_grenades` with
`kind`, `fuse_left()`, `altitude()` (its underside's height over the floor, or over the piece it lies on), `throw_stats()` (below; its `danger_radius`
is a frag's 250 px blast radius, a stun's 400 px flash radius) and `thrower`.

**The arc planner** (`GrenadeArc`, one for the human's throw and the AI's judgment of one; interface 6). It chooses how the grenade leaves the
hand: from the release point at the release height to the aim, **the lowest arc that clears what is in the way and lands near the aim**. The arcs are
enumerated by peak, from the release height up to the top a roof or the open sky allows (above) in `APEX_STEP` **6 px** steps (18 px above the walls' height); an arc's flight time follows from its peak alone, and
the arm gives it at most `throw_speed` **740 px/s** across the floor, so the lowest arc that reaches a near aim is a flat toss and the one that
reaches a far aim a high lob; a throw is never farther than `max_range` **550 px**. Where an arc first touches down is solved so that, with the
bounces (restitution, `min_hop_speed`) and the skid (`friction`) over a flat floor, the grenade rests at the aim. Each arc is swept in five casts of a
cylinder `margin` wider than the grenade through the twin space (the walls, the pieces, the vehicles; characters are looked past) and is kept when
nothing stops it; a strike on the way down within 24 px of the aim is a landing on top of something (on a surface that faces up, a body's, or over a piece's edge; the face of a wall rising beside the aim is a strike). When more than one arc reaches, the lowest
wins; a throw that is made also **flies** each clear arc over the room (the thrower's own flight to rest) and keeps the first that rests within 24 px
of the aim: a grenade that would touch down short of a sofa and skid into it is lobbed farther (12 px further out at a time, at most 40 px past the aim),
over the sofa, to touch down past it and roll on; a rest short of the aim is counted twice (the grenade the cover stopped is the worse miss than
one that rolled on). One that no arc brings near is thrown on the arc that rests nearest, and one with **no clear arc at all** on the highest, and
strikes what is in the way (`ok` is false). The AI asks the same question without flying the skid (`GrenadeArc.clear`, G17), so a throw it judges
clear is one the flight then makes. **What a plan costs** (#194, perf-arc): a plan is mostly casts, and a failing one (nearly every plan the AI's throw-spot search asks: 95 % in the vision guard's window)
sweeps the same lob more than once, so a plan works each arc out once (its flight time, the heights its five chords end at, its reach, what it rests as) and sweeps each lob (an arc at a reach) once:
the flat arc `_flattest` tries, the arcs `_faced` compares and the first step of the search are the same sweeps. `GrenadeArc.work` is the price the AI's search is charged by, in quarter-units (four per planner question, one per raw candidate tested; `ThrowSpots.work()` sums them) and it is **not** the
casts made: a sweep answered from what the plan already found still counts one, so a cheaper plan is no less work and the AI's budgets, block sizes and cadence stay what they were. The plan's answer,
its `top` and `roof` and its `work` are the planner's of before the cut for every input. Test: `items/grenade_arc_matches_reference` (four thousand throws generated in the perf guards' district, planned by
`GrenadeArc` and by `tests/_items/grenade_arc_reference.gd`, a frozen copy of the planner before the cut: every launch field, the course's top and roof and the work equal; also a course that has planned another question, which a plan must forget). It guards that cut only: a deliberate change to the planner's rules re-freezes the copy in the same commit, and the copy and the test are deleted by the ticket's final perf job once every guard passes). Real limits follow: under a roof a lob can come down only so steeply, so a target within about 50 px
behind a 31 px desk, or in the lee of a 78 px wardrobe far from the thrower, is out of a throw's reach indoors; in the open the same target is reached.
Tests: `items/grenade_bounces_off_wall`, `items/grenade_bounces_in_3d` (a wall struck in the air, the floor, rest on it), `items/grenade_lobs_over_furniture`
(a desk and a wardrobe: over them and landing at the aim), `items/grenade_lands_on_furniture` (aimed at a desk, it rests on top), `items/grenade_lobbed_over_cover`,
`items/grenade_release_height_follows_pose` (a ducked thrower's grenade leaves lower than a standing one's), `items/grenade_arc_wall_face_is_no_landing` (a strike on a wall's or a piece's side face near the aim is a strike, not a landing), `items/grenade_arc_spanning_piece_blocks_every_arc` (a tall piece across every arc blocks the throw; a low one is flown over), `worldgen/district_roof_only_over_rooms` (a roof is over every room of the towers, none over a shell or a road), `items/grenade_lob_roof_ceiling` (D11a: a steep drop behind a wardrobe is out of reach under a roof, made in the open), `objects/twin_roof` (a room has a roof at the walls' height, open ground none), `items/grenade_flies_under_the_lintel` (a throw through a doorway passes under the lintel), `items/grenade_high_lob_bounces_off_the_lintel` (a high lob into
the doorway comes back), `items/dropped_item_falls_in_3d` (a dropped item falls the same way), `ai/grenade/throw_planner_agrees_with_flight` (G17: what the NPC
judges clear is what flies), `objects/twin_doorway_lintel`.

**G4. Death.** A dead character's unthrown grenades vanish with it: nothing is dropped, and nothing is ever live in a dead hand.
Test: `items/grenade_none_dropped_on_death`.

**G5. Loadout.** The setup window carries a **Stun** and a **Frag** count per side, 0 to 3 each; the side dict has the integer keys
`stuns` and `frags`. The defaults are invaders 1 + 1 and defenders 0 + 0. They are saved with the rest of the setup (a save from before the grenades, which names no counts, keeps these defaults). In code,
`LoadoutConfig.normalize` keeps `stuns` / `frags` in 0..3, `LoadoutConfig.apply` gives the character that many in slots 7 and 8, and
`LoadoutConfig.grenade_options()` lists the two rows for the window (`[{ id: &"stun", label, slot: 7, max: 3 }, { id: &"frag", ..., slot: 8, ... }]`;
`options()` stays Random plus one entry per gun).
Tests: `items/loadout_grenade_counts`, `general/saved_setup_grenade_counts`.

### Frag grenade

**G6. Fuse.** **3.0 s** from release.
Test: `items/grenade_throw_lands_at_aim`.

**G7. Blast.** *(Amended after the tests phase: "frag out, take cover".)* When it goes off every hittable body with a clear line from the blast
point within `blast_radius` **250 px** takes blast damage: the full `blast_damage` **60** (a character has 50 HP) out to `kill_radius` **120 px**,
falling linearly to 0 at 250 px (`60 * (250 - d) / 130` between), measured from the blast point to the body's centre. Walls block the line.
**Cover** *(real 3D since issue #194, D10: there is no abstract coverage number)*: the line from the burst to a body is a 3D ray in the twin space
(`TwinSpace`, `PlanSpace.lift`), cast from the burst point (the grenade's centre, `Explosion.BURST_CENTRE` **3.5 px** above where it lies: the floor, or a desk's top
when it rests on one, `ThrownGrenade.altitude()`) to each point of the body at its posture's real heights (`BodyHeights.sight_points`: head, chest, hips). A wall, a
door, a vehicle or a piece of furniture on it stops it; the body is shielded only when **every** point is cut off. So the shadow of a low piece is real: a couch's
38 px back shields a ducked body (head 36 px) behind it, and a standing one far enough behind it (the line from a burst on the floor rises too slowly to clear 38 px
before it reaches the body), while a standing body right behind it, or a burst that is high (on a desk, 31 px up), is hit over the back. A hostile that hides
behind a piece from a thrower's bullet is therefore also in its shadow: cover that hides a ducked hostile shields the thrower from a burst there. The blast reaches
characters and objects alike through `take_hit` (so characters bleed, a character's torso armour cutting the damage by its `blast` share: `docs/outfits.md` O9; objects deform and shed debris), and each blast hit posts `&"hit"` with
`outcome = &"blast"`. Pushables in range are shoved away from the blast by `blast_impulse`, falling off with distance: furniture, living
characters (as knockback) and the ragdolls of the dead. The burst posts `&"explosion"` `{ position, height, kind, attacker, radius }`.
Tests: `projectile/frag_blast_by_distance` (80 px dead, about 200 px hurt by the fall-off, 400 px no blast, an object struck),
`projectile/frag_blast_blocked_by_wall`, `projectile/frag_blast_low_cover_by_posture` (behind couches: crouched, no blast; standing close behind them, the blast),
`projectile/frag_blast_shadow_behind_low_cover` (a standing body far behind a couch is in its shadow),
`physics/frag_blast_pushes`. *(Amended by issue #205.)* The blast strikes the bodies it reaches **nearest first** (a tie: the leftmost, then the topmost),
not in the order the engine's shape query lists them (which follows what the process allocated earlier): every blast hit draws from the world's random
stream, so the same fight must draw them for the same body each run; test `projectile/frag_blast_strikes_nearest_first` (five chairs round a frag, created in no
order of distance, are struck in the order of their distance).

**G8. Fragments.** `fragments` **40** real projectiles leave the burst point as **3D rays over the upper hemisphere** (`Explosion._fragments`: azimuth evenly round the circle,
jittered; elevation `sin = q^fragment_flatness` for a draw `q` spread evenly over the fragments, `fragment_flatness` **6**: about two thirds within 6 degrees of level, an eighth over 25,
as a shell's do; at the burst's real altitude), through `ProjectileSpawner`, with low power (`penetration` 0.4, `fragment_damage` **12**, fast) and a short reach
(`fragment_range` **500 px**: a projectile can be given a maximum range, past which it is spent), and a fragment that climbs past 100 px (`Explosion.FRAGMENT_CEILING`: over every wall, piece and body, nothing taller than the walls is left to strike; a roof is struck by no fragment, none of the twin's line layers holds it) is spent there, so a steep one does not fly its whole reach. So cover, penetration, ricochet, blood, debris and impact sounds all work as for
bullets: a ray is stopped by what it meets at that height (a wall, a lintel, a piece's real parts, a door, a vehicle), a ducked body behind a sofa is shielded and a standing one is hit over it,
a grenade resting on a desk or a van's roof bursts at that height and its fragments clear the desk's own top (if the piece under a resting grenade is pushed or blasted away it falls and bursts where it lies, `SmallFlight.unsupported`) (a character's armour and hit zones too: `docs/outfits.md` O9); each hit posts `&"hit"` with the thrower as
`attacker`. **Tuned to the old figure, in HP:** an exposed standing body in the open loses from the fragments, after each hit's zone share (feet and legs 0.6, torso 1, head 2.0,
`CharacterHitConfig.zone_damage`), what it lost when they flew level (12 each) at a height drawn from the floor to the ceiling of the old 0 to 100 scale, band by band (the HP
lost per burst and dummy 14.3 at 70 px, 5.3 at 140 px, 4.0 at 260 px, 2.2 at 420 px, within 15%), by the damage and the flatness. **And spread up the body:** about 9% of the hits on a standing body land on the torso or the head (3 to 5% at flatness 12, which
put nearly all on the feet and legs and left a vest nothing to stop; the old level draw gave 49%). The two pull against each other: a hit's chance falls with distance as
`distance^-(1/flatness)`, so a flatter fan keeps the old distance law and a steeper one spreads the hits and thins them out faster. 6 is the best of both: within 15% per band (in HP) and a
vest has fragments to stop (`projectile/frag_fragments_stopped_by_vest`, O9).
Tests: `projectile/frag_fragments_hit`, `projectile/frag_fragments_exposed_by_distance` (the figure per distance band and the share of hits on the torso and head), `projectile/frag_fragments_stopped_by_vest`, `projectile/frag_fragments_shielded_by_low_cover` (a ducked hostile behind a sofa survives
a frag that kills a standing one beside it), `projectile/frag_burst_on_a_desk_at_desk_height`, `projectile/frag_fragments_spent_above_the_walls`, `projectile/frag_burst_on_a_van_roof_at_roof_height`, `projectile/frag_falls_when_its_support_is_pushed_away`.

**G9. Friendly fire.** Grenades hurt and stun everyone: the thrower and its allies are not spared.
Test: `projectile/grenade_friendly_fire`.

### Stun grenade

**G10. Fuse.** **1.5 s** from release.
Test: `character/stun_flash_by_sight`.

**G11. Flash (by sight).** *(Amended after the AI phase: furniture only shields from the flash at the face.)* A character with a clear line of sight to the burst (the real 3D line from the burst to its eye; walls block it; a piece of
furniture on the line blocks it only when the character is within `flash_cover_reach` **30 px** of the face of it nearest the character, hunched right against it: the light comes round and over a
piece that is not at its face, so a crouched character 120 px behind a couch is flashed and one against it is not) within `flash_radius`
**400 px** is flash-blinded for up to `max_blind` **5 s**, scaled by distance (full inside 100 px, falling linearly to nothing at
400 px) and by how much it faces the burst (the dot of its facing with the direction to the burst: facing it, x1; side-on, x0.6; back to
it, x0.25; linear between those). So `blind = 5 * clamp((400 - d) / 300, 0, 1) * facing_factor`. No line of sight, no flash. The
burst posts `&"explosion"` and each character stunned posts `&"stun"` `{ character, position, blind, deaf }` (G13; `position` is the character's).
Tests: `character/stun_flash_by_sight`, `character/stun_flash_cover_reach` (a crouched victim against a couch is not flashed; one 120 px behind a couch, the couch still on the line, is).

**G12. Bang (by range).** Every character within `bang_radius` **350 px** is deafened and disoriented for up to `max_deaf` **6 s**,
scaled by distance (`deaf = 6 * (1 - d / 350)`); through a wall the effect is x0.4, but furniture muffles nothing: a character out of the flash
behind a couch or a wardrobe is deafened for the whole of its distance. Within `point_blank` **30 px** it also takes
`point_blank_damage` **5**. A stun does no other damage.
Tests: `character/stun_bang_by_range`, `stun_bang_through_furniture`.

**G13. Being stunned** (the character, for the player and an NPC alike). While disoriented a character moves at most `CharacterStunConfig.speed` **x0.45**
of its speed, with a slow drift, cannot run, and its aim sways: a wandering offset of up to `CharacterStunConfig.sway` **25 degrees**, applied to
where its shots go. The effect tails off over the last `recover_tail` **1.5 s** (the level falls linearly from 1 to 0 over that time),
and then it is as before. `Character.take_stun(blind, deaf)` applies it (and posts `&"stun"`), its `stun`'s `is_blind()`, `is_deaf()` and
`level()` (0..1) read it, `stun.view()` gives `{ blind, blind_total, deaf, level }` (seconds left blind and deaf, the blind
seconds at the burst, the level) to the UI, and a new stun takes the longer of the old and new timers, blind and deaf each. The four numbers live in
`CharacterStunConfig` (they tune the body, not the item). A character also tells a controller what it needs to judge a place in time: `movement.run_speed()` (px/s standing and running, slower while stunned or weighed down by the outfit) and
`movement.walk_speed()` (px/s walking, slowed the same way: what the AI counts on once its stamina is low), so the AI keeps no copy of any.
*(Amended by issue #56: the stunned look, and firing one-handed.)* A stunned character also looks it, every character alike (the player,
an NPC, a test puppet); all of it is drawn only, eases in and out with the level (`CharacterStunConfig.look_ease` **6/s**: no hand or head jumps in a
frame), and while it rides a vehicle the ride's pose wins (none of it shows until it is out):
- **Hand over the eyes.** While blind, the free hand (the one the held item's `weapon_hand()` does not name) goes to the `eyes` stance, the
  palm over the face (drawn over the head), and back as sight returns. A reload, a punch or a throw's wind-up takes it away for as long
  as it needs that hand. A bang that only deafens leaves both hands where they were.
- **Hunch.** The spine and the neck pitch forward by `CharacterStunConfig.hunch_pitch` **15 degrees** x the level, on top of a crouch's own pitch; a
  deaf-only stun hunches too. The arms keep their reach past the leaning chest, as in a crouch.
- **Stagger.** Walking, its strides are shorter (`CharacterStunConfig.stagger_stride` **x0.55**) and uneven (a limp, `CharacterStunConfig.stagger_limp` **0.4**, and a
  wandering pace, `CharacterStunConfig.stagger_wander` **0.3**), its hips sway (`CharacterStunConfig.stagger_sway` **4 px**) over the planted foot and its head lolls
  (`CharacterStunConfig.stagger_bob` **3 px**), all by the level. The pace stays `CharacterStunConfig.speed` and the drift stays.
- **One-handed.** While the free hand covers the eyes, a gun is held in the weapon hand alone, in the `one_hand` stance (the arm out, the
  gun lower than a two-handed grip, wandering `waver` **3 px**), and `Character.weapon.one_handed()` is true (false for anything but a gun, and
  while the free hand is away). A round fired so leaves within the gun's `spread_deg` plus its `GunConfig` row's `one_hand_spread_deg`
  (pistol **3**, SMG **6**, rifle **8 degrees**), the player's as an NPC's, and a long gun kicks `one_hand_recoil` **x1.75** harder.
The look's numbers live in `CharacterStunConfig` with the other four, the spread in `GunConfig`.
Tests: `character/stunned_slow_and_sway`, `character/posture_and_run_reads`, `ai/grenade/throw_timing_counts_slowed_walk`,
`character/stunned_hand_over_eyes`, `character/stunned_hunch_and_stagger`, `items/one_handed_fire`.

**G14. The stunned player.** The player's screen goes white at the burst and fades back over the blind time through a frozen afterimage
of the moment of the flash (`StunScreen`, `watch(character)`, `drawn()` -> `{ white, afterimage, remaining }`); a bang that only deafens
whitens nothing, and nothing happens for someone else's flash. Game audio is muffled (a low-pass) with a synthesized tinnitus whine over
the deaf time, but only for the character `Sound.focus` names (Main sets the human): a `&"sound"` of kind `&"tinnitus"` (profile
`tinnitus/...`) once per deafening of the focus, and `Sound.muffled()` true while it is deaf. The grenades sound in the world: the throw
(kind `throw`, profile `throw/...`), each bounce (kind `grenade`, profile `grenade/.../<floor under it>`), the frag (kind `explosion`,
profile `explosion/frag`: big, low, a long tail) and the stun's bang (`explosion/stun`: sharp, very loud, short). The camera shakes
on `&"explosion"` by distance and kind (`Camera2D.offset`: a frag beside it hardest, farther less, none far off, a stun less than a
frag), and the burst has its look: a flash, a fireball puff and smoke, with a scorch left under a frag, and only thin smoke for a stun
(`Physics.spawn_explosion`, off with `PhysicsExplosionConfig.fx_enabled`). *(Amended by issue #56.)* A stun's white flash is a light, not
a drawn disc: the lighting's stun flash (`docs/lighting.md` L9), far brighter than a frag's, shadowed by the walls and the furniture, held
at full brightness for an instant and faded over 0.7 s. The player's own whiteout above is unchanged.
Tests: `ui/stun_screen_whiteout`, `audio/grenade_sounds`, `general/camera_shakes_on_explosion`, `physics/explosion_fx`,
`lighting/light_3d_stun_flash`.

### AI

**G15. A stunned NPC.** While blind it sees nothing new (no sightings; contacts age as usual, so what it holds of a hostile stays at the
spot it last saw it) and starts no new decision; it stumbles, slowed and drifting, and may **fire blindly** at the last-known position
of a hostile it knew (with the sway: no shot strays more than 25 degrees off that spot, plus the one-handed spread below). *(Amended by
issue #56.)* It looks stunned as any character does (G13: a hand over its eyes, hunched, staggering), so the gun it fires blindly is held
one-handed: each round spreads wider by the gun's `one_hand_spread_deg` (a pistol's 3 degrees: 28 in all), on top of the sway.
Whether it fires blind is **one roll** as it goes blind (from not blind) against its `tuning.grenades.blind_fire_chance` (a tunable of
the NPC's, **0.5**): a hit fires blindly as above; a miss **holds its fire** (no round, no click, an automatic's burst cut short)
until it can see, still turned to that spot. A further stun while it is still blind does not roll again. The roll is drawn from the
NPC's own random number generator, seeded once from its character's name and spawn spot, each blinding taking the next draw, so a
seeded match or a test that places the NPC the same way rolls the same. While deaf it hears no gunfire, no hits
elsewhere, no footsteps (`docs/hearing.md` H1) and no radio callouts. When the blindness lifts it re-decides from what it sees, still disoriented for the tail.
Tests: `ai/grenade/stunned_defender_blind` (chance 1), `ai/grenade/stunned_defender_holds_fire` (chance 0), `ai/grenade/deafened_npc_ignores_gunfire`.

**G16. React to a live grenade** *(amended after the tests phase: "frag out, take cover")* (a reflex outside Von, like auto-reload; it takes priority
over every primitive, committed or not, but for the NPC's own grenade in its wind-up: that one cannot be called back and leaves the hand at most a
wind-up (0.3 s) later toward its spot, so the NPC throws it first and runs the tick it has let go; turning away meanwhile would throw it the wrong way). An NPC that *sees* a live grenade (in its view cone with a clear line) or *hears* one land within
`hear_grenade` **300 px**, and is inside its danger zone, radios a `grenade` callout and runs to the nearest **safe spot** it can reach before the
fuse is out. A spot is safe in either of two ways, and the NPC takes whichever is nearer: **out of line** (out of the grenade's line of sight, round
a wall corner or a doorway, or outside its danger zone, defined below: beyond the radius and the margin), or **behind cover** that shields it from the blast (G7: the real 3D line from the burst, at the heights of the posture it would hold): it goes behind that furniture, crouching when
standing there would leave it hit over the back (a standing body far enough behind a low piece is already in its shadow and need not), and a character behind cover is as clear as one out of line. It then holds there, facing away or crouched, until the detonation, and
re-decides. *(Amended by issue #158: safe first, then the fight.)* Holding its spot, a frag's or a stun's, it still fights: a threat the watch
stage picks (`docs/gaze-and-fire.md`: the hostile it fights or the nearest it sees, else one seen a moment ago with a clear line to where it
was) takes its eyes and gun from its back to the grenade, and it fires at will as under any primitive, crouched behind cover when the spot
is cover. So does an NPC a frag catches with no spot it can reach in time (crouched where it stands: its facing is no help against the
blast). On the run to the spot it does not fight (it runs, and a running character neither shoots nor reloads), and one a stun catches
with no spot keeps its back to the bang (the fight comes after it). With no threat it faces away as before. A spot it can reach is one its route gets to: one on
floor it cannot walk to (past a wall with no door) is no spot, however near. The danger zone of a frag is a clear line to the landing within `blast_radius` plus `evade_margin` **120 px**, so **370 px**; of a stun,
a clear line within `flash_radius`, **400 px**; a stun's cover spot counts as clear only under G11's rule (furniture within `flash_cover_reach` of the body; the planner's candidates include a spot
right against the far face of whatever stands near the burst). If it cannot get clear of a stun in time, it turns its back to it (so the flash blinds it for the
back-turned share only). Allies within `callout_range` who are in that zone react the same way to the call, even when they neither saw nor heard the
grenade. A grenade it threw itself it knows about: in flight, at the spot it aimed at (no further than a throw reaches), not at the hand it just left,
and once it has come down wherever it lies. The spot is chosen again as the grenade moves: after 48 px, and after any move at all that brings
the spot into the grenade's line (a grenade that rolls on a few px by a doorway can put a spot round the jamb in view of it). *(Amended by issue #192: a cap on the plans; by #194: a pool of work, not a count.)* The escape searches of every NPC share a pool of **80 units a physics frame** (about 2 ms: a new navmesh snap and a new verdict cost 1 each, a route 5, the candidates round a burst 16, once), so when many are caught at once an NPC may start its run some frames after it could: a search is served the frame after it begins, in this order: an **urgent** search first (one begun 12 frames ago or more, or whose grenade goes off within the margin and 12 frames: the one begun first), then a plan an NPC has none of yet before a replan, the grenade that goes off first, the NPC nearest the burst (most in danger), the search begun first; one that cannot finish this frame continues the next from where it stopped, and its plan is made from where the NPC stood, with the fuse left, when it began. **The wait is bounded**: a search lands within 12 frames plus the work of the searches begun before it or on its frame, over the pool, however many more begin after it; and while any search is urgent a frame holds 80 more units (twice the pool, about 4 ms), so a wave too big for the pool is served at twice its rate once it has waited 12 frames (a wave of N searches of about 110 units lands within about 0.7 frames each after that, N = 80 before a stun's 66 frames of fuse less the margin). Of the grenade tests the median wait is 3 frames, the p90 19 and the most 21 (the 34-NPC wave below, the replans among them); 34 NPCs (30 and four more) round one frag waited up to 15 frames and none was caught (at the pool alone the most was 19 and one was: a 300 px run planned to the margin's edge, begun 19 frames late, since a plan is for the fuse left when its search began). The NPC carries on as it was until it has a plan (a replan keeps the old plan meanwhile); a search its NPC has not asked after for 30 frames is dropped and begun again, and one whose NPC has died is dropped. A frame serves the pool and at most one more candidate (7 units); a new burst's candidates (16 units) are paid by the search that begins it. The NPC walks all
the way into its spot (6 px), since a spot is out of the line with only a little room to spare either side of it. The callout is `status = &"grenade"` with `point` (the landing) and `kind`;
`GoalController.debug_grenades()` reports
`{ known: [{ point, kind, fuse_left, radius, source: &"seen" | &"heard" | &"called" | &"own" }], escape: Vector2 (Vector2.INF when it is
not running to one), throw: {} }`.
Tests: `ai/grenade/evade_frag_seen`, `ai/grenade/evade_frag_ally_warned`, `ai/grenade/evade_stun_turns_away`,
`ai/grenade/evade_frag_takes_cover_behind_couch` (the amendment: a couch nearer than any way out of line, the defender goes behind it),
`ai/grenade/evade_fights_from_spot` and `ai/grenade/evade_stun_fights_from_spot` (scripted: clear of a frag, or of a stun, a defender holding
its spot shoots at an invader in view before the burst), `ai/grenade/evade_frag_cornered_fights` (scripted: a walking defender a frag catches
with no spot in time shoots at the thrower before the burst),
`ai/grenade/evade_replans_when_spot_in_line` (scripted: a frag by the living room's doorway rolls on under 48 px and puts the planned spot in its line; a new
spot out of the line is planned before the burst), `ai/grenade/evade_waits_for_own_windup` (scripted: a teammate's stun lands beside an invader winding up its
own throw: its stun still goes onto its spot, then it runs), `ai/grenade/escape_pool_spreads_plans` (thirty and four NPCs caught by one frag: no frame serves more than the pool, its urgent extra and a candidate, the nearest the burst plan first among those that knew it on one frame (the NPCs sense on a beat, so half of the thirty know the frag a frame after the other half), every plan within 16 frames and before the margin, all clear of the burst; the order rule on its keys), `ai/grenade/escape_pool_bounds_wait` (the wait's bound: 20 NPCs on two grenades, 34 round one, a stream the pool cannot keep up with; the urgent rule on its keys), `ai/grenade/escape_search_owner` (a stale search is begun again, a dead NPC's dropped), `ai/grenade/escape_spot_matches_plain` (the sliced search lands on the plain search's answer), `ai/grenade/evade_wave_spots_match_own_plan` (five defenders round a frag an ally throws
into the hall plan their escape together, at least three begin a search on one frame (a decision lands over a few frames since #194 perf-decide2, so a defender that fought the thrower first may look away or stand clear, and at least four plan at all): the work that depends on the burst alone is shared among them on that frame,
and every plan's spot is the one the NPC's own search, nothing shared, picks on that frame).
*Former gap (found by issue #205's recordings, `evade_wave_spots_match_own_plan`):* with every Von answer landing a fixed 12 frames after its ask, the wave's defender nearest the landing (`d2`, about 67 px from it, among the five the test stands round it) held no evade spot on any frame of the wave and was caught by the frag still evading, while the other four each held one. The test passes since #194's duck-rise changed the thrower's picks (advance / advance_close became fire_here): an incidental effect of the rise rule (`docs/cover-and-stance.md` P6), not a fix of the 12-frame-latency behaviour, so its `gap` tag is gone but the premise (the 12-frame hold starving the nearest defender of a plan) is no longer exercised. A follow-up ticket decides whether the AI or the premise was wrong.

**G17. The GRENADE tactic (combat).** *(Amended after the tests phase: "frag out, take cover"; amended by issue #51, R7 and R10: a defender
barricaded in a room, and the room the shots came from; R13 and R15: throw spots.)* A COMBAT tactic (decision-tree id `grenade`), offered when the NPC
carries a grenade and it can lob onto the bound hostile's last-known spot, within throw range (550 px) with a clear throw path (an arc of G3's planner
clears everything between: no wall, no lintel or tall piece the highest arc does not pass; low furniture is fine), from where it stands or from a **throw spot** a short walk away (below), and
- the spot is **hidden from its line of fire**: the NPC knows the hostile is there (seen, heard or told of, and last known at the spot) but has no
  line to it (the real 3D line of `docs/gaze-and-fire.md` W2, from a standing muzzle to the aimed part: stopped by a corner, a wall, a piece tall
  enough for a ducked body to hide behind, glass), so a hostile standing behind a table or a counter is seen over and shot, and one crouched
  behind a sofa that the NPC saw duck is not: "frag {target} behind their cover", or
- the spot is **in a room the NPC is outside of** (outdoors, or in another room), even with a line of fire: a defender barricaded in a room, holding
  its doorway or crouched behind cover inside, is grenaded, not only shot at (R7): "frag {target} in the kitchen". The state's exposure line says it
  ("h holds the kitchen, a room you are outside of. You can throw a frag grenade onto their spot.") and the tactic's desc reads "h holds a room you are
  outside of and you can throw a grenade onto their spot (...)"; in its own room, in the open, a hostile in its line of fire is shot (no GRENADE);
- or, with **no hostile known**, it is shot at by someone it cannot see **from a room it is outside of** (the line back from the shot, G18's
  `shot_from`, runs into that room): the unbound COMBAT level offers, beside RETREAT, a throw onto that line's stretch inside the room, the
  nearest its middle with a clear lob in range (from where it stands at any point of the stretch first, else from a throw spot, R15); LOCATE, the walk toward the shots, is not offered toward that room (`docs/tactical-entry.md` E9) ("stun grenade into the kitchen, where the shots came from"; the state: "The shots came from the
  kitchen, a room you are outside of. You can throw a stun grenade where the shots came from.") (R10). Whatever the room, LOCATE and a RETREAT spot
  are not offered when their walk would end where the NPC already stands or on a character it knows of (E9, issue #51 R12; tests
  `ai/combat/locate_never_where_it_stands`, `retreat_never_where_it_stands`, `retreat_out_of_sight_goes_farther`).
**The lob** is judged as the grenade flies: from where it leaves the thrower's hand (the `throw` stance's hand, `Character.inventory.throw_release_offset`: 6 px behind it and 15 px to its right as
it faces the spot, held off a wall the way the character's own hand is), at the release height of the thrower's posture (`BodyHeights.release`; crouched, a
lower hand), **some arc of the planner (G3, `GrenadeArc.clear`) clears everything in the twin space between** with 8 px to spare either side (`AgentThrow.LOB_MARGIN`:
the grenade's own width and the hand's sway): the walls, a doorway's lintel, the furniture at its real top, the vehicles, characters looked past
(`AgentThrow.can_lob`, `throw_clear`). The throw, the bang's throw (G18) and the re-check before the wind-up all use the one test, and it is the
planner the throw itself flies, so a throw judged clear is never one the flight then fails. A line from the thrower's centre that clears a jamb by a pixel is a grenade that strikes it, and a spot the thrower walks to (a throw spot, the bang's spot) is judged from
wherever the walk may end, with 6 px more to spare either side (`AgentThrow.throw_clear_on_arrival`, the band the 8 px margin widened by `ARRIVAL_SLACK`): a lob that clears only from the
spot itself is a jamb struck by a thrower that stops a few px off it. The question costs at most 64 swept arcs of five casts (the throw-spot scan asks it for
many spots, budgeted by `perf/grenade_match_stress`).
**A throw spot** *(issue #51 R13, R15)*: when the spot is out of range or has no clear lob from where the NPC stands, the throw is offered from a point on
the navmesh within the grenade's reach of the spot (its range less 15 px) from which the lob is clear, a walk of at most `throw_spot_walk` **250 px** along
a route that passes no known hostile (agent_tactics.gd `throw_spot`), never inside the room the hostile holds that the NPC is outside of (or the room the
shots came from). It is chosen as the fire spots are, and so that its walk needs no detour: one whose walk (measured as it would be walked, round the doorway
views when it would take that, `docs/tactical-entry.md` E18) crosses no doorway into a room not cleared and comes into no doorway view it cannot go
round first, then out of the line from the spot (low furniture between), then with cover close by against it (a doorway's jamb, a piece of
furniture), then the shortest walk (both ranks read the twin space: "out of the line" is a 3D ray at a walker's ankle height from the burst spot to the throw spot, stopped by any wall, door, piece, vehicle or character (`AgentTactics.blocked`), so low furniture hides it; "cover close by" is the 3D lines of a ducked body at the spot or a step from it (`AgentVision.hiding_piece`: head, chest and hips from the burst's standing eye height, `docs/cover-and-stance.md` A4); the safety judgements, the zone and `no_safe_spot`, read the burst's real 3D line of G7); candidates are rings round the NPC (48 to 240 px) and round the spot (0.95 and 0.8 of the
reach). The option's `params.from` is the throw spot (where it stands, for a throw in place) and `params.walk` says it walks there; the ally-in-blast and
self-safety tags are judged from there (an NPC that stands outside the zone but would throw from inside it with no way out is `no_safe_spot`). Its desc adds
" — from the hallway to the east, short route", and the group's summary says "within throwing range from a spot nearby" when every option needs the
walk. `debug_zones()` lists every throw weighed (dropped ones too) as zones of category `grenade` with `point` (the burst spot), `from` and `tags`.
Whether a legal throw exists at all (`grenade_ready`, the fact that gates the tactic and the unbound level's throw onto the shots' origin) is answered
by a search that stops at the first spot the NPC could throw from, and the answer is always the one the full search gives ("it found a spot"); the full
options, with their tags and wording, are built only when the decision's walk reads them. The decision job runs that search as its throw piece,
in steps of a fixed count of candidates (#195) and a work cap (`ThrowSpots.block_work` of `ThrowSpots.work()`, a count in quarter-units: four a planner question, one a raw candidate tested; a throw spot's rank and each of its routes are steps of their own), and its answer is the one-shot search's at every step size. Tests: `ai/grenade/grenade_ready_matches_full_search`,
`ai/decision/lazy_groups_match_eager`, `ai/decision/throw_piece_matches_whole`.
Its options are one per kind it carries (`frag`, `stun`). Measured with `tools/von_probe.py` (`tools/von_scenarios/grenade_*.json`, captured from the
recorded-Von tests): the barricaded holder of a doorway GRENADE 0.49 to 0.51 against ENGAGE 0.32 to 0.40 (dropping the exposure sentence or the desc's
clause hands it back to ENGAGE; a desc that keeps "Your line to {target} is blocked" for it loses, 0.14 against 0.61); behind cover
(GRENADE 0.43 to 0.52 against ENGAGE 0.23 to 0.29 on a decision taken while the first decision's ambush is under way, the level
`grenade_hidden_behind_cover.json`; in the scene it was captured from, a householder crouched behind a sofa in the kitchen seen from the garden
through the back doorway, no such decision comes, since adopting an order starts none of its own (E9): the first decision gives ENGAGE 0.35,
FLANK 0.26, GRENADE 0.20, the throw from a spot nearby since the lob in place grazes the jamb, and the one on the cadence 4.5 s later FLANK 0.32,
ENGAGE 0.26, GRENADE 0.23, so there a defender hidden behind cover loses the grenade to ENGAGE); at the shots' origin GRENADE 0.77 against
RETREAT 0.23 (dropping the room sentence from the state: 0.68). Through a throw spot (`grenade_throw_spot_*.json`, levels captured in real matches and the R7
level, worded as the snapshot now words them): the walk's words change nothing measurable (dropping "from a spot nearby": -0.02 to +0.02): hidden behind
cover 600 px off GRENADE 0.44 against ENGAGE 0.34, the barricaded doorway holder 0.49 against 0.40, the shots' origin 0.78 against RETREAT 0.22; over 40
captured out-of-range levels GRENADE ranks first in 18 ("within throwing range from a spot nearby", mean 0.30) against 17 for the in-place wording (mean
0.29), the rest going to ADVANCE, FLANK or ENGAGE as in the original levels. It is never offered
- when a **known ally** would be inside that grenade's danger zone (G16) at the landing spot (the option's tag `ally_in_blast`, in the tactic's
  `drop_tags`);
- when the **NPC itself** would be inside the zone **and has no way to get safe before the fuse runs out** (tag `no_safe_spot`): it is safe if it
  can get behind cover that shields it from the landing spot (G7: the real 3D line, ducked or standing), or reach a spot out of the blast's line of sight in time. With a way to get
  safe, being inside the zone does not drop the option. (Cover that hides a ducked hostile from a bullet shadows the thrower from a burst there, so a hidden hostile's own cover is almost always a
  safe place, which follows from straight lines from a burst on the floor (a ray to a body behind a low piece rises too slowly to clear it, and a thrower's line is the same one) and holds only for such a burst, not one that lands on a desk: `no_safe_spot` is left for a thrower with no such cover and no way out of line in time: `ai/grenade/escape_judges_real_geometry` (the judgement) and `ai/grenade/grenade_not_offered_no_safe_spot` (end to end: an invader held in the open in line with a doorway, 280 px from a householder inside, is tagged and not offered GRENADE; given its legs back it is offered).);
- against a hostile in its line of fire in the NPC's own room, or outdoors with it (it shoots).

A **confined** NPC (its territory, the room a defend order keeps it to, its squad leash, a held stack's room: its confinement, `GLOSSARY.md`) has a throw judged
where it is thrown from, `params.from` (where it stands, or the throw spot), as every COMBAT option is judged where it acts, never where the
grenade bursts: a territorial defender inside the house may throw onto a spot outside it, while a throw spot outside the house, the
ordered room or the leash is not offered.

The leaf runs the new `throw` primitive: with a throw spot it first walks all the way to it (6 px: the lob was judged from there) with its gun in hand,
the watch stage on any threat in sight, a walk the entry guard covers like an ENGAGE walk (it keeps out of doorway views or secures a doorway it must
pass, and goes into an uncleared room by entry, E9 / E15 / E18; then the walk goes on, test `ai/grenade/grenade_throw_walk_secures_doorway`); then it selects the grenade, aims at the spot, throws, radios `frag_out` / `bang_out` (callout `status`, as the
grenade leaves the hand: `point` the landing, `kind`), puts the gun back in hand, then takes whichever safety is nearer (the G16 plan, which knows
its own grenade: crouch behind that cover, or move out of line) and **holds it until the detonation**, then re-decides (after a stun it naturally
goes on to ADVANCE or ENGAGE while the target is blind: a hostile the NPC, or an ally, caught in the flash of a stun it threw reads "blinded by a flash"
in the state and the ADVANCE option, for a few seconds, `flashed` in memory). A thrower outside the zone has nothing to hold: it waits out the fuse
with the gun in hand and shoots what it can. The NPC decided on a snapshot of a moment ago, so when the order is adopted it may stand a few px past its range
of the spot: it then closes in until it is 15 px inside it (`AgentThrow.REACH_SLACK`) and throws (it does not give the throw up and flap in and out of the offer at
the edge of the range). The throw is dropped, and the NPC re-decides, if the lob has become impossible (no arc of the planner clears what is now in the way) by the
time the wind-up starts; once the wind-up has begun the throw is committed and radioed whatever happens to the line meanwhile. The throw order keeps
the spot it was offered on (the hostile's last-known spot) when that contact ages out on the way (out of sight past `tuning.memory.contact_ttl` while it walks
to a throw spot, or while the entry guard's detour on that walk secures a doorway): losing the contact is not a change of belief that re-decides (the
order keeps its hostile in the salient key while it runs, and while a detour has paused it), so the walk goes on, the detour hands the throw back and the
grenade goes onto that spot. A new hostile still re-decides, and so does the death of the hostile the throw was offered on: a dead character is no
contact and no lost hostile, so it leaves the salient key, and a throw not yet in its wind-up whose hostile the NPC no longer knows of at all ends then
and there, so no grenade goes onto a body while the next decision is on its way.
Options are `frag` and `stun`. What the AI knows of a grenade it has not thrown yet (how far it throws, its blast or flash radius, its fuse, how
near furniture must be to shield from a flash) it reads off the grenades it carries, `Character.inventory.throw_stats(slot)` (G1), and off a live one it sees
(`ThrownGrenade.throw_stats()`); it keeps no mirror of the numbers, so retuning a `GrenadeConfig` row retunes the AI (the tests
`items/grenade_throw_stats` and `ai/grenade/grenade_range_follows_the_item`). What stays the AI's own tuning is the NPC's
`tuning.grenades`: `hear_grenade`, `evade_margin`, `enabled`. `debug_grenades().throw` holds `{ from, to, kind, radius }` while the throw is planned (until the grenade leaves the hand).
Tests: `ai/grenade/grenade_not_offered_ally_in_blast` (an ally in the zone), `ai/grenade/grenade_offered_when_cover_shadows_thrower` (the thrower in the zone
with only a coffee table, or a couch, that hides the hostile: offered in both, the cover shields it from the burst on the floor), `ai/grenade/escape_judges_real_geometry`
(the judgement per posture by the 3D line: a standing body far behind a couch safe standing, one close behind it only ducked, a burst on a desk shadowed by nothing low),
`ai/grenade/grenade_not_offered_clear_shot` (and the same hostile pulled back to 740 px: offered only through a throw spot), `ai/grenade/throw_primitive_returns_to_gun` (the mechanism, scripted Von: the far thrower throws and
returns to its gun after the bang; the near one is behind its couch, shielded, until the bang, is unhurt, then returns to its gun);
`ai/grenade/grenade_range_drift` (scripted Von, slow answers: a thrower pushed past the range while its question is in flight closes in and throws, GRENADE picked once),
`ai/grenade/throw_dropped_when_lob_blocked` (a wardrobe across the lob while the question is in flight: the throw is given up, nothing thrown before Von
is asked again, and a throw that follows leaves from a throw spot round the wardrobe),
`ai/grenade/throw_committed_in_windup` (a wardrobe across the lob as the hand is drawn back: the grenade still leaves and is radioed);
`ai/grenade/combat_frag_hidden_hostile` (a thrower outside its zone), `ai/grenade/combat_frag_take_cover` (inside it, with cover at hand: throws,
crouches until the bang, unhurt), `ai/grenade/combat_stun_then_advance` (the scenarios, recorded Von); issue #51: `ai/grenade/grenade_door_holder`
(a householder holding the kitchen's back doorway in the line of fire of an invader in the garden: frag thrown into the kitchen onto it),
`ai/grenade/grenade_barricaded_behind_cover` (crouched behind a sofa inside: the frag is lobbed over the sofa (G3) and catches it, the thrower
clear), `ai/grenade/stun_entry_shot_from_room` (shot at from the kitchen: GRENADE offered at the shots, nobody walks in unguarded), recorded Von;
scripted, `ai/combat/locate_not_into_shots_room` (shot at from the kitchen: GRENADE offered, no LOCATE) and `ai/combat/locate_toward_shots_from_open`
(shot at from the open garden: LOCATE offered); the throw spots (R13, R15): `ai/grenade/grenade_throw_spot_out_of_range` (scripted: an invader 640 px from a
hidden hostile walks to a throw spot and throws; with a frag whose zone reaches past the throw range the throw spot is tagged `no_safe_spot`),
`ai/grenade/grenade_throw_spot_round_wall` (scripted: an invader that saw the householder through the back door is behind the house wall, with no lob,
when it first decides (the premise: Von down for the question asked in sight): the throw from a spot at the back doorway, kept through the entry guard's
detour at the back door after the contact has aged out, and the stun on the householder's spot),
`ai/grenade/grenade_throw_target_killed_redecides` (scripted, the same premise: the householder killed while the invader walks to its throw spot, a new
decision at once and nothing thrown),
`ai/grenade/grenade_throw_spot_round_jamb` (scripted: the line from the invader's centre clears the back door's jamb, the lob from its hand does not:
a throw spot, not in place, and the stun goes in), `ai/grenade/grenade_lob_follows_throw_stance` (scripted: the same with the `throw` stance retuned to
the left hand, whose lob clears the jamb: thrown from where it stands), `ai/grenade/shots_origin_not_the_landing_room` (scripted: shot at in the kitchen
from the living room, then in the hall: the living room is suspect and grenaded, the kitchen neither),
`ai/grenade/grenade_walks_to_throw_spot` (recorded Von: a householder holding the living room 650 px off through a doorway, fragged from a throw spot) and
`ai/grenade/grenade_shots_origin_throw_spot` (recorded Von: shot at from the kitchen while beside its back door, the frag thrown from in front of the doorway),
`ai/grenade/grenade_range_follows_the_item` (the frag's range retuned to 300 px: thrown from within 300 px after a walk),
`ai/grenade/territorial_throw_from_inside` (scripted: a territorial defender with a frag inside by the front door, its hostile just outside
behind a desk that stops its rounds: GRENADE is offered at COMBAT and the throw leaf's `from` is inside the house).

**G18. Bang entry (SEARCH, then ENTER).** When the NPC (or its stack, by the claims on the radio) carries a stun, SEARCH offers two entry
tactics: **ENTER** (quiet, as before) and **STUN ENTRY** (`stun_entry`: "a doorway leads into a room where a hostile was heard, seen, radioed or shooting from";
Von picks against the facts, worded as measured below). The first claimer's mode travels with its claim and the stack follows it.
**A suspect room means a bang, for every entry** *(issue #51, R10)*: whatever brought the NPC to the doorway (ENTER, STUN ENTRY, or a walk the entry
guard turned into an entry, `docs/tactical-entry.md` E9), an entry into a room it suspects (below) is a bang one when the stack carries a stun; an ENTER
run so is named as the STUN ENTRY it is (`search/stun_entry/<door>`), a guard's entry keeps its walk's name.
In a bang entry, once the stack is ready: the **thrower** (the slot-2 member if it carries a stun, else the lowest slot that does; alone,
itself) radios `bang` (`entry_step = &"bang"`, phase `bang` between `stack` and `cross`), throws the stun to the room's far side through the
doorway, and every member holds its slot turned away from the door; on the detonation the point **skips the pie** and crosses at once,
the rest follow as usual (E4 to E8 of `docs/tactical-entry.md`). If the throw is impossible (no stun left, no clear path into the room) it
falls back to a quiet entry; so it does when the call never comes (`BANG_CALL_CAP` 8 s after the stack is ready) or the stun does not go off (`BANG_BURST_CAP`
5 s after the call), and a member that sees a teammate's claim say quiet goes in quietly at once, its own claims saying so. Where nothing suggests the room is occupied, ENTER is the pick and nothing is thrown.
**The ordered frag entry** (`docs/leadership.md` LD14, `docs/tactical-entry.md` E17). A frag is thrown at entry only by a stack its leader
ordered in with a frag (the order's `mode` `frag`); an unordered stack, STUN ENTRY and the suspect-room bang throw a stun. The roles are the
stun's: the thrower is the slot-2 member if it carries a frag, else the lowest slot that does (every entry callout carries `frags` beside
`stuns`), and it throws from the same spots (`Combat`'s `throw.begin` on `FRAG_SLOT`, at the frag's reach). It aims only where the burst leaves
every claimed slot of the stack, its own included, out of the frag's danger zone (G16: a clear line within 370 px; the wall beside the door
shields the stack), and with no such target it gives the frag up and the stack goes in quietly (`bang_off`). It radios `frag_out` as the frag
leaves its hand, as GRENADE's thrower does (G17); the stack holds its slots crouched and turned away until the burst (`FRAG_BURST_CAP` 7 s
from the call, against `BANG_BURST_CAP` 5 s for a stun), and on the frag's burst in the room the point crosses at once, no pie. A frag stack
with no frag left once it is in goes in quietly (`bang_off`), the order still done at the cleared room. Tests: `ai/grenade/order_frag_entry`,
`order_frag_no_frag_goes_quiet`, `order_frag_held_then_go` (scripted).
How it is made to happen (E17 of `docs/tactical-entry.md` has the rest): the entry callouts carry `bang`, `stuns` and `frags`; the stack is in bang mode only if every
claim says so; the thrower steps out in front of the door (`BANG_STEP_OUT`) to a spot from which the lob from its hand is clear of the jamb (G17's
lob test), walks all the way into that spot (6 px: a stride short of it the jamb can be in the way), and
aims at the room's far side (85% of the room's depth, on the doorway's axis if the lob is clear), or, in a room deeper than a stun reaches from where it throws
(a long hall entered from its end), at the farthest point along that line it reaches, at least 120 px in from the doorway (the aim rule
is the doorway geometry's, `ai/perception/entry/entry_landings.gd`, which an ambush post is shielded by too, `docs/leadership.md` LD15). The plan is tried a dozen
aims a frame, the thrower waiting meanwhile. A stun grenade in flight in the doorway is not evaded by the
stack members, who hold turned away beside the wall (G16 still moves anyone else). Nor is an ordered entry's frag, in flight or come down where the member's
slot is out of its zone (the slot is its cover, `Entry.expects_burst`); a member whose slot the frag reaches (one that came back to the door) evades it as G16 says.

**A suspect room** *(amended by issue #51, R6)*. A room is suspect, each fact its own phrase in the doorway's option (in this order, the room's doorway listed first), when:
- gunfire it heard came from inside it: "gunfire heard there";
- it heard a stranger's footsteps there (`docs/hearing.md` H1): "footsteps heard there";
- the NPC was shot at from it: the line back from where a shot at it landed, to the first wall behind, runs through the room (memory `shot_from`, `{ at, pos }`, kept
  `tuning.memory.lead_ttl` 20 s, long after being under fire is over; `debug_memory()["shot_from"]`): "shots at you came from there". The line counts from where it leaves
  the room the shot landed in (`AgentSuspicion.shot_line`): that room is only where the NPC stood, and once it has stepped out it is neither suspect nor where a
  grenade at the shots is aimed; when the line never leaves it, the shooter stood in it too, and it counts;
- an ally radioed a hostile or a fight in it: every combat `callout` carries `target_pos`, the hostile's last-known spot as the speaker knows it (with no hostile known,
  where the shots at it came from): "an ally radioed a fight there";
- a hostile it lost sight of was last seen in it: "a hostile seen going in"; lost outside it within 150 px of one of its doorways: "a hostile lost by its doorway"; lost
  moving, with where it was heading (as the "where they were heading" lead reckons it) inside it: "a hostile seen heading in".

A reason that comes up once a quiet entry is under way, before anyone crosses, turns it into a bang, and so does a member that joins a quiet stack knowing one
(E17 of `docs/tactical-entry.md`, issue #51 R11: the claims say bang, the stack follows, the thrower throws first; the claims of a member that gave the bang up
say `bang_off` and keep it quiet). **A quiet stack listens first** *(issue #51, R17)*: a quiet entry whose stack carries a stun holds at the stack
`tuning.entry.listen_time` (3 s, a tunable of the NPC's) from the point getting to its slot before the point slices the pie, so a late reason has time to come
up; a hostile in view or coming under fire ends the hold early, and a stack without a stun (or one that gave the bang up) does not hold.
**The thrower is committed to the bang** *(issue #51, R16)*: from its call until the stun leaves its hand (the walk out to its spot, the stun taken in hand,
the wind-up) no new decision is started or adopted, so a hostile seen on the walk out or in the wind-up does not make it leave; it throws, then decides
again from where it stands (a decision held off meanwhile is taken the moment the stun is away). The caps still end it (`BANG_BURST_CAP`, the stun lost,
no way through to its spot, the thrower killed). A member that leaves the stack for a fight does not cancel the bang, and any stun its own team
throws that goes off in the room (one thrown by GRENADE included) counts as the bang: the members still at the door go in on it (R8).
With a stun in the stack none of these is an INVESTIGATE lead for a room a doorway leads into (the last-seen and heading leads of such a hostile, gunfire and footsteps
there, the unseen-shooter lead, an ally's support call): the way in is an entry, whose option says why. Measured with `tools/von_probe.py` (`tools/von_scenarios/stun_entry_*.json`,
the SEARCH level an invader outside sees): STUN ENTRY ranks first with each reason (0.39 to 0.46 against ENTER 0.33 to 0.37; dropping the reason's phrase hands it back to
ENTER, but for gunfire heard, which the state's awareness line names too: either one alone keeps the bang), and ENTER with none (unexplored 0.46 against 0.29, unsearched
0.45 against 0.25). A desc naming only two reasons ("where gunfire was heard or a hostile was seen going in") also ranks every reason first but ties ENTER on an unrelated
phrase; one listing every reason ("gunfire or footsteps were heard, shots came from, an ally radioed a fight ...")
gives the bang to a plain unsearched room (0.41 against 0.36).
Tests: `ai/grenade/stun_entry_suspect_room`, `ai/grenade/quiet_entry_unsuspected_room`, `ai/grenade/stun_entry_ally_radioed`, `ai/grenade/stun_entry_hostile_lost_near_door`,
`ai/grenade/stun_entry_footsteps_heard`, `ai/grenade/stun_entry_shot_from_room` (recorded Von), the late reason (`quiet_entry_turns_bang`,
`quiet_entry_crossing_stays_quiet`, scripted), the guard's entry (`ai/entry/entry_guard_bang_suspect_room`: a search walk through the back door into a
kitchen gunfire was heard in goes in with a bang; `entry_guard_quiet_unsuspected_room`: the same walk with nothing heard, quietly; scripted) and, scripted, one fallback each:
`ai/grenade/bang_fallback_no_clear_lob` (wardrobes across the kitchen), and the aim into a room deeper than a stun reaches: `ai/grenade/bang_into_long_room`
(the Terrace house's 840 px hall from its front door: the stun goes off in the hall, the thrower outside unflashed), `bang_fallback_stun_lost` (the thrower's stun gone after its call: the rest follow within seconds,
not after the burst cap), `bang_fallback_never_called` (a teammate that is ready and never calls), `bang_fallback_never_goes_off` (a call and no throw).

**G19. Debug overlay** `show_grenades` (a row of the overlay table, a child of every NPC, in the AI behaviour group): the planned throw arc and
landing spot with the grenade's danger radius, the live grenades the NPC knows of with their radii and fuse left (a countdown arc against the grenade's whole `fuse`), and the escape spot it
is running to. It draws from `debug_grenades()`.
Test: `ai/grenade/grenade_overlay_draws`.

## Performance

*(Added by issue #56.)* Grenades going off must not make the game stutter. Two perf tests hold them to the smooth standard every frame-based
perf test holds (`Perf.SMOOTH_*` in `tests/_perf/perf_probe.gd`): **average ≤ 16.7 ms** a frame (one 60 fps frame),
**p95 ≤ 20 ms** and **no frame over 33.4 ms** (two frames). The one exception is P1, whose p95 is **≤ 25 ms** and whose worst frame is **≤ 37 ms** (its own `P95_MS` and `MAX_MS`, passed to
`Perf.within_frames` as `p95_limit` and `max_limit`): its p95 reads 20.9 to 22.6 ms at load about 3 and 23.0 to 24.2 ms at load 4 to 4.9, with no single cause left to cut (decision on #195, item 4); its worst frame reads 27 to 31 ms in single runs but 34.75 to 36.02 ms inside the full perf run, against the standard's 33.4 (decision on #195, rule 13).

**P1. Grenades in a match** (`perf/grenade_match_stress`). The 5v5 of `perf/match_5v5_stress` (a generated house on its largest plan, the match built
as Main builds one through `MatchBuilder`: the invader team beside the front door with its plates and a stun and a frag each, styled and ranked, one
squad a side; nav re-baker, blood, debris, sound and radio on, scripted Von); once the sides are in contact (a shot fired and some NPC knowing a
hostile) a puppet on the invaders' side, a test actor and not one of the match's, throws three frags and three stuns among the fighters over about 3
s, through the controller contract, so every NPC's grenade perception, evade planning and re-decision is in the measurement, and a grenade an NPC
throws meanwhile is part of the load. Measured from the first throw to 3 s after the last burst; the premise that all six went off counts only the
puppet's own.

**P2. A burst in a crowded room** (`perf/grenade_burst_stress`). A frag and a stun going off together among twelve pieces of furniture and eight
characters (blood, debris, hit particles and sound on). Measured over the burst frame and the 2 s after it.

**How they measure.** Each test frames the whole fight with the test camera, as a player's screen would show it, so every body is drawn.
Headless (the default) the frame time is the CPU's work, the drawing calls included; `tools/run_tests.sh --windowed` runs the same test in a
window with vsync off, so the render is in each frame too. The absolute budgets stay as they are in both modes: a red windowed run is the
honest state of the game's performance, not a test to loosen. P1's p95 of 25 and worst frame of 37 are the only budgets moved, by the decisions on #195 (item 4, rule 13); the
dated windowed p95 of 21.98 below was read against 20, the budget of that day.

**Before** (origin/main `7428c4a`, before issue #56's fixes; one run each at a 1-minute load of about 2.9, ms a frame):

| Test | Mode | avg | p95 | max |
|---|---|---|---|---|
| P1 | headless | 10.78 | 17.51 | **34.30** |
| P2 | headless | 5.73 | 10.08 | 32.27 |
| P1 | windowed | **23.37** | **32.44** | **50.19** |
| P2 | windowed | 12.69 | **20.13** | **41.59** |

**After** (16 October 2026, issue #56 on origin/main `f0e4f8e`; each run started at a 1-minute load of 3.0 or less, one Godot at a time, the
load before → after each run; bold misses its budget). The headless runs are of the whole of issue #56, the audit's fixes included. The
windowed runs were made just before those fixes and not repeated: the fixes change nothing that is drawn (comments, and a worker's cut making
its own circle ring), and the headless runs after them stayed within the noise of the runs before them (P1 avg 9.08-10.49, p95 15.03-16.31, max
22.73-31.60; P2 avg 5.80-6.56, p95 8.20-8.86, max 23.08-23.88):

| Test | Mode | Run | Load | avg | p95 | max |
|---|---|---|---|---|---|---|
| P1 | headless | 1 | 2.94 → 2.86 | 9.97 | 14.64 | 23.26 |
| P1 | headless | 2 | 2.86 → 2.96 | 9.80 | 15.28 | 21.57 |
| P1 | headless | 3 | 2.96 → 2.88 | 9.35 | 13.85 | 22.12 |
| P2 | headless | 1 | 2.88 → 2.90 | 5.84 | 7.96 | 23.45 |
| P2 | headless | 2 | 2.90 → 3.79 | 7.02 | 9.56 | 27.38 |
| P2 | headless | 3 | 3.00 → 2.77 | 6.57 | 9.03 | 22.74 |
| P1 | windowed | 1 | 2.78 → 2.79 | 16.15 | **22.76** | **39.64** |
| P1 | windowed | 2 | 2.79 → 2.81 | **17.65** | **22.98** | 28.71 |
| P1 | windowed | 3 | 2.81 → 2.99 | 14.51 | 19.64 | 27.18 |
| P2 | windowed | 1 | 2.99 → 3.88 | 10.64 | 14.61 | **38.33** |
| P2 | windowed | 2 | 2.73 → 3.18 | 12.00 | 14.62 | **36.55** |
| P2 | windowed | 3 | 2.49 → 2.87 | 10.24 | 13.25 | **35.99** |

Headless, both pass in every run, and `tools/run_tests.sh --domain=perf` (one run, load 2.78 → 2.94) passed all eleven perf tests (P1 8.59 /
13.21 / 24.53, P2 5.58 / 7.47 / 22.66). Windowed, P1 came down from 23.4 / 32.4 / 50.2 to 14.5-17.7 / 19.6-23.0 / 27.2-39.6 and passes now
and then; P2 from 12.7 / 20.1 / 41.6 to 10.2-12.0 / 13.3-14.6 / 36.0-38.3, its average and p95 well within, its worst frame still over.

**Where the time went** (the profile of issue #56, its fixes pinned each by a test that holds the new code to the plain one, all without a change
to what is drawn, when or how anything behaves): the bodies' drawing was about 70 % of a rendered frame, each plain-coloured polygon a vertex
buffer of its own, so they go out as General's `FillBatch` (one triangle array) and the limbs are built once a frame for body and shadow; furniture
moves its drop shadow instead of repainting on a turn and walls repaint the struck segment alone; spreading pools blur separably; dented colliders
are cut and a spray's splats merged side by side on worker threads; navigation re-bakes measure and parse once a tick; the escape search judges each
spot once (and, since issue #65, shares what depends on the burst alone among the NPCs planning on one physics frame: `docs/leadership.md`,
Performance); and weapon art is painted ahead of time.

**Issue #78** (19 to 21 October 2026) kept the same budgets windowed, no exemption, and fixed the window's costs at their cause, each fix
pinned to the old pixels or bytes: the sound library's pre-warm renders on a worker thread instead of about 10 ms a frame on the main
thread (`domain-audio`); a debris chip lands as a record in its layer; and a hit's spray no longer waits for its splats' merges, which finish later in the
frame (`domain-physics` (`blood.md`)). The limb outlines as kept meshes were measured and dropped (exact, but no faster). Three windowed
`tools/run_tests.sh --windowed --domain=perf` runs on 21 October 2026, each alone (no other Godot during it); this machine's quiet
baseline that day was a 1-minute load of about 5 (ordinary apps), load before → after (peak) 4.46 → 4.64 (5.87), 4.83 → 3.89 (4.83),
2.79 → 4.70 (5.26) (avg / p95 / max ms; bold misses):

| Test | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| P1 | 16.54 / **22.84** / 32.42 | 16.31 / **23.74** / **33.97** | 15.60 / **21.81** / **33.46** |
| P2 | 9.41 / 12.10 / 30.09 | 9.77 / 13.40 / 26.86 | 11.01 / 13.99 / **39.85** |

P1 does not meet the standard windowed: its average is under the budget and its p95 2-4 ms over. P2 holds its average and p95 and missed
once on one frame (39.85; 26.9-31.4 in the other five windowed runs since 19 October). Headless the same build passes (P1 10.61 / 15.80 /
25.29, P2 6.44 / 8.40 / 22.50, load 4.00 → 3.61). The other perf tests' windowed numbers are in the `domain-testing` skill (Performance
tests, "Rendered too"), with the latest windowed runs of all twelve, from before issue #95.

**The GdUnit panel.** One **Run overall** from the editor's GdUnit panel on 21 October 2026 (every suite, an hour; no other Godot but the
editor and its runner; the perf suite at a 1-minute load of 3.9-5.1) gives the windowed verdicts: P1 15.59 / **21.98** / 31.88, its p95
over as in every windowed run; P2 10.49 / 13.08 / **40.50**, its worst frame over as in two of the three latest windowed runs in
`domain-testing`. Of the twelve perf tests nine pass and three fail (P1, P2 and `match_10v10`'s p95 at 20.87), each on a measure the
windowed CLI runs miss too; the panel's numbers for all twelve are beside the windowed table in `domain-testing`.

**What is left.** Of P1's windowed frame (15.6-16.5 ms on average) about 10.6 ms is paid headless too: the characters' physics frame
with the AI it drives (6.4 ms, 0.41 ms a body in both modes, measured with a timer on every `_process`, `_physics_process` and `_draw`),
the ragdolls, and the fallen bodies, which repaint every frame until they settle (about 2 ms a repaint, mostly the trunk's outline built
twice, body and shadow; only 3-5 % of those repaints change nothing). The window adds the rest: the standing bodies' drawing on the
script side (5.3 ms against 3.5 headless) and the engine's render of the frame. Closing it needs work on the AI and the fallen bodies,
outside #78. P2's worst frame is the frag's own frame, about 23 ms of CPU and about 12 ms more of rendering what the burst adds in it
(not a first use, not the flash lights: both ruled out by measurement in the profile). An atlas for the limb art was built and measured
and gained nothing in P1, so it was not kept. What would surely close the rest is only what the user ruled out: visible or timing
changes (fewer splats per blast, the blast's work spread over frames, simpler art).

**Issue #95** builds P1's match through `MatchBuilder`, so its invaders carry their plates and grenades, are styled and ranked and follow
their squad's leader, from beside the front door. Re-baselined headless only (`tools/run_tests.sh --domain=perf --verbose --summary
--no-lint`, three valid runs a side, each started at a 1-minute load under 3.5 with no other headless Godot, a run whose load went over 4
discarded; before 4af0b43, after 91400e6's guard code, measured before the branch was rebased onto #81), P1's medians went from 10.16 /
15.09 / 24.20 to 10.58 / 17.29 / 33.18, and P2's from 6.41 / 8.47 / 22.10 to 6.89 / 8.90 / 22.50. P1's median passes; its max missed in one run of three (34.52). Not yet re-measured windowed; the other
guards' numbers are in the `domain-testing` skill.

**The prepaint's cost.** A gun or grenade paints its art ahead of time once per weapon style per process (`ItemRegistry.inventory_for`, every
raise step, both lying sides, every lighting step: the very draws it will make), about **230 ms** once, when the first inventory in that style
is made at a match's spawns; later inventories cost about 0.05 ms. It moves 0.3-0.5 ms first paints out of a fight's busiest frames.

## How the rules are enforced

- **Items** (`scenes/items/`): `GrenadeConfig` (the numbers above, one row per kind), `GrenadeItem` (count, wind-up, `throw` stance),
  `ThrownGrenade` (flight, bounce, fuse), the art, `ItemRegistry` (`STUN_SLOT`, `FRAG_SLOT`, `create(id, count)`), `LoadoutConfig`, and `GunConfig`'s `one_hand_spread_deg`.
- **Character**: `inventory.item_count`, `inventory.throw_stats`, `weapon.aim_target`, `movement.run_speed` and `movement.walk_speed` (what the AI judges a place in time by), the stun state
  (`take_stun`, and the `stun` component's `is_blind`, `is_deaf`, `level`, `view`; its numbers are `CharacterStunConfig`'s) and its effect on speed, running and aim, the stunned look
  (the `eyes` and `one_hand` stances, the hunch and the stagger) and `weapon.one_handed()`, `blast_push` for ragdolls.
- **Lighting**: the stun's flash (`LightingConfig.flashes`, `WorldLighting3D`).
- **Projectile**: `Explosion.frag` / `Explosion.stun`, and the `max_range` of the `Shot` `ProjectileSpawner.spawn` takes. **Physics**: the explosion FX.
  **Audio**, **General** (camera, EventBus topics `throw`, `grenade`, `explosion`, `stun`), **UI** (`StunScreen`, the setup window,
  the overlay table) and **AI** (perception of live grenades, the throw geometry, the `grenade` and `stun_entry` nodes, the `throw`
  primitive, the evade reflex, the blind-fire roll and holding fire, the bang phase of `entry.gd`, the overlay).
- **The tests reach all of it duck-typed** (`has_method`, `call`, groups, topics, node ids), because most of it did not exist when they
  were written.
- **Cover** is the real 3D line from the burst to each point of the body at its posture's heights, stopped by the twin geometry (`Explosion.shields`, `Explosion.first_stop`);
  the tests read it with `GrenadeAi.shielded` (`tests/_ai/grenade_ai_probe.gd`: a line of its own from the burst, in the twin space).
- **Scenario tests** run the whole pipeline with recorded Von answers (replayed, `--record-von` refreshes them), the rest of the AI on and nothing scripted. Their premises are the
  puppet thrower in the evade scenarios (an invader puppet that cannot be killed, armed with one grenade the way the match builder arms a spawn), the
  hostile puppet that cannot be killed and never shoots in the combat scenarios, the one shot of gunfire heard in the stun entry, and the
  `take_stun` call that stands in for a grenade in the two NPC-effect scenarios (the throw itself is tested elsewhere). No behaviour switch is used in
  a scenario test: the deaf-NPC scenario has only two household defenders, so trespass hostility has nobody to act on without being switched off. The test world keeps
  the default inventory, so each scenario arms its invaders at the start of `run` with `LoadoutConfig.apply`, as Main does.

## Numbers

| | Stun | Frag |
|---|---|---|
| Slot | 7 | 8 |
| Fuse (from release) | 1.5 s | 3.0 s |
| Throw | wind-up 0.3 s, `max_range` 550 px, `restitution` 0.35 | same |
| Throw spot (AI) | at most 250 px of walking (`throw_spot_walk`), within 535 px of the spot | same |
| Flash / blast radius | `flash_radius` 400 px (full inside 100) | `blast_radius` 250 px (full inside `kill_radius` 120) |
| Effect | blind up to 5 s; deaf up to 6 s within 350 px (x0.4 through a wall); 5 damage within 30 px | 60 damage; 40 fragments of 12 damage (a share of it after the hit zone) over the upper hemisphere, penetration 0.4, 500 px reach |
| Danger zone (AI) | line of sight within 400 px; furniture shields only within 30 px of the body (`flash_cover_reach`) | line of sight within 370 px (250 + 120 margin); a body whose every point the real 3D line from the burst cannot reach (G7) is shielded: a ducked one behind cover taller than its head, a standing one in a low piece's shadow |
| Heard landing (AI) | 300 px | 300 px |

The stun on the character: speed x0.45, sway 25 degrees, no running, tail 1.5 s; blind with a gun, one-handed: spread wider by 3 (pistol), 6
(SMG) or 8 (rifle) degrees.

## This game's own rules

Everything numeric in the tables, and in particular: the sizes of the radii and times (the real ones only set the order of magnitude);
the linear falloffs of the blast, the flash and the bang; the facing factor of the flash (x1, x0.6, x0.25); x0.4 through a wall; the
stun's effect on a character (G13); the lob over a piece lower than the highest arc, the bounce off the rest and off walls and a doorway's lintel, and the release heights and apex (G3); a grenade's lack of
cooking, pick-up and throw-back; the loss of every unthrown grenade at death (G4); friendly fire (G9, a fact of the real weapons, but the
absence of any rule to spare an ally is the game's); the evade reflex and its margins (G16); the GRENADE tactic and its dropping rule (G17);
the bang entry and its roles, including the turn-away hold and the point that skips the pie, and the ordered frag entry's aim that keeps
every slot out of the zone and its crouched hold (G18); fragments stopped at 500 px; the
setup defaults of 1 + 1 for invaders (G5).

## Sources

How far each is to be trusted. Mixed quality; none is current doctrine for a game, and the figures are only used for scale.

- GlobalSecurity, [M67 fragmentation hand grenade](https://www.globalsecurity.org/military/systems/munitions/m67.htm): the fuze of 4 to 5
  seconds, the killing radius of about 5 m and the casualty radius of about 15 m (G6, G7, G8). The same figures are in the US Army-derived
  DOD 101 summary (`man.fas.org/dod-101`), which a search returned; this page itself could not be fetched while writing, so its wording
  has not been checked.
- [Wikipedia, M67 grenade](https://en.wikipedia.org/wiki/M67_grenade), as a search summary: the body (2.5 in steel sphere, about 6.5 oz
  of explosive), the M213 fuze of 4 to 5.5 s. The Nammo M67 data sheet was on the source list but was not read.
- [Wikipedia, M84 stun grenade](https://en.wikipedia.org/wiki/M84_stun_grenade): the fuse delay of 1 to 2.3 s, a flash of 6 to 8 million
  candela (4.5 in the text) and 170 to 180 dB within 1.5 m, and the effects: flash blindness, deafness, tinnitus, inner-ear disturbance,
  disorientation and loss of balance (G10 to G13). It gives no duration or safe distance, so the 5 s, 6 s, 400 px and 350 px are the
  game's own.
- NCJRS / OJP, [Stun grenades: uses and tactics](https://www.ojp.gov/ncjrs/virtual-library/abstracts/stun-grenades-uses-and-tactics)
  (Law and Order, 1983): the light and sound surprise and briefly incapacitate people so that an attack team can enter with less risk,
  and attack timing matters (G18). Seen only as its abstract, through a search summary.
- Patent [US10215544](https://patents.google.com/patent/US10215544B2/en), a multi-charge diversionary device: its background describes
  the conventional entry, "an infiltration team storms into the room" after the stun grenade goes off (G18). The device itself is not modelled.
- USMC / Boise State military science, [building and room clearing guide](https://boisestate.edu/sps-militaryscience/wp-content/uploads/sites/123/2014/04/building-clearroom.pdf):
  the general practice of putting a grenade into a room before the entrants cross, from beside the door. The PDF could not be read while
  writing (its text is compressed and no PDF tool was available), so nothing specific is quoted from it and G18 and G17 do not rest on it.
- G15's blind fire, G16's whole reflex, the GRENADE tactic's conditions and the stun's disorientation of the character are this game's,
  not sourced.

## Not modelled

Cooking a grenade, picking one up, throwing it back or kicking it away; grenades in the dropped-item pile; breaching charges and closed
doors (issue #21); smoke and gas grenades; a frag at entry that a stack chooses on its own (only a leader's order throws one, G18);
defenders reacting to a stack at their door beyond G16 and an ordered ambush (`docs/leadership.md` LD15); grenades setting
anything on fire; structural damage to walls beyond the usual deformation; the patent's multi-charge device; hearing damage and permanent
injury; a grenade rolled along the floor; any use of stairs or an upper floor (a grenade flies at its real height, G3, but the world has one storey).
