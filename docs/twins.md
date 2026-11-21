# Twins: what rests on a character

How the free 3D bodies of the twin space (`TwinSpace`, interface 29: furniture, a felled door, a vehicle) behave around a character's
kinematic cylinder (`CharacterTwin`). The tests named under each rule assert this document.

**T1. A body does not hold up what rests on it when it leaves.** The engine puts a free body to sleep the frame the kinematic body
under it goes (and never sleeps one that touches a kinematic body that is moved every frame), and nothing wakes it when that body is
gone: a bookshelf leaning on a character who walks off would hang in the air asleep. So a character's twin keeps the awake free
bodies its cylinder touches and the free bodies put to sleep on it by their own rule (`CharacterTwin.hold`: `PieceBody.rest_on_a_character`),
and wakes each that may hang on it (one lying still that leans more than 2 degrees or stands off the floor; one upright on the floor sleeps of itself, one moving is awake while it moves: waking those would only change when they sleep, and with it a fight's fingerprint: `perf/grenade_match_stress` is the same fight as before) when it no longer touches one: every one of them when the character dies, ducks or stands, rides, is moved by a script or leaves the tree,
and each one it has walked clear of when it walks. The woken body then falls or settles as physics decides (flat, or leaning on
what is under it). A body that is asleep on a character, with nothing else under it, is woken by the character's leaving and by nothing else.

**T2. A leaf (or any piece) at rest on a character sleeps, within 4 s of landing.** A character is kinematic, so a free body on it is never put to sleep
by the engine. `PieceBody.rest_on_a_character` puts one to sleep that has been awake and at rest (`PieceBodyConfig.rest_speed`, `rest_spin`)
for `rest_frames` frames with no shove given it; a `DoorSlab` watches itself every frame while it is awake and not lying flat (the twin space
tells nothing of a body that does not move). A character that holds a sleeping body and has no walk to make is not moved at all (a
kinematic body moved every frame, even by nothing, wakes what touches it): it is moved again the frame it walks, or the body is woken or gone.
A character a leaf cannot bowl away (a wall or an anchored piece holds them) is what such a leaf rests on, and pushes them no further once asleep.

Tests: `objects/bookshelf_resting_on_a_character_falls_when_it_leaves` (a bookshelf leaning on a character held by a post: the character
walks off, dies or is moved, and the shelf lies down), `objects/door_resting_on_a_held_character_sleeps_and_falls_when_it_leaves` (a felled
door on a held character: asleep within 4 s, no creep in 2 s, flat or leaning on the post after the character leaves). The door's own
rules: `docs/doors.md` DR11.
