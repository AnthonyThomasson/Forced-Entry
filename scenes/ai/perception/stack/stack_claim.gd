extends RefCounted
## AI PERCEPTION sub-domain — STACK · the entry claim (`docs/tactical-entry.md` E1 to E22,
## `docs/leadership.md` LD9 to LD25): a member's place in a doorway's stack as the `&"callout"`
## radio carries it (interface 10), and the step lists and distances every reader of a stack shares.
## The one encoder (`encode`, the entry fields of a callout) and the one decoder (`decode`, a
## callout's claim, each field's default from `DEFAULTS`): the NPCs' controller, the human's
## `PlayerStack` and every listener (`ClaimLedger`) go through them, so no caller reads a claim key
## off a raw callout. Static, preloaded (no `class_name`).

const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")
## Entry steps of a member still on its way into the room: it holds a place in the stack.
const STACKING := ["claim", "ready", "bang", "going_in"]
## Entry steps of a member standing in its slot (at the ready barrier, or holding there for the
## bang).
const IN_SLOT := ["ready", "bang"]
## Entry steps of a member through the doorway.
const THROUGH := ["in", "clear", "cover", "rear"]
## Entry steps of a member that has called the room clear (`clear`, then the watch it keeps
## after).
const CLEARED := ["clear", "cover", "rear"]
## Entry steps of a member holding the cleared room (covering a doorway or the rear).
const HOLDING := ["cover", "rear"]
## Entry steps that end a member's claim on a doorway (it gave it up, or is done with it).
const ENDED := ["abort", "done"]
## How far (px) inside the wall plane an entrant counts as through the threshold.
const THROUGH_DEPTH := 26.0
## A doorway's fatal funnel: within its width and this far (px) of its wall plane, either side.
const FUNNEL_DEPTH := 40.0
## Seconds between repeats of a member's latest call, so its claim stays live on the radio (a heard
## callout lapses after the listener's `callout_ttl`).
const HEARTBEAT := 2.0
## How close (px) an NPC walks into its stack slot: all the way, since a stride short of it stands
## on the next slot, in the way of the member walking past to it.
const SLOT_REACH := 6.0
## How close (px) to its slot a hand-driven body (the human) counts as standing in it: a player
## steers to a marker, not onto a point, so the NPCs' `WAYPOINT_REACH`.
const HUMAN_SLOT_REACH := 20.0
## The modes a stack goes in (LD14, D31): quietly (the first), with a stun or with a frag thrown in
## first; the squad's `MODES`, which a leader's request or a rally's go may name.
const MODES := ["quiet", "stun", "frag"]
## The order mode of a join (the leader's own stack bringing its team in, LD24): not one of
## `MODES`.
const JOIN := "join"
## Every field of an entry claim on the radio, with the value a claim that does not say it has:
## `opening` / `into` (the doorway, the room it goes into), `slot` (1 = the point), `side` (1 / -1
## along the wall), `entry_step` (claim / ready / bang / going_in / in / clear / cover / rear / done
## / abort), `bang` (it goes in with a stun thrown first: a member that says nothing of it never
## holds a stack back nor turns it), `bang_off` (it gave the bang up), `stuns` / `frags` (how many
## it carries for the stack), `cleared_room` (with a `clear`), `covering` (the doorway it watches,
## with a `cover`), `claim_frame` / `claim_pos` (the physics frame its slot was claimed on and where
## it stood then, -1 / `Vector2.INF` for none: same-frame claims settle by distance, E2; decoded as
## where it stands when it says none), `move_up` (the slot it moved up from while it walks into the
## one it took, E2), `pie` (it has begun the pie: nobody moves up behind it), the order it stacks
## under (`order_id`, "" for none, `order_bang`, `order_mode` quiet / stun / frag (LD14),
## `order_hold` and `order_go` (held for the leader's go and whether it came, LD13), `order_side`,
## 0 for a split stack, LD9, `order_frame`, the frame the order was issued on, -1 unknown),
## `crossed_frame` (the frame its latest crossing began on: its step reached `going_in` or a
## through step, -1 for none; a held stack takes the human's crossing as its go only from the
## order's frame on, D14), `join` (a join's claim, never its holder's own, LD24, D30), `human`
## (the human's: no AI moves up into its slot, E2, E16), `leader` (its speaker leads the squad,
## LD17) and `own` (the human's own claim, which its squad rallies the team to, LD24).
const DEFAULTS := {
	"opening": "", "into": "", "slot": 0, "side": 0, "entry_step": "",
	"bang": true, "bang_off": false, "stuns": 0, "frags": 0,
	"cleared_room": "", "covering": "",
	"claim_frame": -1, "claim_pos": Vector2.INF, "move_up": 0, "pie": false,
	"order_id": "", "order_bang": false, "order_mode": "quiet", "order_hold": false,
	"order_go": false, "order_side": 0, "order_frame": -1, "crossed_frame": -1,
	"join": false, "human": false, "leader": false, "own": false,
}


## The entry fields of a callout for claim `fields` (`DEFAULTS`' keys; a key left out says its
## default): every field, typed, nothing else. The callout's header (speaker, faction, position,
## ...) is the producer's.
static func encode(fields: Dictionary) -> Dictionary:
	var out := {}
	for key in DEFAULTS:
		out[key] = _typed(key, fields.get(key, DEFAULTS[key]))
	return out


## Whether `mode` is one of `MODES` that throws a grenade in first (any but quiet).
static func throws_first(mode: Variant) -> bool:
	return MODES.has(mode) and mode != MODES[0]


## The order fields of a member's claim (`join` and the `order_*` of `DEFAULTS`) for the order it
## stacks under, `order` by the order's own names (`id`, `join`, `bang`, `mode`, `hold`, `go`,
## `side`, `frame`; a key left out says its `DEFAULTS` value): `join` always, and `order_go` once
## the member latched a go (an unordered member following a held order too, D10, which only its own
## reads count); an ordered member's (`id` not "", LD9) every `order_*`; a join held for its human
## leader's go (`join` and `hold`, D31, its claim carrying no order id, D30) the rally it holds for
## (`order_frame`), `order_hold`, `order_go` and the mode its go named (`order_mode`); nothing more
## for any other. Built here alone, for the radio's claim and every member's own
## (`StackMember.terms`).
static func order_terms(order: Dictionary) -> Dictionary:
	var join := bool(order.get("join", false))
	var out := { "join": join }
	var go := bool(order.get("go", DEFAULTS["order_go"]))
	if go:
		out["order_go"] = true
	var id := str(order.get("id", ""))
	if id == "" and not (join and bool(order.get("hold", false))):
		return out
	out["order_hold"] = bool(order.get("hold", DEFAULTS["order_hold"]))
	out["order_go"] = go
	out["order_mode"] = str(order.get("mode", DEFAULTS["order_mode"]))
	out["order_frame"] = int(order.get("frame", DEFAULTS["order_frame"]))
	if id != "":
		out["order_id"] = id
		out["order_bang"] = bool(order.get("bang", DEFAULTS["order_bang"]))
		out["order_side"] = int(order.get("side", DEFAULTS["order_side"]))
	return out


## The claim callout `data` carries, `{}` when it carries none (no `entry_step`): every field of
## `DEFAULTS` (its default when the callout does not say it; `claim_pos` where the speaker stands),
## with `step` its entry step, `id` / `name` its speaker's instance id and name (0 / "" when the
## speaker is gone), `pos` where it stood and `age` 0 (a ledger sets how long ago it was heard).
static func decode(data: Dictionary) -> Dictionary:
	var step := str(data.get("entry_step", ""))
	if step == "":
		return {}
	var out := encode(data)
	var at: Vector2 = data.get("position", Vector2.ZERO)
	if out["claim_pos"] == Vector2.INF:
		out["claim_pos"] = at
	var speaker = data.get("speaker")
	var alive := speaker is Node and is_instance_valid(speaker)
	out["step"] = step
	out["id"] = speaker.get_instance_id() if alive else 0
	out["name"] = str(speaker.name) if alive else ""
	out["pos"] = at
	out["age"] = 0.0
	return out


## Whether callout `data` carries an entry claim (any entry step, `ENDED` ones too): it replaces
## what its speaker last claimed.
static func is_claim(data: Dictionary) -> bool:
	return str(data.get("entry_step", "")) != "" and not keeps_claim(data)


## Whether callout `data` leaves its speaker's last claim standing: a call about a live grenade
## (`AgentGrenades.is_call`, G16) or how an order goes with no entry step in it (`order_step`,
## LD7), neither of which is what the speaker is doing. Any other callout that is not a claim says
## the speaker is doing something else: it drops the claim.
static func keeps_claim(data: Dictionary) -> bool:
	if AgentGrenades.is_call(data.get("status")):
		return true
	return str(data.get("order_step", "")) != "" and str(data.get("entry_step", "")) == ""


## Whether `d` is a join's (LD24): an order (a `stack` of mode `JOIN`, as the squad posts it), an
## entry leaf's params or a claim (`join` true).
static func is_join(d: Dictionary) -> bool:
	if bool(d.get("join", false)):
		return true
	return str(d.get("kind", "")) == "stack" and str(d.get("mode", "")) == JOIN


## Whether entry step `step` holds a place in the stack (`STACKING`).
static func stacking(step: String) -> bool:
	return STACKING.has(step)


## Whether entry step `step` stands in its slot (`IN_SLOT`).
static func in_slot(step: String) -> bool:
	return IN_SLOT.has(step)


## Whether entry step `step` is through the doorway (`THROUGH`).
static func through(step: String) -> bool:
	return THROUGH.has(step)


## Whether entry step `step` is crossing the doorway (`going_in`) or through it (`THROUGH`).
static func crossing(step: String) -> bool:
	return step == "going_in" or through(step)


## Whether entry step `step` has called the room clear (`CLEARED`).
static func cleared(step: String) -> bool:
	return CLEARED.has(step)


## Whether entry step `step` holds the cleared room (`HOLDING`).
static func holding(step: String) -> bool:
	return HOLDING.has(step)


## Whether a point `outward` px off a doorway's wall plane and `lateral` px along it from the
## doorway's centre stands in its fatal funnel: within its half width `half` (grown by `margin`, a
## body's width for a body standing there) and `FUNNEL_DEPTH` of the plane, either side. The one
## funnel test of the entry geometry and the human's stack.
static func in_funnel(outward: float, lateral: float, half: float, margin := 0.0) -> bool:
	return absf(lateral) < half + margin and absf(outward) < FUNNEL_DEPTH


## The order claims are listed and settled in: lowest slot first, then lowest instance id (a
## `sort_custom` comparator over claims, or any `{ slot, id }`).
static func by_slot(a: Dictionary, b: Dictionary) -> bool:
	return a["slot"] < b["slot"] if a["slot"] != b["slot"] else a["id"] < b["id"]


## `value` as field `key`'s type (its default's).
static func _typed(key: String, value: Variant) -> Variant:
	match typeof(DEFAULTS[key]):
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value)
		TYPE_STRING:
			return str(value)
	return value
