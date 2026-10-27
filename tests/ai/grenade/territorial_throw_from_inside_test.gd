extends GameTest
## G17 with the territory (`docs/grenades.md`; `docs/flanking-behavior.md` B8): a grenade option is
## judged where it is thrown from, so a territorial defender inside the house may throw onto a spot
## outside it. One mechanism, scripted Von (GRENADE whenever COMBAT offers it): a defender with a
## frag stands inside by the front door, and its hostile stands just outside behind a desk that
## stops a bullet but not a lob or the defender's sight. GRENADE is offered at COMBAT, and the
## throw leaf's `from` is inside the house.
##
## The hostile stands 420 px off, outside a frag's 370 px zone, so the defender needs no cover from
## its own grenade. Switch: `ai.hostile_on_sight` on, so the defender holds the stranger it sees
## outside hostile without being shot at first (a defender's preset is hostile to a trespasser or
## an attacker only, and this one is neither). The rest of the AI is left on. Premises: the hostile
## is an invader *puppet* that cannot be killed and never shoots; the defender is armed with one
## frag here because the test world keeps the default inventory, the way Main arms a spawn.

const Probe := preload("res://tests/_ai/grenade_probe.gd")
const GrenadeAi := preload("res://tests/_ai/grenade_ai_probe.gd")
const HOUSE := Rect2(0, 0, 600, 500)
const DOOR := Vector2(300, 500)
const DEFENDER_AT := Vector2(300, 440)
const DESK_AT := Vector2(300, 800)
const HOSTILE_AT := Vector2(300, 860)


func describe() -> Dictionary:
	return {
		"name": "A territorial defender throws from inside onto a spot outside",
		"description": "A defender with a frag inside by the front door, its hostile hidden "
			+ "behind a desk just outside: GRENADE is offered at COMBAT and the throw is made "
			+ "from inside the house (G17, B8).",
		"tags": ["ai", "grenade", "combat", "territory", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(
		[{ "key": "hall", "type": "living_room", "rect": HOUSE }],
		[{ "pos": DOOR, "width": 60.0 }],
	)
	s.object(&"desk", "desk", DESK_AT)
	s.von_script([{ "pick": "combat" }, { "pick": "grenade" }])
	s.switch(&"ai.hostile_on_sight", true)
	s.actor(&"d", &"defender", DEFENDER_AT, { "facing": Vector2.DOWN })
	GrenadeAi.hostile(s, &"h", HOSTILE_AT, DEFENDER_AT, { "faction": &"invader" })


func run(t: TestContext) -> void:
	var d := t.actor(&"d")
	Probe.arm(d, 0, 1)
	if not t.require(
			Probe.count(d, Probe.FRAG) == 1,
			"the defender carries a frag (item_count(8) = %d)" % Probe.count(d, Probe.FRAG),
	):
		return
	t.check(
		not GrenadeAi.line_clear(t, DEFENDER_AT, HOSTILE_AT),
		"set-up: the desk stands across the defender's line of fire",
	)
	var brain := t.controller(&"d", &"debug_state")
	if not t.require(
			await t.until(func() -> bool: return not _combat_asks().is_empty(), 10.0),
			"Von was asked how to fight (act %s, asks %s)"
				% [
					brain.current_act(),
					str(DecisionStub.requests.map(func(r): return r["options"])),
				],
	):
		return
	var offered: Array = _combat_asks()[0]["options"]
	t.check(offered.has("grenade"), "GRENADE is offered at COMBAT (offered %s)" % str(offered))
	var seen: Array = []
	if not t.require(
			await GrenadeAi.wait_act(t, &"d", "grenade", 5.0, seen),
			"the defender took the GRENADE tactic (its acts: %s)" % str(seen),
	):
		return
	var from: Array = brain.debug_state().get("params", {}).get("from", [])
	t.check(
		from.size() == 2 and HOUSE.has_point(Vector2(from[0], from[1])),
		"the throw is made from inside the house (from %s)" % str(from),
	)


## The scripted Von's COMBAT asks so far (the tactic level: "How should you fight ...").
func _combat_asks() -> Array:
	return DecisionStub.requests.filter(func(r: Dictionary) -> bool:
		return String(r["question"]).begins_with("How should you fight"))
