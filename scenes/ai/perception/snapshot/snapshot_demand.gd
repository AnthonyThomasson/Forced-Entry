extends RefCounted
## AI PERCEPTION sub-domain — SNAPSHOT DEMAND. The option groups and facts a decision's walk
## rarely reads, built when it first reads them instead of with every snapshot (#192 rule 23):
## the groups `leads`, `entries`, `search_rooms`, `explore`, `interactions` and `rooms`, the facts
## `leads` and `lead_outside` and the section `odds` that need the first. `AgentSnapshot.build()`
## hands each snapshot
## one (`snapshot["demand"]`), filled with what the groups are built from (the frozen context and
## knowledge of that decision); the planner asks it for a group or fact its snapshot lacks
## (`group`, `fact`), and a reader that wants everything (the debug overlay, the spectator card, a
## test) calls `complete()`. A group built here is stored in the snapshot's own `options`, so it is
## built once and every later reader sees it there; its text is exactly the eager build's.
##
## What a group reads live (the event memory, the physics space, the navigation map) it reads when
## it is built, up to a walk's latency after the decision began; what it reads from `ctx` and
## `know` is the decision's frozen copy.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const SnapshotOptions = preload("res://scenes/ai/perception/snapshot/snapshot_options.gd")
const SnapshotSections = preload("res://scenes/ai/perception/snapshot/snapshot_sections.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
## The option groups built on demand.
const GROUPS: Array[String] = [
	"leads", "entries", "search_rooms", "explore", "interactions", "rooms",
]
## The facts resolved on demand.
const FACTS: Array[String] = ["leads", "lead_outside"]
## The state sections written on demand.
const SECTIONS: Array[String] = ["odds"]

## The names of the groups built so far, in the order they were built (one entry per group: a
## group is built once). A test reads it to see which groups a walk read.
var built: Array[String] = []
## The option groups' author (`snapshot_options.gd`).
var options: SnapshotOptions
## The state text's author (`snapshot_sections.gd`).
var texts: SnapshotSections
## The agent's event memory (read-only here).
var memory: RefCounted
## The shared vocabulary: its `rooms` are the decision's.
var vocab: SnapshotVocab
## The doorway views, whose walked-route memo each build opens for itself.
var views: RefCounted
## The decision's frozen context (`AgentSnapshot._context`).
var ctx := {}
## The knowledge the perception handed the decision (`AgentPerception.sense`).
var know := {}
## The house's rooms the decision is built over.
var rooms: Array = []
## Whether a stun can be thrown, which hands the leads the rooms the entries lead into.
var stun_stack := false
## The snapshot's own `options`, which a group is stored in once built.
var groups := {}
## The snapshot's own `facts`, which a fact is stored in once worked out.
var facts := {}
## The snapshot's own `sections`, which a section is stored in once written.
var sections := {}
## The rooms a doorway of ENTER leads into (`SnapshotOptions.entry_rooms`), once worked out.
var _entered: Dictionary = {}
## Whether `_entered` is worked out.
var _entered_known := false


## Option group `name`, built now unless it was already: `{}` for a name that is not built on
## demand (so a caller can ask for any group).
func group(name: String) -> Dictionary:
	if groups.has(name):
		return groups[name]
	if not GROUPS.has(name):
		return {}
	var _scope: RefCounted = views.begin_decision()
	# The author's modules read the decision in build from themselves: hand this one's back in,
	# whatever a decision begun since has left there.
	options.know = know
	vocab.rooms = rooms
	var out := _build(name)
	groups[name] = out
	built.append(name)
	return out


## Fact `name` of the decision, worked out now unless it was already: false for a fact that is not
## resolved on demand.
func fact(name: String) -> bool:
	if facts.has(name):
		return facts[name]
	if not FACTS.has(name):
		return false
	var value := false
	if name == "leads":
		value = not (group("leads")["options"] as Array).is_empty()
	elif name == "lead_outside":
		value = _lead_outside()
	facts[name] = value
	return value


## State section `name`, written now unless it was already: "" for a section that is not written on
## demand.
func section(name: String) -> String:
	if sections.has(name):
		return sections[name]
	if not SECTIONS.has(name):
		return ""
	var text := ""
	if name == "odds":
		text = _odds()
	sections[name] = text
	return text


## Build every group, fact and section still missing, so the snapshot holds what an eager build
## would: the full-set reader's call. Idempotent.
func complete() -> void:
	for name in GROUPS:
		group(name)
	for name in FACTS:
		fact(name)
	for name in SECTIONS:
		section(name)


## The odds: how many hostiles against which allies; with none known, whether it is quiet or there
## is trouble out of sight (a lead), which asks for the leads only with no hostile known and
## nobody firing at the NPC.
func _odds() -> String:
	var hostiles: Array = ctx["hostiles"]
	var trouble: bool = (hostiles.is_empty() and not memory.under_fire()
			and not (group("leads")["options"] as Array).is_empty())
	return texts.odds_text(hostiles, ctx["allies"], ctx["callouts"], trouble)


## Whether the NPC is in a room and a lead lies outside the house.
func _lead_outside() -> bool:
	if HouseRooms.at(ctx["self_pos"], rooms).is_empty():
		return false
	return (group("leads")["options"] as Array).any(func(o): return not o["tags"]["inside"])


## The group `name`'s build.
func _build(name: String) -> Dictionary:
	var out := {}
	match name:
		"entries":
			out = options.entry_group(ctx, rooms)
		"leads":
			out = options.lead_group(ctx, ctx["hostiles"], _entered_for_leads())
		"search_rooms":
			out = options.search_group(ctx, know["known_rooms"], rooms, _entered_rooms())
		"explore":
			out = options.explore_group(ctx, rooms, _entered_rooms())
		"interactions":
			out = options.interaction_group(ctx["self_pos"])
		"rooms":
			out = options.room_group(ctx, know["known_rooms"], rooms)
	return out


## The rooms a doorway of ENTER leads into.
func _entered_rooms() -> Dictionary:
	if not _entered_known:
		_entered = SnapshotOptions.entry_rooms(group("entries"))
		_entered_known = true
	return _entered


## What the leads leave out: the rooms the entries lead into, while a stun can be thrown (the
## entry weighs them, docs/grenades.md G18); nothing otherwise.
func _entered_for_leads() -> Dictionary:
	return _entered_rooms() if stun_stack else {}
