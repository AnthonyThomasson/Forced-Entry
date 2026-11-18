# Cover, height and posture

How a bullet decides what it meets, how crouching changes who gets hit, and what an NPC
does with its posture. The tests named under each behaviour assert this document.

Height is **real**: a body, a piece of furniture and a bullet are 3D, in px above the floor on one scale (1 px a 3D unit, a
1.75 m person 74 px: `BodyHeights`, `PieceHeights`; the sources are `docs/research/3d-cover-heights.md`). A bullet is a 3D ray in
the twin space (`TwinSpace`) and meets what its line crosses. The pieces: `projectile.gd` (the bullet), `gun.gd` and
`character_weapon.gd` (where it leaves and where it is aimed), `character.gd` and `character_posture_config.gd` (the postures),
`agent_tactics.gd` / `behavior_gait.gd` (how an NPC uses them). See the `domain-projectile`, `domain-character` skill and
`domain-ai` (`behavior.md`). Tests: `cover_shared_bullet_height`, `level_shot_over_table`.

## Behaviours

**H1. A bullet is a line in 3D.** A round leaves the shooter's muzzle at its posture's height (a standing bore 65 px up; a
crouched shooter fires from the fire-over muzzle, 43 px, its body staying at the duck's height) and flies a straight line toward
its aim point. Where it meets a body, a piece, a wall or a door it strikes it: whatever the line passes over or under it never
touches (a level round at 65 px flies over a table of 31 and strikes a wardrobe), and the same line serves everything along the
path. Where it strikes a body is the **hit zone** by the height it meets it at (`docs/outfits.md` O2, O3). The ground ends a line
that falls into it. There is no chance in what cover stops: it is geometry.
What a shot is aimed at (D8, D8a): the player's cursor aims where its line of sight first meets a character's body (hovering a
visible head aims at the head: `Pointer.aim_hit`); else at the first piece, wall, door or vehicle it meets, with a body behind it or
not, at that point on it (a shot at a lone chair strikes the chair); only with the cursor on bare floor **level** at the muzzle's
height toward the floor point, the round striking whatever stands in that line at that height. An NPC aims at the
middle of its target's torso at its posture (`movement.aim_height` automatic). A gun's spread scatters the round up and down as
well as sideways (`BallisticsFlightConfig.vertical_spread_scale`, 1 = the same cone both ways), so it can miss over or under a
body as it misses beside it. Rounds hit and kill more than they did under the old chance of clearing cover: that is the game now
(#194 D17), and no aim error is added to bring it back.
Tests: `cover_shared_bullet_height`, `level_shot_over_table`, `muzzle_height_by_posture`, `vertical_spread_misses`,
`head_aimed_over_cover`, `general/pointer_aim_hit`, `flesh_squareness_ignores_pitch`, `ricochet_off_hard_top`,
`penetration_exit_on_incoming_line`, `hit_normal_on_flat_top`.

**H2. Cover shelters what is lower than it.** A piece of cover is as tall as its top (`PieceHeights`). A line that clears it
clears any body behind it that stands no higher, and one that does not is stopped by it (and may punch through it to the body by the
usual penetration). A sofa's back is 38 px: a standing body behind it (head top 74, torso up to 64) is struck by a line that
clears the back, a ducked one (head top 36) by none that does, so a round aimed at its torso meets the sofa. Crouching behind a
low piece hides you; standing does not.
Tests: `cover_shared_bullet_height`, `sofa_cover_standing_vs_ducked`.

**P1. Postures.** A character is standing or crouching (`movement.set_posture`, the player's C toggle). Each is a row of `CharacterPostureConfig.postures`
and a real body height (`BodyHeights`). Tests: `posture_speed`, `posture_hit_chance`.

| posture | body height (head top) | speed | other |
|---|---|---|---|
| stand | 74 px (1.75 m) | ×1.0 | can run, can punch |
| crouch | 36 px, the duck (0.85 m) | ×0.6 | cannot run |

A body's twin (`CharacterTwin`) is as tall as its posture, so a crouch is struck by fewer lines in the open (the ones under 36 px,
against a standing body's under 74) and hides behind pieces at least 36 px tall. (The row's `coverage` is the 0 to 100 scale the AI's cover
picking still reads until it moves to real heights.) A crouched shooter fires from the fire-over muzzle (43 px), above the duck's head
(36), so for now a crouch fires over its cover without ever exposing its body to be hit there; the rise-to-fire that
exposes it for the burst is a later rule. Shooting and reloading work in every posture; running is refused (and costs no stamina) unless
standing.
Tests: `posture_speed`, `posture_player_input`, `posture_hit_chance`.

**P2. Changing posture.** C toggles stand and crouch. A change waits out `CharacterPostureConfig.change_time` after the last one.
Sitting or lying on an object stands the character up and locks the posture while it lasts; a dead
character takes none and falls from the standing skeleton.
Tests: `posture_player_input`, `posture_interaction`.

**P3. How it looks.** The drawn body eases into its posture (`posture_ease`). A crouch lowers the hips and
pitches the spine forward about the pelvis (`body_crouch_pitch`, 25°, the neck pitching on so the head sits ahead
of and above the shoulders); the pelvis sits back and the chest forward by half the lean, so the body stays
centred over its feet. The hips and feet come closer together than standing, the feet stand a little ahead of
the pelvis so the knees lead over the toes, the foot on the weapon hand's side steps back (a stagger), and the
stride is shorter. A crouch is drawn like a fallen body, from above with its back showing, the weapon and fists
on top. The collision circle is the same in every posture.
The arms stay on the body: the drawn shoulders and head sit at the rig's chest and head, so the forward lean of
a crouch carries them with the sleeves; the hands are held `body_crouch_hand_ahead` further forward, and a fist
beyond the arm's reach draws its shoulder after it.
A gun against a wall: a pistol's hand is pushed back by the wall in every posture. A long gun's barrel is raised
(hands drawn in, barrel shortened) and it cannot fire until it is clear.
Tests: `crouch_rig`, `crouch_arms_attached`, `standing_body_repaints_on_change`.

**P4. Turning takes time.** A standing body faces its aim at once; a crouched one swings round at no more than
its posture's `turn` rate (5 rad/s, about 0.6 s for a half turn). The aim
point is never held back, only `facing`, so the hands, the weapon and every shot follow the slower body. Standing
up catches the body up at once.
Tests: `posture_turn_speed`.

**P5. Legs touch the world.** The legs are swept from the body centre toward where the pose puts them and rest at
the first wall or solid piece they meet (as the hands do), so a stride's toes and a crouch's knees
never draw through anything; a knee that would pass through something moves the foot back. A foot or
knee swinging into a light, pushable piece shoves it where it touches (so a piece pressed near one end turns), scaled
by how fast it moves into it and capped so the piece is never driven faster than the character walks; a wall or a
heavy piece only stops the leg, and a foot at rest shoves nothing. Other characters stop a leg but are never shoved by it.
Tests: `legs_rest_on_walls`, `leg_press_turns_furniture`.

**A1. Fighting low.** An NPC fighting in place (an engaged NPC in position, or one holding or reloading
with a hostile known or shots landing) crouches (behind cover, in the open or pinned alike). It is a manner of carrying
out the leaf, not something Von picks, so it works with the server down.
Tests: `posture_crouches_in_fight`, `posture_pinned_crouch`.

**A2. Standing to run.** Anything travelling to a destination, and everything outside a fight, stands; a
crouched NPC stands before it runs and is never crouched while running. A crouch is held
for `posture_dwell` before it is dropped, so a peek and duck does not flicker; standing back up is never
delayed. The `ai.posture` switch (`posture_enabled`) turns it off.
Tests: `posture_stands_to_run`, `posture_crouches_in_fight`.

**A3. What Von is told.** Von's state mentions a posture only when someone is not standing: the NPC's own
("You are crouching.") and a contact it can see ("crouched low"). A standing body adds nothing, so the
existing wording is unchanged.
Tests: `posture_in_von_state`.

## Not modelled

A long gun against low furniture raises as it does standing. A crouched shooter always fires from the
fire-over muzzle: rising to fire only when its line is blocked, and exposing itself while it does, is a later rule. The AI's cover
picking and entry posts still read the catalogue's 0 to 100 `coverage`. Tests: `muzzle_height_by_posture`.
