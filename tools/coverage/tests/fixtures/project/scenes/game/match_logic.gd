extends RefCounted
## Fixture game logic Main calls: one function every match, a branch per seed parity, an arm per side count, the
## endless teardown, and a function nothing calls.


func every_match() -> int:
	return 1


func seed_parity(seed_value: int) -> String:
	if seed_value % 2 == 0:
		return "even"
	else:
		return "odd"


func side_count(count: int) -> int:
	match count:
		1:
			return 1
		2:
			return 2
		3:
			return 3
		4:
			return 4
		_:
			return 5


func endless_teardown() -> void:
	pass


## Nothing calls it.
func never_called() -> int:
	return 0
