class_name NavTurns extends RefCounted
## Navigation domain, all static: whose re-bake may start (`NavBake`, `rebake.md`, "A bake waits
## its turn"). At most `NavBakeConfig.at_once` bakes hold a place, from start to landing; the rest
## wait here and start the oldest first as places free, so none starves: with `q` ahead of it a bake
## starts within `q / at_once + 1` turns of the longest count.

## The bakes waiting for a place, the oldest first.
static var _waiting: Array[NavBake] = []


## Put `bake` at the back of the line; `admit` starts it when its turn comes (at once, with a place
## free and nothing ahead).
static func wait(bake: NavBake) -> void:
	_waiting.append(bake)


## Give the waiting bakes their turn, the oldest first, while `flying` (the bakes between start and
## landing, which a bake that starts joins) leaves a place. One whose region is gone is let go
## without a place.
static func admit(flying: Array[NavBake]) -> void:
	while not _waiting.is_empty():
		var bake := _waiting[0]
		if bake.standing() and _taken(flying) >= NavBakeConfig.at_once:
			return
		_waiting.pop_front()
		bake.take_turn()


## Let every waiting bake go unstarted (the game is closing).
static func forget() -> void:
	_waiting.clear()


## The places held in `flying`.
static func _taken(flying: Array[NavBake]) -> int:
	var taken := 0
	for bake in flying:
		if bake.holds_place():
			taken += 1
	return taken
