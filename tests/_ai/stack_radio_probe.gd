extends RefCounted
## Shared fixtures of the stack module's native suites (not a test itself): `const StackRadio :=
## preload("res://tests/_ai/stack_radio_probe.gd")`. The speakers on the radio (`Speaker` nodes),
## the plain callout dicts they make and the claims a listener decodes from them, and a plain
## doorway, which `tests/ai/stack_claim_suite.gd`, `tests/ai/door_stack_suite.gd` and
## `tests/ai/stack_member_suite.gd` feed the stack module (`scenes/ai/perception/stack/`).

const StackClaim := preload("res://scenes/ai/perception/stack/stack_claim.gd")


## A speaker on the radio: a character as a listener reads it (`is_dead`), freed with `suite`'s
## case.
static func speaker(suite: GdUnitTestSuite, dead := false) -> Speaker:
	var s: Speaker = suite.auto_free(Speaker.new())
	s.is_dead = dead
	return s


## A callout from speaker `from` of side `faction` at `pos` with `fields` (its claim or other
## fields) over the header every callout carries.
static func callout(
	from: Node,
	fields: Dictionary,
	pos := Vector2(100, 50),
	faction := &"invader",
) -> Dictionary:
	var out := {
		"speaker": from, "faction": faction, "position": pos, "status": "", "path": "",
		"label": "", "target_id": 0, "point": pos,
	}
	out.merge(fields, true)
	return out


## A doorway in a wall along x at the origin into the hall, the stack's side out along +y: each
## side's file of six slots against the wall, 30 px apart from 40 px off the door (agent_entry.gd
## `geometry`, its `wall` kind).
static func door() -> Dictionary:
	var files := {}
	for s in [1, -1]:
		files[s] = range(1, 7).map(func(n): return { "point": slot_at(s, n), "row": 1 })
	return {
		"id": "o_1", "into": "hall", "pos": Vector2.ZERO, "out": Vector2(0, 1),
		"along": Vector2(1, 0), "width": 40.0, "side": 0, "kind": "wall", "files": files,
		"row1": { 1: 6, -1: 6 }, "wall_n": 6,
	}


## The point of the `place`th slot of side `side`'s file of `door()`.
static func slot_at(side: int, place: int) -> Vector2:
	return Vector2(side * (40 + 30 * (place - 1)), 12)


## `from`'s claim on `door()` as a listener holds it (`StackClaim.decode`): `fields` over a
## claim at step `claim`, heard from (0, 200).
static func claim(from: Node, fields: Dictionary) -> Dictionary:
	var wire := StackClaim.encode(
		{ "opening": "o_1", "into": "hall", "entry_step": "claim" }.merged(fields, true),
	)
	return StackClaim.decode(callout(from, wire, Vector2(0, 200)))


## A character on the radio as a listener reads it.
class Speaker:
	extends Node

	var is_dead := false
