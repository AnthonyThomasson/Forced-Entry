extends GameTest
## LD9 / D10 (`docs/leadership.md`): an unordered member that joins an ordered stack follows the
## order's mode and side. The squad is built and bound as a match's (`s.squads`, a puppet standing
## in for the human leader, its `PlayerStack` claiming as Main's does, D29). The human steps up
## north of the Terrace house's back door: its own claim rallies its team (LD24), and the joiner,
## running the join as its own unordered entry, claims its slot north of the door first, in bang
## mode (the human's claim says nothing of a bang, so it never vetoes one: the stack's first
## claimers chose a bang). Then the human orders the teammate to stack on the same door south of it,
## quietly. Unordered, the first claimers set a stack's side and mode; with an ordered claim in the
## team, the order's do: the joiner's later claims are quiet and on the order's side, and it stacks
## south of the door.
##
## Scripted Von (`Entry.rules`; the join's and the order's levels ask nothing). Premises: the
## ordered member carries a stun the way Main arms a spawn (so once it claims, the stack has a
## grenade for the bang its first claimers chose, and only the order's mode makes the joiner quiet);
## it starts far off in the south of the garden, so the joiner has claimed first.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Order := preload("res://tests/_ai/order_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "An unordered joiner follows the ordered stack's mode and side",
		"description": "An invader that joined its human leader's stack north of the back door in "
			+ "bang mode follows a teammate's later order to stack south quietly: its claims turn "
			+ "quiet and to the order's side, and it stacks south (LD9, D10).",
		"tags": ["ai", "entry", "leadership", "order", "join", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	s.actor(&"joiner", &"invader", Vector2(960, 60))
	s.actor(&"ordered", &"invader", Vector2(990, 600))
	Stack.human(s, &"lead", Vector2(930, 40), { "aim_point": Order.BACK_NORTH })
	s.squads({ "human": &"lead" })


func run(t: TestContext) -> void:
	Probe.arm(t.actor(&"ordered"), 1, 0)
	if not t.require(
			Probe.count(t.actor(&"ordered"), Probe.STUN) == 1,
			"the ordered member carries a stun (Character.item_count(7))",
	):
		return
	var squad := t.squad(&"invader")
	t.puppet(&"lead").walk_to(Order.BACK_NORTH)
	if not t.require(
			await t.until(func(): return not Entry.calls(t, "claim", &"joiner").is_empty(), 12.0),
			"the joiner, rallied by the human's own claim, claims the back door first (premise)",
	):
		return
	var first: Dictionary = Entry.calls(t, "claim", &"joiner")[0]
	if not t.require(
			first.get("bang") == true and str(first.get("order_id", "")) == "",
			"set-up: its claim is in bang mode and unordered (a join's, LD24)",
	):
		return
	var order := Order.issue(
		squad,
		{
			"kind": Order.STACK,
			"to": [t.actor(&"ordered")],
			"pos": Order.BACK_SOUTH,
			"bang": false,
		},
	)
	if not t.require(not order.is_empty(), "the squad posts the order (issue)"):
		return
	var ordered_at := await _first_ordered_claim(t)
	if not t.require(ordered_at < INF, "the ordered member claims the back door under the order"):
		return
	await _joiner_follows_order(t, ordered_at)


## Checks the joiner's claims after the order's (at `ordered_at`) take the order's mode and side,
## and it stacks on that side.
func _joiner_follows_order(t: TestContext, ordered_at: float) -> void:
	var joiner := t.actor(&"joiner")
	await t.seconds(3.0)
	var later: Array = Order.raw_calls(t, joiner).filter(
		func(e): return float(e["time"]) > ordered_at + 1.0,
	)
	if not t.require(not later.is_empty(), "the joiner kept radioing its claim after the order's"):
		return
	t.check(
		later.all(func(e): return e["data"].get("bang") == false),
		"the joiner's later claims are quiet, the order's mode (%s)"
			% str(later.map(func(e): return e["data"].get("bang"))),
	)
	var ordered_side = Order.ordered_claims(t, t.actor(&"ordered"), Entry.BACK["id"])[0].get("side")
	t.check(
		later.all(func(e): return e["data"].get("side") == ordered_side),
		"on the order's side (%s, the joiner's: %s)"
			% [str(ordered_side), str(later.map(func(e): return e["data"].get("side")))],
	)
	t.check(
		await t.until(
			func(): return (
				Order.stacked(t, &"joiner") and Order.back_side(joiner.global_position) == "south"
			),
			20.0,
		),
		"the joiner stacks south of the door, the order's side (at %s)"
			% str(joiner.global_position.round()),
	)


## The sim time of the ordered member's first claim carrying an order_id at the back door (waiting
## up to 10 s), or INF.
func _first_ordered_claim(t: TestContext) -> float:
	var who := t.actor(&"ordered")
	await t.until(
		func(): return not Order.ordered_claims(t, who, Entry.BACK["id"]).is_empty(),
		10.0,
	)
	return Order.first_time(
		t,
		&"callout",
		func(d): return (
			d.get("speaker") == who
				and str(d.get("order_id", "")) != ""
				and String(d.get("opening", "")) == Entry.BACK["id"]
		),
	)
