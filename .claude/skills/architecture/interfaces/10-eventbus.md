10. **Any domain ↔ General (EventBus)** — a generic decoupled notification bus (General autoload).
    - `EventBus.post(topic: StringName, data: Dictionary)` — broadcast an event.
    - `signal posted(topic, data)` — listeners connect and filter by `topic`.
    These topics are in use:
    - `&"hit"`: the Projectile System posts one per damaging hit and the Character one per landed
      punch (`{ position, victim, direction, damage, attacker }`; `attacker` = the striking
      character or null). The AI controller consumes it for combat awareness, hostility ("attacked
      me") and gunfire heard farther off. It also says *how* the
      hit met the surface, for the Audio domain: `outcome` (`&"blocked"` / `&"penetrate"` /
      `&"ricochet"` for a bullet, `&"punch"` for a fist or a kick, `&"blast"` for a frag's blast: posted by the Projectile System's
      `Explosion` with the thrower as `attacker` and `speed_factor` 0, which Audio does not voice as an impact: the burst has its own sound), `material` (the struck surface's, `""` for a
      wall; for a round armour stopped, the armour's: `metal`, `ceramic`, `composite`, `fabric`; for one through it, the flesh under it), and for bullets
      `speed_factor` and `power` (its penetration power). Its `damage` is the striker's, before the struck character's zone, blunt and reduction
      scaling (`docs/outfits.md`; the same for `hit_landed` / `report_shot`). A shot that flies over cover posts nothing.
    - `&"explosion"`: `Explosion.frag` / `Explosion.stun` (Projectile System) post one when a grenade goes off (`{ position, kind` (`&"frag"` / `&"stun"`)`,
      attacker` (the thrower, or null)`, radius` (the blast radius of a frag, the flash radius of a stun)` }`), before the burst's hits and stuns, for
      Audio (`explosion/<kind>`), the camera (General: `Camera2D.offset` shake by distance and kind) and the AI (`docs/grenades.md`). The grenade's other topics: `&"throw"` (Items, the `GrenadeItem` as it leaves the hand: `{ position, kind, attacker` (read by the tests)` }`), `&"grenade"` (Items, `ThrownGrenade`:
      `{ position, kind, stage }` with stage `bounce` / `rest`) and `&"stun"` (Character, `take_stun`: `{ character, position, blind, deaf }`). Audio voices the
      `throw` (`throw/<kind>`), a `grenade` `bounce` (`grenade/<kind>/<floor>`, the floor from `SoundSurface.at`; a `rest` is silent) and the `explosion`, and of the `stun`
      only a deafening of its `focus` (interface 18); the AI hears where a grenade comes down from its `bounce` / `rest`, and the UI's `StunScreen` reads the human's own `stun` event to freeze the frame of the flash.
    - `&"shot"`: a gun (Items) posts one per round that leaves the barrel (`{ position` (the
      muzzle)`, gun, attacker` (read by the tests)`, power }`). Audio voices it and the Lighting domain lights a muzzle flash (as it lights a burst on an
      `&"explosion"`).
    - `&"footfall"`: `CharacterFootsteps` posts one each time a foot lands (`{ position` (the sole)`,
      foot` (0 left / 1 right)`, speed, running, character` (the walker)`, crouched }`). Audio voices it; the AI hears it
      (`docs/hearing.md` H1: a stranger's steps through walls, out to a range set by `running` / `crouched`).
    - `&"reload"`: `Character` posts one when a reload starts (`stage = &"start"`) and one when it finishes
      (`&"done"`, never after a cancelled one): `{ position` (weapon hand)`, gun, stage, power, character` (read by the tests)` }`.
    - `&"sound"`: the Audio domain's `Sound` service posts one for every sound it accepts (`{ kind,
      profile, variant, position, volume_db, pitch }`), which is what tests assert on.
    - `&"callout"`: an AI controller posts one when it adopts a combat or investigation decision —
      its team radio (`{ speaker, faction, position, status, path, label, target_id, point }`, and with a combat decision `target_pos`:
      the hostile's last-known spot as the speaker knows it, else where the shots at it came from, `Vector2.INF` when it knows neither;
      an ally reads it as a fight in that room, `docs/grenades.md` G18) — and one
      per step of a tactical entry, which adds `opening`, `into` (the room it leads into), `slot`, `side` (the side of the door it stacks on: a stack split across the door, E19, has both), `entry_step` (claim / ready / bang /
      going_in / in / clear / cover / rear / done / abort), `bang` (this member goes in with a stun thrown first), `bang_off` (it gave the bang up: the stack goes in quietly), `stuns` and `frags` (how many stun / frag grenades it carries), `cleared_room` (with a clear) and `covering` (with a cover:
      the doorway on out of the cleared room it watches), `claim_frame` / `claim_pos` (the `GameClock` frame its slot was claimed on and
      where it stood then, kept by every repeat of that claim: two claims on one slot made on the same frame settle by distance, E2),
      `move_up` (the slot it moved up from, while it walks into the lower one it took; 0 otherwise, E2), `pie` (it has begun slicing the
      pie: nobody moves up behind it) and `crossed_frame` (the `GameClock` frame its crossing began on, its step reaching `going_in` or a
      through step, -1 before it: an NPC's first, the human's latest, D14) (`docs/tactical-entry.md`), and from a member of a stack its leader ordered
      `order_id`, `order_bang` (a grenade first), `order_mode` (`quiet` / `stun` / `frag`, LD14), `order_hold` (the order holds the stack
      for the leader's go, LD13), `order_go` (that go has come), `order_side` (the side of the door the order names, 1 / -1 along its
      wall, 0 for a split stack) and `order_frame` (the order's `frame`, -1 unknown): a stack with such a claim goes in the order's way (`docs/leadership.md` LD9), and from a member of a join
      (the squad's rally, LD24) `join: true` (its claims are never its own, D30); a human invader's `PlayerStack`
      (interface 17) posts the same entry steps for the human as a full claim (E16: every field above, `claim_frame` / `claim_pos` stamped
      on each new claim and kept by its repeats, `crossed_frame` restamped each time its step goes from `claim` / `ready` to `going_in` /
      `in`, `bang: true` and `bang_off: false` (it never holds a stack back nor turns it), `stuns: 0` /
      `frags: 0` (it throws nothing for the stack), `move_up: 0`, `pie: false`), with `human: true` (no AI moves up into its slot), `leader`
      (true while the human leads its squad: a stack it ordered waits for it, LD17) and `own` (true for the human's own claim at a doorway
      nobody stacks at, which the squad rallies the team to, LD24; false for a slot it is reserved in an allied stack, E16). These entry
      fields are encoded by one function and decoded by one, `StackClaim.encode` / `StackClaim.decode`
      (`ai/perception/stack/stack_claim.gd`, each field's default in its `DEFAULTS`): the NPC controller's radio (`npc_comms.gd` `post_entry_call`), the
      `PlayerStack` and every reader of a stack go through them, and no reader takes a claim key off a raw callout. A live grenade has its own statuses, which an ally in range reads as "a
      grenade is down there" and not as what the speaker is doing: `status = "grenade"` (an NPC that saw or heard a grenade come down and
      is in its danger zone: `point` the spot it landed, `kind` `&"frag"` / `&"stun"`; the NPC repeats it once if the grenade then comes to rest
      30 px or more away), `"frag_out"` / `"bang_out"` (the thrower of a frag or a stun, `point` the landing; the GRENADE tactic's call, G17, and `frag_out` from the
      thrower of a frag entry its leader ordered, LD14), all
      from `docs/grenades.md` G16. Allied AI
      controllers within their `tuning.radio.callout_range` consume it (which flank an ally holds, whom it fights, where to
      support it, which stack slot is taken, when the point is through, which room is clear, which doorway on is
      covered, when the team moves on, which grenade to get clear of). A member carrying out an order (`docs/leadership.md` LD7) radios its
      progress as a callout with `order_id` (the order's `id`) and `order_step` (`moving` / `in_position` / `done` / `refused`); allies leave
      such a call out of what they weigh, and its squad (interface 21) keeps it as that member's latest step.
    - `&"order"`: a squad (`ai/team/squad.gd`, interface 21) posts one per order its leader gives (`docs/leadership.md` LD5):
      `{ id, leader, faction, to` (the recipients, characters)`, kind` (`defend_room` / `stack` / `go` / `ambush` / `cancel`)`, room?`
      (`defend_room`: the room key; `ambush`: the room it lies in wait in, on the click's side of the doorway's wall, D17)`, opening?, into?,
      stack_at?, split?, mode?, bang?, wait_go?` (`stack`: the doorway's id, the room it goes into, the click the stack's side is read from
      or a split stack, `mode` `quiet` / `stun` / `frag` (LD14) or `join` (the squad's own rally on its leader's own entry claim, to the
      followers holding no order, LD24: no side or mode pinned, the member's own entry joining the leader's stack) with `bang` true for
      `stun` and `frag`, and `wait_go`, the stack holds at
      its slots for the leader's go, LD13)`, beyond?` (`ambush`: the room the doorway leads into from its `room`, "" for an exterior door)`,
      auto?` (`go`: the squad's own release of the held stacks of a leader that died, D12; read by the tests)`, pos?` (`defend_room` / `stack` / `ambush` /
      `go`: the target point, the room's centre or the doorway's, which the UI's order markers draw)`, frame }` (the `GameClock` frame it
      was issued on, on every order: a held stack takes the human's crossing as its go only from then on, D14). A `go` (`opening`, `pos`) goes
      to the living members holding a held stack at that doorway and replaces nothing: it releases their order (latched, D13). Range is
      unlimited: every AI controller named in `to` of the same faction takes it, and it holds it until it is done, cancelled or replaced
      (never on a timer); an `ambush` is done on first contact (a hostile seen or shots at the member, D18). Besides its leader's orders a
      squad posts its own: the rally's `join` stacks, a `cancel` of them when its leader radios `abort` at that doorway (LD25), and a `cancel`
      to the members holding a `defend_room` or `ambush` when the human leader dies (LD26).
    - `&"leader"`: a squad posts one when its leader dies and the next in line leads (`docs/leadership.md` LD4): `{ faction, leader, previous }`
      (`leader` null when nobody is left). Read by the tests: no game code listens to it.
    - `&"vehicle"`, `&"engine"`, `&"skid"`: a vehicle (Vehicles) posts `&"vehicle"` `{ position, kind` (`&"car"` / `&"van"`)`, stage }` with
      stage `ignition` (a driver sat down; the vehicle's centre), `door_open` / `slide_open` (a shut door starts to open; at its handle),
      `door_close` / `slide_close` (the frame it shuts), `crash` (a new impact above `VehicleCollisionConfig.crash_min_speed` on anything but a
      character, + `speed` (the closing speed) and `material` (the struck `get_surface().material`, `""` for a wall)) or `bump_character`
      (a character struck, + `speed`); `&"engine"` `{ vehicle, kind, stage }` `start` / `stop`; `&"skid"` `{ vehicle, stage }` `start` /
      `stop` (the tyres begin / stop sliding). Audio voices the one-shots and keeps one looping voice per vehicle for its `engine` and its
      `skid`, following the vehicle each frame through `engine_state()`, `slip()` and `speed()` read duck-typed off the event's `vehicle`
      (the `Sound.focus` pattern, interface 18), so it stays a leaf.
    Emitters and listeners never reference each other (like `Despawner`).
