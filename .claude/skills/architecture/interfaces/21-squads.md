21. **Main / Testing (through `MatchBuilder`) → AI team: the squads, their leaders and their orders** (`scenes/ai/team/squad.gd`; spec
    `docs/leadership.md`, rules LD / D; implementation `domain-ai` (side file team), the UI `domain-ui` (side file command))
    - **Build:** `MatchBuilder.build_squads` (23) makes one `Squad` per side after arming: `Squad.setup(roster: SquadRoster, openings,
      rooms)`. `SquadRoster` (`ai/team/squad_roster.gd`): `faction`; `members` in spawn order; `human` when the human leads, else null;
      `claim_ttl` (the side's `tuning.radio.callout_ttl`, `MatchBuilder.callout_ttl_of(members)`,
      7); `ambush_attacks` (below). Each member gets its squad through `MatchBuilder.bind_squad(member, squad, stack := null, own_claims :=
      false)`: the controller's `squad`, and the human's `PlayerStack.squad` through `stack` (17), `own_claims` true for the invaders only
      (D29). The squad reads members only through the Character API (`wardrobe.rank`, `is_dead`, `died`, `global_position`, the leader's
      `facing`; an NPC = a child in the group `npc_controllers` at `setup`) and lays stacks and spots on the nav map and physics space of
      its own viewport's `World2D` (`NavBuilder.snap`, 9). 
    - **Reads:**
      - `leader() -> Node` (LD3: the human when it leads, else the highest `wardrobe.rank`), `members() -> Array`, `alive(member) -> bool`.
      - `view() -> Dictionary` is what observers draw: `{ leader, members: [{ node, order, step, held, follow_spot }], stacks, trail, leash
        }`. `order` is the posted dict or {} (`go: true` on a held stack a go released); `step` its latest `order_step` (`done` with {}
        once done; `refused` stays); `held` is true while its order is a stack waiting for the leader's go (LD13, the one rule the UI
        reads; released by the squad's `go` or read off the claims by `DoorStack.released(order_id, into, since)`, D13 / D14 / D38).
        `stacks` is every stack the side forms, read off its entry claims through the squad's own `ClaimLedger` (unlimited range) and laid
        by each doorway's `DoorStack.layout`: `[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]`
        (LD18; `holder` an instance id, 0 free; `row` 1 against the wall, 2 a step out), from a stack's first claim until everyone is
        through. `trail` is the leader's trail (points, oldest first), `leash` px (LD28).
    - **Following** (LD19 to LD23): `follows(member) -> bool` (alive, a leader exists, not the leader, an NPC), `follow_spot(member) ->
      Vector2` (`Vector2.INF` when it does not follow: on the leader's trail while it moves, a ring slot once the leader stood
      `SquadFollowConfig.still_time`). `SquadFollowConfig` (`ai/team/squad_follow_config.gd`, static holder, all squads; the follow
      distances, `leash`, `leash_break`). The squad lays spots through its `SquadFollow` (`squad_follow.gd`); the controller's
      `npc_reflexes.gd` reads `follows` / `leader()` / the leash, the `follow` primitive `follow_spot`.
    - **`Squad.issue(request) -> Dictionary`:** a leader's request `{ kind, to: [characters], pos?, room?, bang?, mode?, wait_go? }` (no
      `to` = every living member but the leader; `mode` one of `Squad.MODES` `quiet` / `stun` / `frag`; `Squad.JOIN` is posted only by the
      squad's rally, `StackClaim.is_join(order)` tells it) resolved into the AI's order and posted as `&"order"` (10). Returns the order,
      or {}.
      - `defend_room`: a room key, or the room under `pos`.
      - `stack`: the doorway nearest `pos`; `into` the room across the wall plane from `pos`; `stack_at` = `pos` or `split`; `mode` from
        the request, else `bang` true = stun.
      - `ambush`: the same doorway; `room` the one on `pos`'s side; or named by `{ kind: "ambush", to, opening, room }` (`{}` for an
        unknown id or a room the doorway does not join).
      - `{ kind: "go", pos, mode? }` posts a `go` to every living member holding an unreleased held stack at the doorway nearest `pos`,
        whatever its `to` (D13; {} when none waits), with `mode` when one of `Squad.MODES` (a held rally's mode, D38). When a leader who
        gave held stacks dies, the squad posts their `go` itself (`auto: true`, D12).
    - **`Squad.resolve(request) -> Dictionary`** (read-only): the same resolution without posting: `{ room, pos }` for `defend_room`, `{
      opening, pos, into, split, stack_at? }` for `stack`, `{ opening, pos }` for `go`, `{ opening, pos, room, beyond }` for `ambush`; {}
      when it names nothing. The one rule for which doorway a click means; the command menu uses it.
    - **Leader change:** on the leader's `died` the next in line leads within the frame and the squad posts `&"leader"` (10); orders stand,
      except that a dead human leader's `defend_room`, `ambush` and rally joins get one `cancel` (LD26, D38).
    - **The rally** (LD24, LD25): on an entry claim of the leader's own (an `&"callout"` from the leader with no `order_id` and no `join`:
      an AI leader's entry, or the human's own `own` claim through `PlayerStack`, 17) the squad posts one `stack` order with `mode` `join`
      to every follower holding no order, once per doorway per leader; on the leader's `abort` there, a `cancel` to those joins. The human
      leader's rally is held (`wait_go`, D38) until the human steps in or the menu's go. The menu never offers a join.
    - **Defenders' ambush rule** (LD29): with `SquadRoster.ambush_attacks` (set for the defenders' side only, 23) an AI-led squad issues `{
      kind: "ambush", to, opening, room }` of its own on a callout of its side that places a threat outside the leader's room (a COMBAT
      callout's `target_pos`, an INVESTIGATE callout's `lead_pos`, 10). It re-orders only for a new doorway, at least
      `SquadAmbushConfig.reorder_gap` after the last, with at least `SquadAmbushConfig.min_recipients` recipients
      (`ai/team/squad_ambush_config.gd`, static holder). Doorway and recipients: LD29.
    - **UI (14, 17 shape; no AI reference, only the Character API and `view()` / `resolve()`).** With the setup window's "Lead the team" on
      (`current_config()["lead"]`, saved by `Settings.set_setup`; played matches only; read into the spec's `human.lead` by
      `MatchBuilder.spec_from_setup`) the builder hands the human to `Squad.setup` (ranked lead by `MatchBuilder.style`) and Main's
      `_build_command_menu` builds under `World` the `CommandMenu` (`ui/command/command_menu.gd`, `CanvasLayer`): `setup({ rooms,
      teammates, view, resolve, leader, right_clear })` (`rooms` = `WorldGen.get_rooms`; `view` / `resolve` the squad's callables; it opens
      only while the view names `leader` the leader; `right_clear` = the overlay bar's `RESERVED_WIDTH`, else 0), `open_at(world)`,
      `close()`, `is_open()`, `items() -> Array` (`[{ label, disabled, why }]`; LD11 / LD16), a "Hold for my go" checkbox (D19; widgets in
      `command_panel.gd`). Signals `order_requested(request)` (`{ kind: "stack", to, pos, bang, mode, wait_go }`, `{ kind: "go", pos, mode?
      }`, `{ kind: "ambush", to, pos }`, `{ kind: "defend_room", to, room }`, `{ kind: "cancel", to }`; Main connects it to `Squad.issue`)
      and `selection_changed(nodes)`. `Keybinds.COMMAND` (right mouse) is read by the menu alone. `OrderMarkers`
      (`ui/command/order_markers.gd`): `watch(view)`, `set_selection(nodes)` (Main connects the menu's `selection_changed`), `drawn() ->
      Array` (test read): `[{ kind, point, node, from?, label?, refused? }]`, `kind` `order` / `selected`.
    - **Squad-leaders overlay** (`ui/overlays/leader_overlay.gd`, LD12): `MatchBuilder.build_leader_overlay` (23) builds a hidden
      `LeaderOverlay` over the squads, the handle's `leader_overlay`: `watch(views)` (every squad's `view()` callable), `show_leaders` (the
      global `OverlayRegistry.LEADERS` row, off by default, set through `MatchBuilder.set_overlay`), `drawn() -> Array` (test read; `{
      kind, ... }` of `crown`, `leash` (`radius`), `spot`, `line` (`from`, `to`) and `trail` (`points`), LD28).
