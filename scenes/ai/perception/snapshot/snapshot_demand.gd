extends RefCounted
## AI PERCEPTION sub-domain — SNAPSHOT DEMAND. The option groups, facts and sections a decision's
## walk rarely reads, built when it first reads them instead of with every snapshot: the groups
## `leads`, `entries`, `search_rooms`, `explore`, `interactions`, `rooms` and
## the grenade throws (`grenade_throws`, the shots' one, and each analysed hostile's); the facts
## `leads`, `lead_outside` and `grenade_ready`; and the sections `odds` and `exposure`, which say
## what the leads and the throws make possible. `AgentSnapshot.build()` hands each snapshot one
## (`snapshot["demand"]`), filled with what these are built from (the frozen context and knowledge
## of that decision); the planner asks it for what its snapshot lacks (`group`, `target_group`,
## `fact`, `section`, `target_section`), and a reader that wants everything (the debug overlay, the
## spectator card, a test) calls `complete()`. What is built here is stored in the snapshot's own
## dictionaries, so it is built once and every later reader sees it there. On a world that does not
## change during the walk the path, every option read and its text are the eager build's.
##
## `grenade_ready` is answered by a search that stops at the first throw the NPC could make
## (`SnapshotThrows.grenade_possible`); the throw options themselves, with their tags and wording,
## are built only when the walk reads them.
##
## What a group reads live (the event memory, the physics space, the navigation map) it reads when
## it is built, up to a walk's latency after the decision began: a door turned or a sound heard
## meanwhile is in the group, and the walk neither throws nor loses an option
## (`tests/ai/decision/lazy_groups_read_live_test.gd`). What it reads from `ctx` and `know` is the
## decision's frozen copy.

const SnapshotVocab = preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const SnapshotOptions = preload("res://scenes/ai/perception/snapshot/snapshot_options.gd")
const SnapshotSections = preload("res://scenes/ai/perception/snapshot/snapshot_sections.gd")
const SnapshotThrows = preload("res://scenes/ai/perception/snapshot/snapshot_throws.gd")
const ThrowScan := preload("res://scenes/ai/perception/throw_scan.gd")
const HouseRooms := preload("res://scenes/ai/perception/house_rooms.gd")
const GroupBuild := preload("res://scenes/ai/perception/snapshot/group_build.gd")
const GroupSteps := preload("res://scenes/ai/perception/snapshot/group_steps.gd")
const GroupReads := preload("res://scenes/ai/perception/snapshot/group_reads.gd")
const ThrowSearch := preload("res://scenes/ai/perception/snapshot/throw_search.gd")
## The option groups built on demand (the global ones; a hostile's grenade throws are
## `target_group`'s).
const GROUPS: Array[String] = [
	"leads", "entries", "search_rooms", "explore", "interactions", "rooms", "grenade_throws",
]
## The facts resolved on demand.
const FACTS: Array[String] = ["leads", "lead_outside", "grenade_ready"]
## The state sections written on demand.
const SECTIONS: Array[String] = ["odds", "exposure"]
## The id of a global group in `GroupSteps`' jobs (a hostile's group has its hostile's id), and of
## the source of a throw when the shots' origin is it.
const GLOBAL := -1
## No source: the throw search found none, or its answer was a group already built.
const NO_SOURCE := ThrowSearch.NO_SOURCE

## The names of the groups built so far, in the order they were built (one entry per group: a
## group is built once; a hostile's grenade throws are `grenade_throws:<its id>`). A test reads it
## to see which groups a walk read.
var built: Array[String] = []
## The option groups' author (`snapshot_options.gd`).
var options: SnapshotOptions
## The grenade groups' author (`snapshot_throws.gd`).
var throws: SnapshotThrows
## The state text's author (`snapshot_sections.gd`).
var texts: SnapshotSections
## The shared vocabulary: its `rooms` are the decision's.
var vocab: SnapshotVocab
## The decision's frozen context (`AgentSnapshot._context`).
var ctx := {}
## The knowledge the perception handed the decision (`AgentPerception.sense`).
var know := {}
## The house's rooms the decision is built over.
var rooms: Array = []
## Whether a stun can be thrown, which hands the leads the rooms the entries lead into.
var stun_stack := false
## The hostiles given full analysis, by id: `{ t, a }`, the contact and its combat geometry.
var targets := {}
## The snapshot's own `options`, which a group is stored in once built.
var groups := {}
## The snapshot's own `facts`, which a fact is stored in once worked out.
var facts := {}
## The snapshot's own `sections`, which a section is stored in once written.
var sections := {}
## The snapshot's own `sections_per_target`, which a hostile's section is stored in once written.
var per_sections := {}
## What the leads and entries built ahead of the walk read of the radio (`group_reads.gd`), and the
## rooms the entries lead into.
var reads := GroupReads.new()


## The kinds (`frag` / `stun`) of the throws in grenade group `throw_group` the GRENADE tactic would
## offer: those not tagged `ally_in_blast` or `no_safe_spot`.
static func usable(throw_group: Dictionary) -> Array:
	var offered := func(o): return not o["tags"]["ally_in_blast"] and not o["tags"]["no_safe_spot"]
	return throw_group["options"].filter(offered).map(func(o): return o["id"])


## Option group `name`, built now unless it was already: `{}` for a name that is not built on
## demand (so a caller can ask for any group).
func group(name: String) -> Dictionary:
	if groups.has(name):
		return groups[name]
	if not GROUPS.has(name):
		return {}
	var _scope: RefCounted = open()
	SnapshotCounts.note(name)
	reads.note(ctx, name)
	var out := _build(name)
	store(name, GLOBAL, out)
	return out


## Hostile `target_id`'s option group `name` (`grenade_throws`), built now unless it was already;
## null when it is not built on demand or the hostile got no full analysis.
func target_group(name: String, target_id: int) -> Variant:
	if name != "grenade_throws" or not targets.has(target_id):
		return null
	var per: Dictionary = groups["per_target"][target_id]
	if per.has(name):
		return per[name]
	var _scope: RefCounted = open()
	SnapshotCounts.note("target_throws")
	var target: Dictionary = targets[target_id]
	store(name, target_id, throws.grenade_group(ctx, target["t"], target["a"]))
	return per[name]


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
	elif name == "grenade_ready":
		value = _grenade_ready()
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
	elif name == "exposure":
		text = _exposure()
	sections[name] = text
	return text


## Hostile `target_id`'s version of section `name` (`exposure`), written now unless it was already;
## null when it is not written on demand or the hostile got no full analysis.
func target_section(name: String, target_id: int) -> Variant:
	if name != "exposure" or not targets.has(target_id):
		return null
	var per: Dictionary = per_sections[target_id]
	if per.has(name):
		return per[name]
	var target: Dictionary = targets[target_id]
	var throw_group: Dictionary = target_group("grenade_throws", target_id)
	per[name] = texts.exposure_text(
		ctx, target["t"], target["a"], usable(throw_group), throw_group.get("held_room", "")
	)
	return per[name]


## Build every group, fact and section still missing, so the snapshot holds what an eager build
## would: the full-set reader's call. Idempotent.
func complete() -> void:
	for name in GROUPS:
		group(name)
	for id in targets:
		target_group("grenade_throws", id)
		target_section("exposure", id)
	for name in FACTS:
		fact(name)
	for name in SECTIONS:
		section(name)


## Hand the author's modules the decision this builds for (they read it from themselves, whatever
## a decision begun since has left there) and open the walked-route memo of the build: hold the
## returned token for the whole build.
func open() -> RefCounted:
	options.know = know
	throws.know = know
	vocab.rooms = rooms
	return options.begin_decision()


## Whether the NPC is in a room and a lead lies outside the house.
func _lead_outside() -> bool:
	SnapshotCounts.note("lead_outside")
	if HouseRooms.at(ctx["self_pos"], rooms).is_empty():
		return false
	return (group("leads")["options"] as Array).any(func(o): return not o["tags"]["inside"])


## Whether a legal throw exists (docs/grenades.md G17, G18): one at a hostile given full analysis,
## or one where the shots came from. The search that stops at the first throw the NPC could make,
## run to its end (`throw_search`).
func _grenade_ready() -> bool:
	var search := throw_search(ThrowScan.WHOLE)
	while not search.done():
		search.step()
	return search.found


## The `grenade_ready` search in steps of `block` raw candidates (`ThrowSearch`), or null when the
## fact is already worked out. What is already built answers from it (a group's options); the rest
## by the search of each source in the order of the one-shot's: the shots' origin, then each hostile
## given full analysis. Its answer goes into the snapshot's facts as it ends. The decision job runs
## it as the throw piece (`decision-job.md`).
func throw_search(block: int) -> RefCounted:
	if facts.has("grenade_ready"):
		return null
	SnapshotCounts.note("grenade_ready")
	var plan: Array = []
	var ids: Array = []
	if groups.has("grenade_throws"):
		plan.append({ "of": "known", "value": _offers(groups["grenade_throws"]) })
		ids.append(NO_SOURCE)
	else:
		plan.append({ "of": "shots", "hostiles": ctx["hostiles"] })
		ids.append(GLOBAL)
	for id: int in targets:
		var per: Dictionary = groups["per_target"][id]
		if per.has("grenade_throws"):
			plan.append({ "of": "known", "value": _offers(per["grenade_throws"]) })
			ids.append(NO_SOURCE)
		else:
			plan.append({ "of": "target", "t": targets[id]["t"], "a": targets[id]["a"] })
			ids.append(id)
	var search: RefCounted = throws.begin_search(ctx, plan, block)
	search.demand = self
	search.ids = ids
	return search


## Note the hostile (`GLOBAL`: the shots' origin, `NO_SOURCE`: none) the throw search found a throw
## at: the one the grenade piece builds the throws for (`grenade_steps`).
func found_at(id: int) -> void:
	throws.memo_of(ctx)["source"] = id


## The leads group, and the entries it needs while a stun can be thrown, in steps (`GroupSteps`),
## or null when both are built: what the decision's root reads whatever the situation, so the job
## builds it ahead of the walk (`decision-job.md`, the group piece).
func group_steps() -> RefCounted:
	var jobs: Array = []
	if stun_stack:
		jobs.append({ "name": "entries", "id": GLOBAL })
	jobs.append({ "name": "leads", "id": GLOBAL })
	return _steps(jobs)


## The throws at the hostile (or the shots' origin) the throw search found one at, in steps, or null
## when there are none to build (no throw found by that search, or its group is built).
func grenade_steps() -> RefCounted:
	var source: int = throws.memo_of(ctx).get("source", NO_SOURCE)
	if source == NO_SOURCE or not facts.get("grenade_ready", false):
		return null
	return _steps([{ "name": "grenade_throws", "id": source }])


## A run of the groups in `jobs`, those not built yet, or null when all are.
func _steps(jobs: Array) -> RefCounted:
	jobs = jobs.filter(func(j): return not holds(j["name"], j["id"]))
	if jobs.is_empty():
		return null
	return GroupSteps.new().begin(self, jobs)


## Whether group `name` (of hostile `id`, or `GLOBAL`) is built.
func holds(name: String, id: int) -> bool:
	if id == GLOBAL:
		return groups.has(name)
	return not targets.has(id) or (groups["per_target"][id] as Dictionary).has(name)


## Forget the leads built ahead of the walk, and what is made of them: they were made while a stun
## could (not) be thrown, so with the entries' rooms left out (or in), and the stack since says
## otherwise (`AgentSnapshot.reread_claims`). The walk builds them again as it reads them; the
## entries do not depend on the stun and stay.
func forget_leads() -> void:
	if groups.erase("leads"):
		built.erase("leads")
		reads.forget("leads")
	facts.erase("leads")
	facts.erase("lead_outside")
	sections.erase("odds")


## Forget the leads and the entries built ahead of the walk that a call or a slot claim came in
## since (`AgentSnapshot.reread_claims`, the callouts now in `ctx`): the walk builds them again as
## it reads them, so two NPCs bound for one doorway take different slots however long the build
## took. The leads go too when the entries they leave out the rooms of go and a stun can be thrown.
func forget_stale_groups() -> void:
	var entries_stale: bool = groups.has("entries") and reads.stale(ctx, "entries")
	if entries_stale:
		SnapshotCounts.note("forgotten_entries")
		groups.erase("entries")
		built.erase("entries")
		reads.forget("entries")
	var leads_stale: bool = groups.has("leads") and reads.stale(ctx, "leads")
	if (leads_stale or (entries_stale and stun_stack)) and groups.has("leads"):
		SnapshotCounts.note("forgotten_leads")
		forget_leads()


## Begin group `name` (of hostile `id`, or `GLOBAL`) in steps (`GroupBuild`): the group the same
## as when the walk first reads it.
func begin_group(name: String, id: int) -> RefCounted:
	SnapshotCounts.note(name if id == GLOBAL else "target_throws")  # one a group, not a step
	reads.note(ctx, name)
	if id != GLOBAL:
		return throws.begin_grenade_group(ctx, targets[id]["t"], targets[id]["a"])
	match name:
		"entries":
			return options.begin_entry_group(ctx, rooms)
		"leads":
			return options.begin_lead_group(ctx, ctx["hostiles"], _entered_for_leads())
		"grenade_throws":
			return throws.begin_shots_group(ctx, ctx["hostiles"])
	return GroupBuild.new().already(_build(name))


## Keep group `name` (of hostile `id`, or `GLOBAL`) as built, in the snapshot's own dictionaries.
func store(name: String, id: int, out: Dictionary) -> void:
	if holds(name, id):
		return  # Built already (a group is built once): the first stays.
	if id == GLOBAL:
		groups[name] = out
		built.append(name)
		return
	groups["per_target"][id][name] = out
	built.append("%s:%d" % [name, id])


## Whether a built grenade group holds an option.
func _offers(throw_group: Dictionary) -> bool:
	return not (throw_group["options"] as Array).is_empty()


## The odds: how many hostiles against which allies; with none known, whether it is quiet or there
## is trouble out of sight (a lead), which asks for the leads only with no hostile known and
## nobody firing at the NPC.
func _odds() -> String:
	var trouble: bool = (texts.is_quiet(ctx["hostiles"])
			and not (group("leads")["options"] as Array).is_empty())
	return texts.odds_text(ctx["hostiles"], ctx["allies"], ctx["callouts"], trouble)


## The exposure the walk reads at a level with no hostile bound: the nearest hostile given full
## analysis, else (shot at by someone unseen) what the throws where the shots came from allow.
func _exposure() -> String:
	for h: Dictionary in ctx["hostiles"]:
		if targets.has(h["id"]):
			return target_section("exposure", h["id"])
	var shots := group("grenade_throws")
	return texts.unseen_fire_text(usable(shots), shots.get("held_room", ""))


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
		"grenade_throws":
			out = throws.shots_grenade_group(ctx, ctx["hostiles"])
	return out


## The rooms a doorway of ENTER leads into.
func _entered_rooms() -> Dictionary:
	if reads.entered == null:
		reads.entered = SnapshotOptions.entry_rooms(group("entries"))
	return reads.entered


## What the leads leave out: the rooms the entries lead into, while a stun can be thrown (the
## entry weighs them, docs/grenades.md G18); nothing otherwise.
func _entered_for_leads() -> Dictionary:
	return _entered_rooms() if stun_stack else {}
