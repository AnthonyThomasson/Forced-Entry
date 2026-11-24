extends RefCounted
## AI PERCEPTION sub-domain — STACK · the claim ledger: the entry claims one listener has heard on
## the `&"callout"` radio (`stack_claim.gd`), the latest per speaker, for the stacks it reads. One
## per listener: an NPC's perception, the human's `PlayerStack`, a side's `Squad`. It hears its own
## side only (`faction`), within the listener's `callout_range` (<= 0: unlimited, the squad's
## whole view), never the listener's own calls; a claim lapses `ttl` s (on `GameClock`, LD1) after
## it was heard, and a dead or freed speaker's goes at once. A callout that keeps the speaker's
## claim (`StackClaim.keeps_claim`: a grenade call, an order's progress) leaves it standing; any
## other callout replaces it, so a speaker doing something else holds no claim. A doorway's claims
## and stack are laid when a claim is heard or lapses and stand until then, each claim's `age`
## brought up once per physics frame (`GameClock.frame()`): the lists and stacks asked on later
## frames are the same objects while nothing changed.

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")
const DoorStack := preload("res://scenes/ai/perception/stack/door_stack.gd")

## The side whose claims it hears.
var faction: StringName = &""
## How far (px) a claim carries to the listener (<= 0: unlimited).
var callout_range := 0.0
## Seconds a heard claim stays current.
var ttl := 6.0
## The listener, whose own calls it does not hear (null: none).
var listener: Node = null
## speaker instance id -> { claim (decoded), speaker, at (`GameClock.seconds()` heard) }.
var _heard := {}
## opening -> its claims (`claims`), laid since a claim was last heard or lapsed.
var _cache := {}
## opening -> { into -> its `DoorStack` }, laid with `_cache`.
var _stacks := {}
## The `GameClock.frame()` the ages and the lapsed claims were last brought up to date on (-1: not
## yet).
var _frame := -1


## Set what it hears from `cfg`: `faction`, `range` (px, <= 0 unlimited), `ttl` (s) and the
## `listener` (a Node), each left as it is when `cfg` does not name it.
func setup(cfg: Dictionary) -> void:
	faction = StringName(cfg.get("faction", faction))
	callout_range = float(cfg.get("range", callout_range))
	ttl = float(cfg.get("ttl", ttl))
	listener = cfg.get("listener", listener)
	_drop_laid()


## Take callout `data` (interface 10) heard by a listener standing at `listener_pos`
## (`Vector2.INF`: anywhere, no range).
func hear(data: Dictionary, listener_pos := Vector2.INF) -> void:
	var speaker = data.get("speaker")
	if (not speaker is Node
			or not is_instance_valid(speaker)
			or speaker == listener
			or speaker.get("is_dead") == true
			or StringName(data.get("faction", &"")) != faction
			or StackClaim.keeps_claim(data)):
		return
	var at: Vector2 = data.get("position", listener_pos)
	if (callout_range > 0.0
			and listener_pos != Vector2.INF
			and listener_pos.distance_to(at) > callout_range):
		return
	var id: int = speaker.get_instance_id()
	if StackClaim.is_claim(data):
		_heard[id] = {
			"claim": StackClaim.decode(data), "speaker": speaker, "at": GameClock.seconds(),
		}
	else:
		_heard.erase(id)
	_drop_laid()


## The claims heard and standing, speaker instance id -> decoded claim (no ages): what two moments
## of one ledger are compared by, to see whether a claim came in, changed or lapsed between them.
func heard_key() -> Dictionary:
	_refresh()
	var out := {}
	for id in _heard:
		out[id] = _heard[id]["claim"]
	return out


## The live claims on doorway `opening` (`StackClaim.decode`, with `age` the seconds since each was
## heard): one per speaker, none `ENDED`, lowest slot first (then lowest instance id). The list is
## shared until the next frame or claim heard: read it, never change it.
func claims(opening: String) -> Array:
	_refresh()
	if _cache.has(opening):
		return _cache[opening]
	var now := GameClock.seconds()
	var out: Array = []
	for id in _heard:
		var rec: Dictionary = _heard[id]
		var claim: Dictionary = rec["claim"]
		if claim["opening"] != opening or StackClaim.ENDED.has(claim["step"]) or _lapsed(rec, now):
			continue
		if not rec.has("live"):
			rec["live"] = claim.duplicate()  # The claim with its `age`, kept while it stands.
		var live: Dictionary = rec["live"]
		live["age"] = now - float(rec["at"])
		out.append(live)
	out.sort_custom(StackClaim.by_slot)
	_cache[opening] = out
	return out


## The stack at the doorway of geometry `g` (agent_entry.gd `geometry`; {} for the claims alone, on
## doorway `opening`): a `DoorStack` of its claims, built at most once a frame (or again once a
## claim is heard).
func stack(opening: String, g := {}) -> RefCounted:
	var team := claims(opening)
	var into: String = str(g.get("into", ""))
	var of_opening: Dictionary = _stacks.get(opening, {})
	var held: RefCounted = of_opening.get(into)
	if (held != null
			and is_same(held.team, team)
			and (is_same(held.geometry, g) or (g.is_empty() and held.geometry.is_empty()))):
		return held
	held = DoorStack.new(g, team)
	of_opening[into] = held
	_stacks[opening] = of_opening
	return held


## The doorways a stack is forming at (`{ opening, into }`, in the order their claims were first
## heard): those with a live claim at a `STACKING` step, `into` the room the lowest slot's of those
## goes into (the stack forming, not a claim left from an earlier entry through the doorway).
func openings_stacking() -> Array:
	_refresh()  # Before the loop: it drops lapsed claims from `_heard`.
	var out: Array = []
	var seen := {}
	for id in _heard.keys():
		var opening: String = _heard[id]["claim"]["opening"]
		if opening == "" or seen.has(opening):
			continue
		seen[opening] = true
		for m in claims(opening):
			if StackClaim.stacking(m["step"]):
				out.append({ "opening": opening, "into": m["into"] })
				break
	return out


## Drop the lapsed claims and those of dead or freed speakers (what is laid goes with the first),
## and bring the ages of the claims that stand up to date, once a frame has passed.
func _refresh() -> void:
	var frame := GameClock.frame()
	if frame == _frame:
		return
	_frame = frame
	var now := GameClock.seconds()
	var dropped := false
	for id in _heard.keys():
		if _lapsed(_heard[id], now):
			_heard.erase(id)
			dropped = true
	if dropped:
		_drop_laid()
		return
	for rec: Dictionary in _heard.values():
		if rec.has("live"):
			rec["live"]["age"] = now - float(rec["at"])


## Forget the claims and stacks laid: a claim came in or went, or what the ledger hears changed.
func _drop_laid() -> void:
	_cache = {}
	_stacks = {}
	_frame = -1  # What is heard is looked over again at the next ask.


## Whether heard claim `rec` has lapsed by `now`, or its speaker is dead or gone.
func _lapsed(rec: Dictionary, now: float) -> bool:
	var speaker = rec["speaker"]
	return (now - float(rec["at"]) > ttl
			or not is_instance_valid(speaker)
			or (speaker as Node).get("is_dead") == true)
