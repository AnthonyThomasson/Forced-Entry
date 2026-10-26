extends RefCounted
## AI domain · TEAM — a squad's stacks, a part the squad builds once and holds as `stacks`: every
## stack its side is forming (`docs/leadership.md` LD18), read off the side's entry claims on the
## radio (`ledger`) and laid by each doorway's `DoorStack` over the doorway geometry (`entry`), the
## same the NPCs build; `now()` is `view()["stacks"]`. It holds its squad (a node, so no reference
## cycle) for the world the stacks are laid on.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const ClaimLedger := preload("res://scenes/ai/perception/stack/claim_ledger.gd")

## The squad it belongs to.
var squad: Node
## The entry claims of this side heard on the radio, the latest per member (LD18): from anywhere
## (the side's whole view), each current for the NPCs' `callout_ttl` (`setup`; a claim is repeated
## every `StackClaim.HEARTBEAT` s).
var ledger: RefCounted = ClaimLedger.new()
## `_stacks()` as last laid (`now`).
var _stacks_cache: Array = []
## The physics frame `_stacks_cache` was laid on (-1: lay it again on the next read).
var _stacks_at := -1
## The doorway geometry the stacks are laid out by, the same the NPCs build.
var entry: RefCounted = AgentEntry.new()


func _init(team: Node) -> void:
	squad = team


## `_stacks()`, laid at most once a physics frame, and again after a claim heard or a member's
## death: the stack markers, the order markers and the leaders overlay each read `view()` every
## frame (about 0.14 ms a lay with a six-member stack).
func now() -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _stacks_at:
		_stacks_cache = _stacks()
		_stacks_at = frame
	return _stacks_cache


## Lay the stacks again on the next read (`now`): a claim heard or a member's death.
func invalidate() -> void:
	_stacks_at = -1


## Every stack the side is forming (LD18), from the entry claims heard:
## `[{ opening, into, door, slots: [{ n, point, holder, held, there, mine, side, row }] }]`, a stack
## while one of its members is still on its way in. Its slots run from 1 to the last claimed, each
## where the AI stands it (`DoorStack.layout`: its holder's side, its place in that side's file),
## a free one on the stack's side; `holder` the instance id holding it (0: none), `there` its
## holder standing in it, `mine` the human's, `row` its file (1 against the wall, 2 a step out).
func _stacks() -> Array:
	var out: Array = []
	for at: Dictionary in ledger.openings_stacking():
		var g := _geometry(at["opening"], at["into"])
		if g.is_empty():
			continue
		out.append({
			"opening": at["opening"],
			"into": at["into"],
			"door": g["pos"],
			"slots": ledger.stack(at["opening"], g).layout(),
		})
	return out


## The entry geometry of doorway `opening` into room `into`, on the world the squad is in: its
## viewport's `World2D`, the one its members stand in ({} when none is known, or the squad is not in
## the tree).
func _geometry(opening: String, into: String) -> Dictionary:
	if not squad.is_inside_tree():
		return {}
	var world := squad.get_viewport().find_world_2d()
	return entry.geometry(opening, into, world.navigation_map, world.direct_space_state)
