# Gaze and fire

Where an NPC looks and when it takes the shot (the faults ruled out: an NPC turned its back on a known threat, looked at
a wall, or saw an enemy and did not shoot). The tests named under each behaviour assert this document
(`tools/run_tests.sh gaze`). The code is `scenes/ai/behavior/watch.gd` and its *watch stage*
(`Watch.apply`, which `behavior.gd` runs each tick); see `domain-ai` (`watch.md`, `behavior.md`, `combat.md`).

The one rule: **an NPC is always either looking at (and, when it can, shooting) a threat, or watching its doors; never a
wall, and never with its back to a known threat.** The character turns to wherever the controller sets `movement.aim_point`
(instantly when standing), so the question is only who sets it. The primitives set it only as they steer (a walk looks down
its path, a room search at the nearest unseen floor), and the watch stage, which runs after them every tick, overrides it with
a threat or, for a resting NPC, the doors. It also does all the shooting of a threat, so no primitive or entry phase needs
its own fire call.

A *threat* is a hostile contact (`Watch._pick_threat`): the one it is fighting if it can see it, else the nearest it can see,
else the one it is fighting as last seen, else the nearest it saw within `tuning.watch.lost_gaze` s. A contact it cannot see only
counts while it has a clear line to where it was last seen (it does not stare at a wall because someone is behind it).

*Can see* is the eye ray of `docs/player-vision.md` V2 (#194 D9): a 3D line from the NPC's eye, at the height of its posture, to the head,
chest or hips of the other body at that body's posture, clear for any one. A standing NPC looks over a table and sees a standing body behind
a sofa but not one ducked right behind it; a ducked NPC cannot look over a counter. A body in the way hides nothing.

## Behaviours

**W1. A threat holds the eyes.** Whatever the primitive is doing (a move, a search covering a room, a hold, a reload, an
engage still walking to its spot, any tactical-entry phase) the NPC faces its threat. Only a melee and an engaged NPC in
position (which aim at their target themselves) and an interaction (its own gaze, and the character is frozen anyway) are
left alone. The evade from a live grenade (`docs/grenades.md` G16) is safe first, then the fight: on the run to its spot, and
caught by a stun with no spot, its back is to the grenade; holding its spot, or caught by a frag with no spot, the threat
holds its eyes and is shot as here. A fight retargets from a contact it has lost sight of to another hostile it can see.
Tests: `gaze_search_turns_to_threat`, `gaze_travel_watches_threat`, `engaged_retargets_to_visible`.

**W2. A threat in sight is shot, in every state.** The shot is taken as soon as one is available (a loaded gun, the threat in
`shoot_range` with a clear line, the facing settled): in a move, a hold, a reload, while covering a room, and in every phase
of a tactical entry, the approach, the stack and the pie included, so an invader stacking at a door with its target in plain
view fires on it from outside (E3). A gaze step of the entry that cannot settle because the entrant is looking at a threat
counts as settled, so the entry carries on rather than waiting at the pie. Peek-and-cover and the ambush shoot only once the
facing has settled on the contact; a peek ducks only after a shot left the barrel (or on the click of an empty gun, where the
cover phase reloads), not after a refused one. The round is aimed at the middle of the part of the threat that shows
(`movement.aim_height` left to its automatic setting, `SightRay.aim_height`: the centre of the parts the shooter's eye sees, the head
when only the head shows over cover, and the middle of the torso at its posture when none does; the 3D ray of
`docs/cover-and-stance.md` H1), not at a roll of the dice: a threat behind cover it clears is struck over it, one the cover is taller
than is not, so the shot is taken whenever it is available and what stops it is geometry. The AI's own "clear line" is that same
line (`AgentVision.fire_line_clear`: from the shooter's muzzle at its pose, or at the pose its gun would rise to, to the aimed
height), so an NPC never pulls the trigger on a line its round cannot fly, and never holds back on one it can: a hostile crouched
behind a sofa is not shot through, one behind a coffee table is shot over it. Any living body standing in the line holds the shot but a known hostile (a round hits it; sight looks through it): an ally, a bystander, the human player; a ducked one under the line is shot over. The firing and flank spots the planner ranks ignore bodies (a body moves; only the trigger asks). An NPC aims at where it last knew its target, so the gate cannot leak the body's real position: the visible part is read from the last-known point and from the eye of the pose it fires in. Tests: `aim_at_visible_part`, `aim_from_last_known`, `no_rounds_into_cover`, `fire_line_held_by_any_body`.
Tests: `entry_guard_fires_from_outside`, `gaze_search_turns_to_threat`, `combat_waits_for_facing`.

**W3. An empty gun is reloaded.** With a threat in view and a spare magazine, an empty gun is reloaded at once, not carried
on a walk (`auto_reload`; not mid-crossing, E4). A gun with no spare is not reloaded and not fired.
Tests: `fire_dry_gun_on_move_reloads`, `empty_pistol_no_spares`.

**W4. With no threat: look where you are going, or watch the doors.** A walking NPC looks along its path as far as it has a
clear line, up to `tuning.watch.look_ahead` px, so it looks through the doorway it is lining up and never at the jamb or the wall
beside it. A resting NPC (a hold, a reload, a move that has arrived, the Von-down fallback) turns among the doorways of its
room, `tuning.watch.door_dwell` s at each, outer doors included, skipping any under its feet or without a clear line. Outdoors, or in
a room with no doorway in line, it keeps the gaze it has; an NPC that was never given one looks where its body points.
Tests: `gaze_hold_watches_doors`, `gaze_walk_looks_ahead`, `gaze_fresh_npc_keeps_its_facing`.

**W5. A walk that has arrived stops.** An arrived move zeroes its steering input, so the NPC stands still while the next
decision (a slow Von) is in flight.
Tests: `gaze_arrival_stops`.

**W6. No sprinting with a shot to take.** A running character can neither shoot nor reload, so an NPC that has a shot available
(or an empty gun to reload) drops to a walk and takes it, instead of sprinting on past its range. Retreating is the exception
(`run_through_fire` on the RETREAT node): it is about leaving the line, not trading shots.
Tests: `ai_runs_to_destination`, `retreat_keeps_running`.

## The beat: where it looks and fires one frame in two (#194)

An NPC senses and acts on a beat, one frame in two (`npc_pace.gd`; the rule, its wake list and the cost: the `domain-ai` skill's `beat.md`). Its aim (`aim_point`), its walk and its decision to fire are written on its beat; the body turns toward the aim and walks on the intent every frame. So an NPC sights a character in its cone at most a frame later than before, aims at it a frame later, and a gun's cooldown rounds up to its beat (a shot the weapon allows between beats is fired on the next). It never waits for a beat when a frame late would show: a burst owing a round, a throw, a tactical entry (its stack, pie and crossing, and its approach near the doorway: a team's choreography is timed against the other bodies, and a guard that covers a doorway a beat after the invader is abreast of it is a different behaviour) and a door being worked, a grenade run, a primed ambusher and a flash-blinded NPC run every frame, and a hit on it, a grenade event (thrown, landed, burst) or an order wake it for the frame. A character held in view is re-tested every second beat (4 frames).

Tests: `npc_beats_on_its_frames`, `sight_follows_a_moving_target`, `gaze_arrival_stops`.

## Tuning (the NPC's `tuning.watch`)

`tuning.watch.look_ahead` (150 px), `tuning.watch.door_dwell` (2.5 s), `tuning.watch.lost_gaze` (2 s). The turn between doorways uses
`tuning.coverage.look_rate`.

## Not modelled

Shooting through glass (a glass-panel door passes sight, not a round): the line of fire is fully physical, as it is for fire spots,
flanks and the snapshot's `clear_shot`, so such a shot is not taken (the NPC still faces the enemy).
