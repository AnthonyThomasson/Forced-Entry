# AI · Snapshot · Wording for Von

Von is a CLASSIFIER: it picks the option whose text best matches the state. It cannot do arithmetic or compare numbers, and an encoder reads "no cover" as "cover". Every phrase here was chosen by measurement with `tools/von_probe.py` (scenarios in `tools/von_scenarios/*.json`, `--ablate` drops one fact at a time, `--capture` turns a live `gcmd ai` dump into stubs). Near-ties flip on rewording: after any change to what Von reads (a section, a desc, a tree `question`), re-run the probe over the affected scenarios and the Von game tests (`*_von_test.gd` under `tests/ai/`), and keep the old phrase when the top pick moves.

## Rules

1. **Bands, not numbers.** Distance from `punch_range` / `shoot_range` ("point-blank", "close, in pistol range", "too far to shoot"), route length (`route_buckets`), recency (`recency_bands`), health and wounds. `shoot_range` and the "in pistol range" band stay gun-agnostic (pinned wording).
2. **Canonical phrases.** The state uses the exact phrases the tree's situation descs are written in ("You have a clear shot at X from where you stand.", "You are exposed to their fire.", "You are badly wounded."), so a fact lights up the option it argues for.
3. **No negated attributes.** "In the open", "line blocked", "free", "taken by X", "unsearched".
4. **Only distinguishing facts in options.** Common facts (every hostile is hostile and armed) and the contacts section on a bind level blur the match.
5. **Only perceived facts.** Facing, aim, wounds, `reloading` and a contact's posture only while visible (a remembered posture may be stale); unknown rooms by direction.
6. **Posture words only when someone is not standing**, so a standing body's text stays byte-identical (the `tools/von_scenarios` fixtures pin it). `tests/ai/posture/posture_in_von_state_test.gd`.
7. The gun is named by `gun_noun` (display name lower-cased; an acronym like "SMG" kept), so a pistol user's text is unchanged. Room types are humanized ("kitchen_living" → "kitchen living").

## Route bands are the route walked (E18)

Every "short / medium / long route" in an option (`SnapshotOptions._route_len`) is the length of the route the NPC will walk from where it stands, `AgentDoorViews.walk_route(...)["len"]` (`perception-views.md`), not the plain one. The controller starts no decision before that route's avoid map is baked. Test: `tests/ai/entry/entry_route_band_as_walked_test.gd`.

## Suspect rooms (`docs/grenades.md` G18)

The `entries` options say why a room is suspect instead of "unexplored" / "unsearched", from `AgentSuspicion.rooms_suspected` (room key → reason ids), worded by `SnapshotOptions.SUSPECT_PHRASES`, one phrase per fact in `AgentSuspicion.ORDER`; a suspect doorway is listed first. The entry reads the same reasons through `hearing.room_suspicion` to make any entry into a suspect room a bang one (E17).

With a stun in the stack (`stack_has_stun`) no `leads` option names a fact about a room an entry doorway leads into: the lost hostile's leads, gunfire and footsteps there, the unseen-shooter lead whose `shot_from` line runs into it, an ally's support call whose `target_pos` is in it. The way into that room is an entry (ENTER / STUN ENTRY), whose option says why. Without a stun the leads are unchanged. The `leads` group also offers footsteps heard, and the awareness section says so while no hostile is known (H1).

## Grenade options (`SnapshotThrows`, `docs/grenades.md` G17)

- `grenade_throws` per target (`grenade_group`): one option per kind carried (`frag` / `stun`), only against a hostile whose last-known spot is hidden from the NPC's line of fire (`line.clear` false) or lies in a room the NPC is outside of (`_held_room`, R7), within that kind's throw range with a clear lob from the hand (`AgentThrow.can_lob`), judged per kind from where the NPC stands or else from a **throw spot** a short walk away (`ThrowSpots.throw_spot`, R13; `perception-tactics.md`). A throw spot is worked out once per decision per burst spot, reach and kept-out room (the decision's own `ctx["throw_memo"]`, `SnapshotThrows.memo_of`: it dies with the context, nothing is cleared).
- `params`: `point`, `kind`, `radius`, `slot`, `target_id`, `from` (where it throws from), `walk` (`from` is a throw spot). Tags: `ally_in_blast` (a known ally in the danger zone at the spot), `no_safe_spot` (the NPC itself, standing at `from`, finds no safe spot within the fuse), which the tree's `grenade` node drops by; `inside`. `debug_zones()` lists every throw weighed, dropped ones too.
- The throw spot's walk words ("from the hallway to the east, short route") and the summary "within throwing range from a spot nearby" move GRENADE by 0.02 at most (measured).
- Global `shots_grenade_group` (R10): with no hostile known and under fire, a throw per kind onto the stretch of a `shot_from` line (`AgentSuspicion.shot_line`) inside the first room along it the NPC is outside of; from where it stands, else (R15) from a throw spot outside that room. Its `situation` reads "The shots came from a room you are outside of". `grenade_ready` holds for either group.
- The exposure section says "You can throw a frag grenade onto their spot." for the options not dropped, and "X is blinded by a flash and cannot see you." for a hostile a stun caught (`blind` on the contact, from `grenades.process_explosion`). A blinded hostile has no `aim_text`; the `hostiles` bind carries `blinded`, the clause the ADVANCE desc's `{blinded}` is filled with (`decision.md`).
- The GRENADE desc needs both halves together: the "Your line to X is blocked and you can throw a grenade onto their spot" desc and the exposure sentence. Either alone leaves ENGAGE ahead.
