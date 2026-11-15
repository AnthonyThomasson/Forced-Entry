class_name PieceQueue
extends RefCounted
## Physics domain, a first-in first-out line of pieces (or anything) with an advancing head instead
## of a front-pop: the oldest leaves in constant time, and the consumed prefix is folded away only
## now and then, so a capped store churned for ever stays bounded. The 3D effects keep what lies
## (chips, blood) in one, oldest first, to drop the oldest past the `Despawner`'s cap.

## What it holds, and how many of the front are already gone.
var _items: Array = []
var _oldest := 0


## File `item` as the newest.
func append(item: Variant) -> void:
	_items.append(item)


## Remove and return the oldest (null when empty).
func pop() -> Variant:
	if size() == 0:
		return null
	var item: Variant = _items[_oldest]
	_items[_oldest] = null
	_oldest += 1
	if _oldest >= 64 and _oldest * 2 >= _items.size():
		_items = _items.slice(_oldest)
		_oldest = 0
	return item


## The oldest, left in place (null when empty).
func oldest() -> Variant:
	return _items[_oldest] if size() > 0 else null


## How many it holds.
func size() -> int:
	return _items.size() - _oldest


## What it holds, oldest first: a list of the caller's own.
func items() -> Array:
	return _items.slice(_oldest)
