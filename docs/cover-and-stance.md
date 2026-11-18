# Cover, height and posture

How a bullet decides what it meets, how crouching changes who gets hit, and what an NPC
does with its posture. The tests named under each behaviour assert this document.

Height is **real**: a body, a piece of furniture and a bullet are 3D, in px above the floor on one scale (1 px a 3D unit, a
1.75 m person 74 px: `BodyHeights`, `PieceHeights`; the sources are `docs/research/3d-cover-heights.md`). A bullet is a 3D ray in
the twin space (`TwinSpace`) and meets what its line crosses. The pieces: `projectile.gd` (the bullet), `gun.gd` and
`character_weapon.gd` (where it leaves and where it is aimed), `character.gd`, `character_posture_config.gd` and `character_rise.gd` (the postures and the rise to fire),
`agent_tactics.gd` / `behavior_gait.gd` (how an NPC uses them). See the `domain-projectile`, `domain-character` skill and
`domain-ai` (`behavior.md`). Tests: `cover_shared_bullet_height`, `level_shot_over_table`, `rise_over_sofa`.

## Behaviours

**H1. A bullet is a line in 3D.** A round leaves the shooter's muzzle at its body's height (a standing bore 65 px up, a ducked one's 30, a
risen one's 43 or 65: P6) and flies a straight line toward
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

**P1. Postures: crouch is the duck.** A character is standing or crouching (`movement.set_posture`, the player's C toggle). Each is a row of
`CharacterPostureConfig.postures` (speed, turn) and a real body height (`BodyHeights`). A crouch **is** the duck (D7): a body folded low behind
cover, its head top 36 px (0.85 m), so a piece at least that tall hides all of it. Tests: `posture_speed`, `posture_hit_chance`, `crouch_draws_the_duck`.

| posture | body height (head top) | muzzle | speed | other |
|---|---|---|---|---|
| stand | 74 px (1.75 m) | 65 px | ×1.0 | can run, can punch |
| crouch (the duck) | 36 px (0.85 m) | 30 px | ×0.6 | cannot run |
| crouch, risen to fire over cover (P6) | 52 px (1.22 m), or 74 | 43 px, or 65 | ×0.6 | head and shoulders show |

A body's twin (`CharacterTwin`), its hit zones (`BodyHeights.zone_at`), its eye and its muzzle are those of `movement.body_posture()`: the
standing, the duck, or the pose a ducked body has risen to. So a crouch is struck by fewer lines in the open (the ones under 36 px, against a standing
body's under 74) and hides behind pieces at least 36 px tall. (The row's `coverage` is the 0 to 100 scale the AI's cover picking still reads until it moves to
real heights.) A crouched shooter with nothing in its way fires from the duck's muzzle without rising. Shooting and reloading work in every posture;
running is refused (and costs no stamina) unless standing.
Tests: `posture_speed`, `posture_player_input`, `posture_hit_chance`, `muzzle_height_by_posture`.

**P2. Changing posture.** C toggles stand and crouch. A change waits out `CharacterPostureConfig.change_time` after the last one.
Sitting or lying on an object stands the character up and locks the posture while it lasts; a dead
character takes none and falls from the standing skeleton. Standing up (or any change out of the crouch) drops a rise at once.
Tests: `posture_player_input`, `posture_interaction`.

**P3. How it looks.** The drawn body is as tall as its pose (`BodyHeights`: the duck's 36 px head top over the stature's 74, 0.49 of a standing body;
a risen one the fire-over's 52), so the mesh, the twin and sight agree, and eases into it (`posture_ease`). A crouch lowers the hips and
pitches the spine forward about the pelvis (`body_crouch_pitch`, 25°, the neck pitching on so the head sits ahead
of and above the shoulders); the pelvis sits back and the chest forward by half the lean, so the body stays
centred over its feet. Rising to fire unfolds it by the same ease (a smaller pitch, the chest higher). The hips and feet come closer together than standing,
the feet stand a little ahead of
the pelvis so the knees lead over the toes, the foot on the weapon hand's side steps back (a stagger), and the
stride is shorter. A crouch is drawn like a fallen body, from above with its back showing, the weapon and fists
on top. The collision circle is the same in every posture.
The arms stay on the body: the drawn shoulders and head sit at the rig's chest and head, so the forward lean of
a crouch carries them with the sleeves; the hands are held `body_crouch_hand_ahead` further forward, and a fist
beyond the arm's reach draws its shoulder after it.
A gun against a wall: a pistol's hand is pushed back by the wall in every posture. A long gun's barrel is raised
(hands drawn in, barrel shortened) and it cannot fire until it is clear.
Tests: `crouch_rig`, `crouch_arms_attached`, `crouch_draws_the_duck`, `standing_body_repaints_on_change`.

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

**P6. Rise to fire.** A ducked character (player and NPC alike, automatic) that fires a gun does not shoot through the cover it is behind, and does
not stay under it: when its **duck muzzle's line** toward the aim is blocked, within a short reach of its body (`CharacterRiseConfig.reach`, 60 px, about
1.4 m), by cover some pose clears, it rises to **the lowest pose whose muzzle clears that cover** (`BodyHeights.lowest_clearing`, D7a): `FIRE_OVER` (muzzle
43 px) for cover up to that, `STAND` (65 px, fully exposed above the cover) for taller. The cover's height is that of the **part** the line meets
(`PieceHeights` parts, the twin's boxes): a kitchen counter's backsplash is 44 px, over the fire-over muzzle, though its top is 38, so a level shot
over it needs a standing pose; the line is cast again from each higher pose, up to `cover_depth` past where it first met the piece, so a taller part behind
the first counts. A line that already climbs over the cover (aimed up at a torso) needs no rise. Cover no pose clears (a wardrobe, a fridge, a wall) is not
risen over: the body stays ducked, fires from where it stands, and its round meets the cover. A far obstacle (past the reach) is not its cover, and in the
open there is nothing to rise for.
The body is exposed the moment it rises (its twin, zones, eye and muzzle are the risen pose's, `body_posture()`) but holds its fire for
`CharacterRiseConfig.rise_time` (0.2 s): the rise before the first shot. It drops back to the duck `CharacterRiseConfig.dwell` (0.6 s, and at least the gun's time between rounds plus `dwell_margin`, so a slow gun stays risen between rounds) after the last
round it could fire (every shot, and a held trigger, renews it: no flicker); a gun that cannot fire (empty, reloading, cooling) neither rises nor renews the rise; it never lowers a pose it is risen to mid-burst. A shot refused for the rise is no shot: a
controller's trigger is retried each frame (an NPC's fire timer is untouched), and the player's click is held for the rise. An NPC crouched behind low cover counts a
clear line from the pose the rise would take (the same rule, `CharacterRise.pose_along`, then a clear 3D line from that muzzle to its target's torso) as a line to fire along, so it pulls the trigger and rises
(`Combat._has_firing_line_to`); the options Von is shown still read the 2D line of fire. Only a gun rises (a thrown grenade
does not); the rise is a manner of firing, so it works with Von down.
Tests: `rise_over_sofa`, `rise_to_stand_over_tall_cover`, `no_rise_behind_unclearable_cover`, `risen_body_is_exposed`, `risen_body_sees_over_cover`,
`muzzle_height_by_posture`.

**A1. Fighting low.** An NPC fighting in place (an engaged NPC in position, or one holding or reloading
with a hostile known or shots landing) crouches (behind cover, in the open or pinned alike): it ducks, and fires by rising over what hides it (P6). It is a manner of carrying
out the leaf, not something Von picks, so it works with the server down.
Tests: `posture_crouches_in_fight`, `posture_pinned_crouch`.

**A2. Standing to run.** Anything travelling to a destination, and everything outside a fight, stands; a
crouched NPC (risen or not) stands before it runs and is never crouched while running. A crouch is held
for `posture_dwell` before it is dropped, so a peek and duck does not flicker; standing back up is never
delayed. The `ai.posture` switch (`posture_enabled`) turns it off. The rise is not the AI's posture: the NPC stays "crouching" while risen.
Tests: `posture_stands_to_run`, `posture_crouches_in_fight`.

**A3. What Von is told.** Von's state mentions a posture only when someone is not standing: the NPC's own
("You are crouching.") and a contact it can see ("crouched low"). A standing body adds nothing, so the
existing wording is unchanged.
Tests: `posture_in_von_state`.

## Not modelled

A long gun against low furniture raises as it does standing (`blocked`), so a rifle held to a sofa is not fired by rising over it. A body does not
lean out from the edge of a wardrobe to fire around it: it fires from where it stands and the round meets the cover. The AI's cover picking and entry
posts still read the catalogue's 0 to 100 `coverage`. Tests: `muzzle_height_by_posture`.
