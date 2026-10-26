extends RefCounted
## Shared fixtures of the stack module's native suites (not a test itself): `const StackRadio :=
## preload("res://tests/_ai/stack_radio_probe.gd")`. The speakers on the radio and the callouts they
## make, which `tests/ai/stack_claim_suite.gd` and `tests/ai/door_stack_suite.gd` feed the stack
## module (`scenes/ai/perception/stack/`) as plain dicts.


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


## A character on the radio as a listener reads it.
class Speaker:
	extends Node

	var is_dead := false
