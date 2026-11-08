10. **Any domain ↔ General (EventBus)** — a generic decoupled notification bus (General autoload). Emitters and listeners never reference each
    other.
    - `EventBus.post(topic: StringName, data: Dictionary)` broadcasts; `signal posted(topic, data)` is what listeners connect to,
      filtering by `topic`.

    Topics (a payload key listed is a promise; "tests" = read only by tests):
    - `&"hit"`: the Projectile System posts one per damaging hit, the Character one per landed punch: `{ position, victim, direction,
      damage, attacker (the striking character or null), outcome, material }`, bullets also `speed_factor` and `power` (penetration
      power). `outcome`: `&"blocked"` / `&"penetrate"` / `&"ricochet"` (bullets), `&"punch"` (fist or kick), `&"blast"` (a frag's blast,
      posted by `Explosion` with the thrower as `attacker`, `speed_factor` 0; Audio does not voice it as an impact: the burst has its own
      sound). `material`: the struck surface's (`""` for a wall; for a round armour stopped, the armour's `metal` / `ceramic` /
      `composite` / `fabric`; for one through it, the flesh). `damage` is the striker's, before the zone, blunt and reduction scaling
      (`docs/outfits.md`). The AI consumes it (combat awareness, hostility, gunfire heard farther off). A shot that flies over cover posts
      nothing.
    - Grenades (`docs/grenades.md`): `&"throw"` (Items, `GrenadeItem` as it leaves the hand: `{ position, kind, attacker }`, tests),
      `&"grenade"` (Items, `ThrownGrenade`: `{ position, kind, stage }`, stage `bounce` / `rest`), `&"explosion"` (`Explosion.frag` /
      `Explosion.stun` post it first, before the burst's hits and stuns: `{ position, kind (&"frag" / &"stun"), attacker (thrower or
      null), radius (a frag's blast, a stun's flash) }`), `&"stun"` (Character `take_stun`: `{ character, position, blind, deaf }`).
      Audio voices `throw` (`throw/<kind>`), a `grenade` `bounce` (`grenade/<kind>/<floor>`, the floor from `SoundSurface.at`; a `rest` is
      silent) and the `explosion`, and of the `stun` only a deafening of its `focus` (interface 18). The camera shakes on `explosion` (by
      distance and kind); the AI hears where a grenade comes down from `bounce` / `rest`; the UI's `StunScreen` freezes the flash frame
      on the human's own `stun`.
    - `&"shot"`: a gun (Items) posts one per round leaving the barrel: `{ position (muzzle), gun, attacker (tests), power }`. Audio voices
      it; Lighting lights a muzzle flash (as it lights a burst on `&"explosion"`).
    - `&"footfall"`: `CharacterFootsteps` posts one per landed foot: `{ position, foot (0 left / 1 right), speed, running, character,
      crouched }`. Audio voices it; the AI hears it (`docs/hearing.md` H1: a stranger's steps through walls, range set by
      `running` / `crouched`).
    - `&"reload"`: `Character` posts one at the start (`stage = &"start"`) and one at the finish (`&"done"`, never after a cancelled
      reload): `{ position (weapon hand), gun, stage, power, character (tests) }`.
    - `&"sound"`: Audio's `Sound` posts one per sound it accepts: `{ kind, profile, variant, position, volume_db, pitch }`; what tests
      assert on.
    - `&"vehicle"`, `&"engine"`, `&"skid"` (Vehicles). `&"vehicle"`: `{ position, kind (&"car" / &"van"), stage }`, stage `ignition`
      (a driver sat down), `door_open` / `slide_open` (at the handle), `door_close` / `slide_close`, `crash` (a new impact above
      `VehicleCollisionConfig.crash_min_speed` on anything but a character, + `speed` and `material` = the struck
      `get_surface().material`, `""` for a wall) or `bump_character` (+ `speed`). `&"engine"`: `{ vehicle, kind, stage }`, `start` /
      `stop`. `&"skid"`: `{ vehicle, stage }`, `start` / `stop`. Audio voices the one-shots and keeps one looping voice per vehicle for
      engine and skid, following it each frame through `engine_state()`, `slip()` and `speed()` read duck-typed off the event's
      `vehicle` (the `Sound.focus` pattern, interface 18), so it stays a leaf.
    - `&"door"`: a house door (Objects, 24) posts one per stage: `{ position (its doorway's middle), door (tests), material (`hollow` /
      `solid` / `steel` / `glass`), stage }`: `open` (a swing to open begins; a run of scroll notches posts one), `shut`, `burst` (the
      latch gave, or an ajar door was thrown open), `down` (it fell) or `glass` (the panes shattered). Audio voices `open` / `shut` as
      `leaf/latch`, `burst` as `leaf/burst`, `down` as `leaf/<material>/down`, `glass` as `leaf/glass/glass` (`docs/doors.md` DR12).
    - `&"callout"`: an AI controller's team radio, posted when it adopts a combat or investigation decision and once per step of a
      tactical entry. Header `{ speaker, faction, position, status, path, label, target_id, point }`; a combat decision adds `target_pos`
      (the hostile's last-known spot as the speaker knows it, else where shots at it came from, `Vector2.INF` for neither; an ally reads
      it as a fight in that room, `docs/grenades.md` G18), an investigation `lead_pos` (the freshest lead placing a hostile, `Vector2.INF`
      for none; allies' perception ignores it, the squad's ambush rule reads it, `docs/leadership.md` LD29). Allied AI controllers
      within `tuning.radio.callout_range` consume it (flanks held, who fights whom, support, stack slots, which room is clear, which
      doorway is covered, when the team moves on, which grenade to get clear of).
      - *Entry steps* add the claim fields of `StackClaim.DEFAULTS` (`ai/perception/stack/stack_claim.gd`, each field commented
        there; `docs/tactical-entry.md`, `docs/leadership.md` LD9 to LD25). Encoded and decoded only by `StackClaim.encode` /
        `StackClaim.decode`: the NPC radio (`npc_comms.gd` `post_entry_call`), `PlayerStack` and every reader of a stack go through them,
        and no reader takes a claim key off a raw callout. `entry_step`: claim / ready / bang / going_in / in / clear / cover / rear /
        done / abort.
      - A human invader's `PlayerStack` (interface 17) posts the same steps as a full claim (E16): `human: true` (no AI moves up into its
        slot), `leader` (true while it leads its squad: a stack it ordered waits for it, LD17), `own` (its own claim at a doorway nobody
        stacks at, which the squad rallies to, LD24; false for a slot reserved in an allied stack).
      - A live grenade has its own statuses, read by an ally in range as "a grenade is down there", not as what the speaker is doing:
        `status = "grenade"` (an NPC that saw or heard one come down in its danger zone: `point` the landing, `kind` `&"frag"` /
        `&"stun"`; repeated once if it comes to rest 30 px or more away), `"frag_out"` / `"bang_out"` (the thrower, `point` the landing;
        G16, G17, and a frag entry its leader ordered, LD14).
      - A member carrying out an order (LD7) radios progress with `order_id` and `order_step` (`moving` / `in_position` / `done` /
        `refused`); allies leave such a call out of what they weigh, its squad (interface 21) keeps it as the member's latest step.
    - `&"order"`: a squad (`ai/team/squad.gd`, interface 21) posts one per order its leader gives: `{ id, leader, faction, to (recipient
      characters), kind (defend_room / stack / go / ambush / cancel), frame (the `GameClock` frame it was issued on) }` plus kind-specific
      keys (`room`, `opening`, `into`, `stack_at`, `split`, `mode`, `bang`, `wait_go`, `beyond`, `auto`, `pos`); the key set and the
      resolution rules are `docs/leadership.md` LD5, LD9, LD13, LD14, LD24 (`join`). Range is unlimited: every AI controller named in
      `to` of the same faction takes it and holds it until done, cancelled or replaced (never on a timer). Besides its leader's orders a
      squad posts its own (rally joins, `go`, `cancel`, the defenders' ambush: interface 21).
    - `&"leader"`: a squad posts it when its leader dies and the next in line leads: `{ faction, leader, previous }` (`leader` null when
      nobody is left). Tests read it only.
    - `&"death"`: `Character._die` posts `{ character, position }` (fading overhangs listen).
