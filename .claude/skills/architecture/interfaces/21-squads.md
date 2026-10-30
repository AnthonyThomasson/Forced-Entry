21. **Main / Testing (through `MatchBuilder`) → AI team: the squads, their leaders and their orders** (`scenes/ai/team/squad.gd`; spec
    `docs/leadership.md`)
    - The match builder builds one `Squad` (a `Node`) per side after arming the characters (`MatchBuilder.build_squads`, interface 23: under
      Main's `World` in every match, under a test world for a declared match or declared squads):
      `Squad.setup(roster: SquadRoster, openings, rooms)` (`SquadRoster`, `ai/team/squad_roster.gd`: `faction`; `members` the side's characters in
      spawn order; `human` when the human leads, else null; `claim_ttl` how long the side's NPCs keep a callout they heard, their `tuning.radio.callout_ttl`, read by `MatchBuilder.callout_ttl_of(members)`
      off each one's controller (interface 7): the squad keeps a member's entry claim as long), and hands each member its own through
      `MatchBuilder.bind_squad(member, squad, stack := null, own_claims := false)` (beside `bind_npc`: the controller's `squad`, found by the
      same contract, and the human's `PlayerStack.squad` through `stack`, the node `bind_player` returned, interface 17, with its `own_claims`,
      true for the invaders' side only, D29). The squad reads its members only through the
      Character API (`wardrobe.rank`, `is_dead`, the `died` signal, `global_position`, and the leader's `facing`; a member is an NPC, one that may
      follow, when a child of it is in the group `npc_controllers` at `setup`, interface 7) and lays its stacks and its follow spots on the
      navigation map and physics space of its own viewport's `World2D` (`NavBuilder.snap`, interface 9; a wall ray for the leader's sight).
      Every squad coordinates, with no switch (`docs/leadership.md` LD3, LD19 to LD26); the roster's `ambush_attacks` (below) is the one
      per-side flag.
    - Reads: `leader() -> Node` (LD3: the human when it leads; else the highest `wardrobe.rank`, the first in spawn order among equals, so the invaders'
      unit lead and the defenders' first spawned), `members() -> Array`, `alive(member) -> bool`, and `view() -> Dictionary`
      (`{ leader, members: [{ node, order, step, held, follow_spot }], stacks, trail, leash }`: the order each member holds, the posted dict or {} (a held stack a `go` released
      carries `go: true`), its latest `order_step` and `held` (its order is a stack that waits for the leader's go and no go has released yet,
      LD13: the one rule the UI reads instead of working it out; released by the squad's own `go`, or by one read off the claims,
      `DoorStack.released(order_id, into, since)`, `since` the order's `frame`, `order_id` "" for a join of the human leader's rally (D31): a claim under that order says `order_go`, or a member of that
      stack, under the order or the human, is crossing or through into the order's room, the human on a crossing begun since (its
      `crossed_frame` at or after `since`; -1 on either releases nothing); for a join of the rally, a joiner of it (its `order_frame` `since`)
      saying `order_go` or crossing, or the human crossing on a crossing begun since (D14: the human leader stepping in is its go; a claim left from
      an earlier entry through the doorway releases nothing), latched once heard as each member latches its own); an order radioed `done` is no longer held, {} with the
      step `done`, while a `refused` one is; `stacks` every stack the side is forming, ordered or its own, read off the side's entry claims
      through the squad's own `ClaimLedger` (unlimited range: the side's whole view; `claim_ttl`) and laid by each doorway's `DoorStack.layout`,
      `[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]` (LD18: slots 1 to the last claimed, each where
      the AI stands it; `holder` the instance id, 0 free; `there` its holder in it; `mine` the human's; `row` 1 against the wall, 2 a step out),
      from a stack's first claim until everyone in it is through; `follow_spot` the member's `follow_spot`, `trail` the leader's trail
      (`Array` of points, oldest first) and `leash` (px), LD28), what observers draw.
    - Following reads (LD19 to LD23): `follows(member) -> bool` (alive, the squad has a leader, not the leader, an NPC), `follow_spot(member)
      -> Vector2` (the spot it keeps to now, `Vector2.INF` when it does not follow: on the leader's trail while it moves, a ring slot behind
      it once it has stood `SquadFollowConfig.still_time`, out of the leader's way), and the tunables the AI reads, the static holder
      `SquadFollowConfig` (`ai/team/squad_follow_config.gd`, the same for every squad): `gap` (55), `step` (45), `caught_up` (20), `ring` (80),
      `still_time` (0.8 s), `retarget` (20), `arrive` (10), `leash` (320) and `leash_break` (1.3). The squad keeps the leader's trail every
      physics frame and lays the spots through its `SquadFollow` (`ai/team/squad_follow.gd`, the team module's own, which reads the holder,
      `leader()`, `members()`, `alive` and `follows` off the squad). The controller (its reflexes part, `npc_reflexes.gd`) reads `follows`,
      `leader()` and the holder's `leash` and `leash_break`; the behaviour's `follow` primitive `follow_spot` and the
      follow tunables, and faces away from the leash centre the controller pushes (its leader's live position), reading no `leader()`.
    - `Squad.issue(request) -> Dictionary`: a leader's request in plain terms (`{ kind, to: [characters], pos?, room?, bang?, mode?, wait_go? }`:
      no `to` = every living member but the leader; a stack's `mode` one of `Squad.MODES`, `quiet` / `stun` / `frag`; `Squad.JOIN`, `join`, is
      not one of them: only the squad's own rally posts it, and `StackClaim.is_join(order)` tells such an order) resolved into the AI's (a room key, or the room under `pos`; for a stack or an ambush the
      doorway nearest `pos` within its width, a stack's `into` the room on the far side of the wall plane from `pos`, an exterior door's house
      room, and `stack_at` = `pos` or `split` for a click on the opening; a stack's `mode` from the request's `mode`, else `bang` true is a
      stun; an ambush's `room` the one on `pos`'s side of the wall plane; an ambush may instead name its doorway by id and the room it is
      laid from, `{ kind: "ambush", to, opening, room }`, resolved by the same code to the order the equivalent click gives, {} for an id the
      house lacks or a room the doorway does not join) and posted as `&"order"` (interface 10); a `{ kind: "go", pos, mode? }`
      posts a `go` to every living member holding a held stack, not yet released, at the doorway nearest `pos`, whatever its `to` (D13; {}
      when none waits there), with the request's `mode` when it is one of `Squad.MODES` (the mode a held rally goes in, D31). Returns the order posted, or {}. Nothing outside the AI computes an AI id. When a leader that gave held stack
      orders dies, the squad posts their `go` itself (`auto: true`, D12).
    - `Squad.resolve(request) -> Dictionary` (read-only): the same resolution without posting, `{ room, pos }` for a `defend_room`,
      `{ opening, pos, into, split, stack_at? }` for a `stack`, `{ opening, pos }` for a `go` and `{ opening, pos, room, beyond }` for an
      `ambush` (by a click or by id; {} when it names nothing): the one rule for which doorway a click means and which room "into" (or an ambush's room) is,
      which the command menu names its stack and ambush items from.
    - On the leader's `died` the next in line leads within the frame and the squad posts `&"leader"` (interface 10, read by the tests); the orders given stand,
      but when the dead leader was the human the squad posts one `cancel` to the members holding a `defend_room`, an `ambush` or a join of its
      rally (the takeover, LD26; D31: a rally gets no automatic go). The trail starts afresh at the new leader.
    - **The rally** (LD24, LD25): on an entry claim of its leader's own (an `&"callout"` from the leader with no `order_id` and no `join`: an
      AI leader's entry, or the human's own claim through its `PlayerStack`, the one marked `own`, interface 17; a join's claims never, D30) the squad posts one `stack` order with `mode` `join` to every
      follower holding no order, once per doorway per leader, and on the leader's `abort` there a `cancel` to the members holding those joins.
      The human leader's rally is held for its go (`wait_go` true, D31): released by the human stepping in or the menu's go with its `mode`.
      The command menu never offers a join.
    - **The defenders' ambush rule** (LD29): a squad whose roster has `ambush_attacks` (`SquadRoster.ambush_attacks: bool`, false unless set;
      `MatchBuilder.build_squads` sets it for the defenders' side only, interface 23) runs, while an AI leads it, the only orders of a kind the
      human gives that it posts of its own: on a callout of its side (the leader's own included) placing a threat outside the leader's room (a
      COMBAT callout's `target_pos`, an INVESTIGATE callout's `lead_pos`, interface 10; nothing for a leader in no room) it issues
      `{ kind: "ambush", to, opening, room }`, the attack doorway (the last doorway on the shortest way from the threat's room into the
      leader's, over `WorldGen.get_rooms` / `get_openings`, interface 1) from the leader's room, `to` the living NPC members holding no order
      (or holding one they radioed `refused`) in spawn order, the leader included, with three or more the last spawned non-leader left out
      (the rear guard). It re-orders only for a new doorway, at least `SquadAmbushConfig.reorder_gap` (8 s) after the last, with at least
      `SquadAmbushConfig.min_recipients` (2) recipients (`SquadAmbushConfig`, `ai/team/squad_ambush_config.gd`, a static holder); the doorway
      and the clock start afresh with a new leader, and the dead leader's ambushes stand.
    - **The human leader's command menu and order markers** (UI, `docs/leadership.md` LD10 to LD12 and LD16), in the shape of interfaces 14 and 17:
      with the setup window's "Lead the team" on (its `current_config()["lead"]`, saved by `Settings.set_setup`; a played match only, read into
      the spec's `human.lead` by `MatchBuilder.spec_from_setup`) the match builder hands the human to `Squad.setup` (a human invader is ranked
      the unit's lead, 2, by `MatchBuilder.style`) and Main's `_build_command_menu`, over the match handle's squads, builds, under `World`, the
      `CommandMenu` (`ui/command/command_menu.gd`, a `CanvasLayer`, `PROCESS_MODE_ALWAYS`): `setup({ rooms, teammates, view, resolve, leader,
      right_clear })` (the house's `WorldGen.get_rooms` dicts, the squad's members but the human, `view` and `resolve` the squad's `view()` and `resolve()`
      callables (the doorway a click is on and the room its stack goes into are the squad's `resolve`), `leader` the human: it opens only
      while the view names it the leader, `right_clear` the screen width from the right edge its panel keeps clear when docked on the right:
      Main hands it the overlay bar's `OverlayToggles.RESERVED_WIDTH` (interface 22) with Debug on, else 0, the default), `open_at(world)`, `close()`, `is_open()`, `items() -> Array`
      (`[{ label, disabled, why }]`, `why` a greyed item's tooltip, what it offers: on a teammate holding a held stack, "Go into the <room>"; on a doorway, "Go into the <room>"
      while a member holds a held stack there (for a held join of the human's rally, on either, "Go into the <room> (quiet)", "... with stun" and
      "... with frag", stun or frag greyed while no member holding it carries one, D31), the stack items quiet / with stun / with frag (the stun or frag one greyed, with a tooltip,
      while no recipient carries one, D1 / D15) and "Ambush the doorway from the <room>"; on a room, "Defend the <room>"; "Cancel order"),
      a "Hold for my go" checkbox (D19; the menu's widgets are its `Panel` child, `ui/command/command_panel.gd`), and the signals `order_requested(request)` (`{ kind: "stack", to, pos, bang, mode, wait_go }`,
      `pos` the raw click, `wait_go` the checkbox; `{ kind: "go", pos, mode? }`, `mode` a held rally's go; `{ kind: "ambush", to, pos }`; `{ kind: "defend_room", to, room }`;
      `{ kind: "cancel", to }`), which Main connects to `Squad.issue`, and
      `selection_changed(nodes)`; and the `OrderMarkers` (`ui/command/order_markers.gd`, a `Node2D` at `DrawLayers.ABOVE`): `watch(view)` (the
      squad's `view()` callable), `set_selection(nodes)` (Main connects the menu's `selection_changed` to it) and `drawn() -> Array` (test read)
      (`[{ kind, point, node, from?, label?, refused? }]`, `kind` `order` (`from` where the member stands, `label` the words at its target,
      "Stack (frag, hold) · in position", "Join stack · moving", "Ambush · moving") / `selected`). `Keybinds.COMMAND` (`"command"`, right mouse) is read by the
      menu alone, so with "Lead the team" off nothing reads the right button. Neither holds an AI reference: they read the members through the
      Character API (`global_position`, `name`, `is_dead`, `inventory.item_count`) and the squad through `view()` (and the menu `resolve()`), and the menu
      emits plain requests.
    - **The squad-leaders debug overlay** (UI, `ui/overlays/leader_overlay.gd`, LD12): the match builder builds a `LeaderOverlay` (a `Node2D`
      at `DrawLayers.ABOVE`, hidden) with the squads (`MatchBuilder.build_leader_overlay`, interface 23: under `World` in every match, under a
      test world with its declared squads or match), the match handle's `leader_overlay`: `watch(views)` (every squad's `view()`
      callable), `show_leaders` (the overlay bar's global `OverlayRegistry.LEADERS` row, off by default, set through `MatchBuilder.set_overlay`)
      and `drawn() -> Array` (test read; while shown, per squad: `{ kind: "crown", point, node }`, a crown over its living leader; `{ kind: "leash", point, radius,
      node }`, the leash ring round it; per follower with a follow spot `{ kind: "spot", point, node }` and `{ kind: "line", from, to, node }`;
      `{ kind: "trail", points }`, the leader's trail dotted, LD28). It reads the leader and the members through the Character API
      (`global_position`, `is_dead`) and the squads through `view()` only.
