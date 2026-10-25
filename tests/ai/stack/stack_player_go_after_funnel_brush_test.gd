extends GameTest
## LD13 / D14 (`docs/leadership.md`, `docs/tactical-entry.md` E16): the human's crossing is a held
## stack's go only when it began since the order was issued, and it is the human's latest crossing
## that counts. A human that brushed the doorway's funnel before the order (its claim said
## `going_in`, then `ready` again as it stepped back to its slot) and steps into the doorway after
## the order still releases the held stack: its claim's `crossed_frame` is restamped each time its
## step goes from a waiting one to `going_in` or `in`.
##
## The Terrace house's back door. The human (a puppet given the human's stack radio and its squad
## as a match gives them, `s.squads` with `human`, the squad keeping a claim as long as the NPCs
## keep a callout, `claim_ttl`) stands near a teammate (`a`) stacking there, is reserved slot 2,
## walks to it, steps into the funnel and back to its slot. Then its squad, the human leading,
## orders `a` to stack there, held for the go; `a`'s claims say `ready` under the order. The squad
## says the order is held; the human steps into the doorway, and the squad no longer says it.
##
## Premise: the teammate is a puppet radioing its claims on the bus, not an AI invader: before the
## order nothing makes an AI stack and hold there for as long as the human's brush takes, and the
## squad and the human's stack read only the bus, so a puppet's claim is exactly what they hear
## from an AI.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
## How often (s) the puppet repeats its claim (the NPCs' heartbeat is 2 s; a claim lapses after
## 6 s).
const REPEAT := 0.5
## How long (s) the squad keeps a claim: the NPCs' `callout_ttl` (6 s).
const CLAIM_TTL := 6.0
## How far (px) out from the door the human steps into the funnel (`StackClaim.FUNNEL_DEPTH` 40).
const FUNNEL_STEP := 10.0
## How long (s) the squad is given to read a claim (a few physics frames).
const READ := 0.5


func describe() -> Dictionary:
	return {
		"name": "The human's crossing after a funnel brush releases a held stack",
		"description": "The human in a stack steps into the doorway's funnel and back before a "
			+ "held stack is ordered there, then into the doorway after it: its latest crossing "
			+ "is the stack's go, and the squad no longer says the order is held (LD13, D14).",
		"tags": ["ai", "entry", "stack", "leadership", "order", "scripted", "callout"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	s.switch(&"ai.hostile_on_trespass", false)
	Stack.human(s, &"a", Order.BACK_NORTH)
	Stack.human(s, &"me", Stack.NEAR)
	s.squads({ "human": &"me", "claim_ttl": CLAIM_TTL })


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var opening := String(door["id"])
	var a := t.actor(&"a")
	var squad := t.squad(&"invader")
	var stack := t.player_stack()
	if not _declared(t, squad, stack):
		return
	var said := { "order": {}, "step": "claim" }  # What the puppet radios, every `REPEAT` s.
	_radio_on(t, door, said)
	var slot := await _ready_in_slot(t, stack)
	if slot == Vector2.INF:
		return

	# The brush: into the funnel and back to its slot, before any order.
	var funnel: Vector2 = door["pos"] + (door["out"] as Vector2) * FUNNEL_STEP
	var brush := await _brush(t, stack, slot, funnel)
	if brush.is_empty():
		return
	var order := await _held_order(t, squad, a, brush["call"], said)
	if order.is_empty():
		return

	if not t.require(
			await Stack.walk(t, &"me", [funnel], 8.0)
				and await t.until(func(): return _step(stack) == "going_in", 2.0),
			"the human steps into the doorway again, after the order (going_in)",
	):
		return
	await _check_go(t, squad, a, opening, order)


## Whether the invaders' squad is declared and the human has its stack radio (set-up premises).
func _declared(t: TestContext, squad: Node, stack: Node) -> bool:
	if not t.require(squad != null, "the invaders' squad is declared (s.squads)"):
		return false
	return t.require(stack != null, "the human has a stack radio (MatchBuilder.bind_player)")


## The human is reserved slot 2 behind its teammate, walks to it and is ready; the slot, or
## Vector2.INF when a step fails.
func _ready_in_slot(t: TestContext, stack: Node) -> Vector2:
	if not t.require(
			await t.until(func(): return Stack.mine(stack) == 2, 10.0),
			"the human is reserved slot 2 behind its teammate (it holds %d)" % Stack.mine(stack),
	):
		return Vector2.INF
	var slot := Stack.slot_point(stack, 2)
	if not t.require(
			await Stack.walk(t, &"me", [slot], 10.0)
				and await t.until(func(): return _step(stack) == "ready", 3.0),
			"the human walks to its slot and is ready",
	):
		return Vector2.INF
	return slot


## The human steps into the funnel and back to its `slot`: `{ call }`, its going-in call of the
## brush, or {} when a step fails.
func _brush(t: TestContext, stack: Node, slot: Vector2, funnel: Vector2) -> Dictionary:
	if not t.require(
			await Stack.walk(t, &"me", [funnel], 8.0)
				and await t.until(func(): return _step(stack) == "going_in", 2.0),
			"the human steps into the doorway's funnel (going_in)",
	):
		return {}
	var brushed := _last_call(t, String(Entry.BACK["id"]), "going_in")
	if not t.require(
			await Stack.walk(t, &"me", [slot], 8.0)
				and await t.until(func(): return _step(stack) == "ready", 3.0),
			"and back to its slot (ready)",
	):
		return {}
	return { "call": brushed }


## The squad posts a held stack order to `a`, after the brush's crossing (`brushed`), and the
## puppet radios ready under it (`said`); the order, or {} when the set-up fails.
func _held_order(
		t: TestContext,
		squad: Node,
		a: Node,
		brushed: Dictionary,
		said: Dictionary,
) -> Dictionary:
	var order := Order.stack_order(squad, [a], Order.BACK_NORTH, "quiet", true)
	if not t.require(not order.is_empty(), "the squad posts the held stack order (issue)"):
		return {}
	t.check(
		int(brushed.get("crossed_frame", -1)) >= 0
			and int(brushed["crossed_frame"]) < int(order.get("frame", -1)),
		"set-up: the brush's crossing began before the order (crossed_frame %s, order frame %s)"
			% [brushed.get("crossed_frame"), order.get("frame")],
	)
	said["order"] = order
	said["step"] = "ready"
	await t.seconds(REPEAT * 2.0)
	if not t.require(
			_held(squad, a),
			"set-up: the squad says the order is held, the brush before it no go (%s)"
				% str(Order.member_view(squad, a)),
	):
		return {}
	return order


## The human's crossing since the order is the held stack's go.
func _check_go(
		t: TestContext,
		squad: Node,
		a: Node,
		opening: String,
		order: Dictionary,
) -> void:
	var stepped := _last_call(t, opening, "going_in")
	t.check(
		int(stepped.get("crossed_frame", -1)) >= int(order["frame"]),
		"its claim says the crossing began since the order (crossed_frame %s, order frame %s)"
			% [stepped.get("crossed_frame"), order["frame"]],
	)
	t.check(
		await t.until(func(): return not _held(squad, a), READ),
		"the human's latest crossing is the held stack's go: the squad no longer says held (%s)"
			% str(Order.member_view(squad, a)),
	)


## Keep the puppet `a` radioing its claim on slot 1 at doorway `door` every `REPEAT` s for the rest
## of the test: at `said.step`, under `said.order` once it holds one (the claim an ordered NPC's
## entry radios, in the wire format's field names, interface 10).
func _radio_on(t: TestContext, door: Dictionary, said: Dictionary) -> void:
	var c := t.actor(&"a")
	while is_instance_valid(c):
		var msg := {
			"speaker": c, "faction": c.faction, "position": c.global_position, "status": "",
			"path": "", "label": "", "target_id": 0, "point": c.global_position,
			"opening": door["id"], "into": door["room_key"], "slot": 1, "side": 1,
			"entry_step": said["step"],
		}
		var order: Dictionary = said["order"]
		if not order.is_empty():
			msg.merge({
				"into": order["into"], "order_id": order["id"], "order_mode": "quiet",
				"order_hold": true, "order_go": false, "order_frame": order["frame"],
			}, true)
		EventBus.post(&"callout", msg)
		await t.seconds(REPEAT)


## The human's own radio step, as its stack shows it.
func _step(stack: Node) -> String:
	return String(Stack.view(stack).get("step", ""))


## The human's latest call at step `step` about doorway `opening` ({} when none).
func _last_call(t: TestContext, opening: String, step: String) -> Dictionary:
	var calls := Stack.calls_at(t, &"me", opening).filter(
		func(d): return String(d.get("entry_step", "")) == step,
	)
	return calls[-1] if not calls.is_empty() else {}


## Whether the squad's `view()` says `member`'s order is held for the leader's go.
func _held(squad: Node, member: Node) -> bool:
	return bool(Order.member_view(squad, member).get("held", false))
