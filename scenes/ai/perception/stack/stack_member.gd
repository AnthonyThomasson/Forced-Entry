extends RefCounted
## AI PERCEPTION sub-domain — STACK · one member's own claim in a doorway's stack
## (`docs/tactical-entry.md` E2, E16, E19 to E22): the claim a member keeps of itself, which it
## never hears on the radio, and the one way it claims, keeps and settles its slot against the
## doorway's `DoorStack`. The NPC's entry (`behavior/entry/`, on its `state`) and the human's
## `PlayerStack` (`ai/team/`) each own one; the snapshot's slot guess builds a transient one.
##
## Claim, keep, settle: `begin` starts a claim from where the member stands (its frame and spot,
## E2), `slot_in` is the slot the stack gives it now, the caller weighs the side it asks for when
## `weighs_side` says it must and hands it in (`ask`), and `claim` takes the slot, the side and the
## point the stack settles it on (`DoorStack.claim`); `settle` reads where its slot stands without
## claiming again. The side rule is one for every member: on its claim it weighs its side; after
## that the point (slot 1) never weighs it again, and any other member only when the side the
## team stacks on changed (E19).
##
## `me()` is the member as a `DoorStack` reads one asking about itself, in the radio's field names
## (`StackClaim.DEFAULTS`: `claim_frame` / `claim_pos`, the order's `order_*`), built here alone.
## Preloaded, no `class_name`; it holds nothing but its own claim.

## Its instance id.
var id := 0
## Its slot (1 = the point; 0 while it is claiming).
var slot := 0
## The side its slot stands on (1 / -1 along the wall): `want`, or the other while that side's
## wall is full (E21).
var side := 0
## The side it asks for (the team's, the order's, its own on a split stack, E19).
var want := 0
## The side the team stacked on when it last weighed its own (a change is weighed again, E19).
var team_side := 0
## The `GameClock` frame its slot was claimed on and where it stood then (E2: same-frame claims
## settle by distance), kept by every repeat of the claim.
var claim_frame := -1
var claim_pos := Vector2.INF
## The slot it moved up from while it walks into the one it took (E2), else 0.
var move_up := 0
## Its latest radio step (claim / ready / bang / going_in / in / ...).
var step := ""
## Its place in its side's file (1 = nearest the door) and the point its slot stands on
## (`Vector2.INF` for a slot a dead end does not hold), as last settled.
var place := 0
var point := Vector2.INF
## The frame its latest crossing began on (-1 before it, D14).
var crossed_frame := -1
## The rest of what its claim says of it, by the radio's field names: the room it goes into
## (`into`), the grenades it carries for the stack (`stuns`, `frags`), the order it stacks under
## (`order_id`, `order_bang`, `order_mode`, `order_hold`, `order_go`, `order_side`,
## `order_frame`), a join's (`join`), the human's (`human`, `leader`, `own`). A key left out says
## its default (`StackClaim.DEFAULTS`).
var terms := {}
## It has weighed its side on this claim.
var _asked := false


## Start a new claim, made on frame `frame` by a member standing at `at`: no slot yet, no side asked
## (its terms are kept).
func begin(frame: int, at: Vector2) -> void:
	slot = 0
	side = 0
	want = 0
	team_side = 0
	claim_frame = frame
	claim_pos = at
	move_up = 0
	step = "claim"
	place = 0
	point = Vector2.INF
	crossed_frame = -1
	_asked = false


## Give the claim up: every field back to none, its terms too.
func clear() -> void:
	begin(-1, Vector2.INF)
	step = ""
	terms = {}


## The slot `stack` (a `DoorStack`) gives this member now (`DoorStack.slot_for`): its own while it
## keeps it, else the next free one (E2).
func slot_in(stack: RefCounted) -> int:
	return stack.slot_for(me())


## Whether the side this member asks for must be weighed (again) for slot `n`, the team stacking on
## `now` (`DoorStack.team_side`): on its claim; after that never for the point (slot 1), and for
## any other slot only when the team's side changed since it last weighed (E19).
func weighs_side(n: int, now: int) -> bool:
	return not _asked or (n != 1 and now != team_side)


## Ask for side `asked` (1 / -1), weighed with the team stacking on `now`.
func ask(asked: int, now: int) -> void:
	want = asked
	team_side = now
	_asked = true


## Claim (or keep) its slot in `stack` with the side it asks for (`DoorStack.claim`): the slot, the
## side, its place in that side's file and its point, all taken. A member whose slot changes is no
## longer moving up (E2). Returns `{ slot, held, side, place, point }` (`held` false: a dead end
## holds no slot for it, E20).
func claim(stack: RefCounted) -> Dictionary:
	var at: Dictionary = stack.claim(me())
	if int(at["slot"]) != slot:
		move_up = 0
	slot = int(at["slot"])
	_take(at)
	return at


## Where its slot stands now in `stack` (`DoorStack.settle`), taken without claiming again (a slot
## it moved up into, or one taken otherwise). Returns `{ slot, side, place, point }`.
func settle(stack: RefCounted) -> Dictionary:
	var at: Dictionary = stack.settle(me())
	_take(at)
	return at


## The member as a `DoorStack` reads one asking about itself: `{ id, slot, side, want,
## claim_frame, claim_pos, move_up, step, crossed_frame }` and its `terms`, by the radio's names.
func me() -> Dictionary:
	var out := {
		"id": id, "slot": slot, "side": side, "want": want, "claim_frame": claim_frame,
		"claim_pos": claim_pos, "move_up": move_up, "step": step, "crossed_frame": crossed_frame,
	}
	out.merge(terms)
	return out


## Take where a settled slot stands (`at`: `DoorStack.settle` / `claim`).
func _take(at: Dictionary) -> void:
	side = int(at["side"])
	place = int(at["place"])
	point = at["point"]
