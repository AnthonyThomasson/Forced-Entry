extends RefCounted
## The forms issue #68 had not tried before this fixture: lambdas written inside a call's arguments (inline and over
## several lines), a static func, inner classes (one nested in another), a multi-line signature, strings that hold
## a `#`, and a function nothing calls.

const LABEL := "edge # not a comment"


class Counter:
	var n := 0

	func bump() -> int:
		n += 1
		return n

	class Nested:
		static func twice(x: int) -> int:
			return x * 2


static func helper(a: int) -> int:
	return a + 1


func signature(a: int,
		b: int,
		c: int) -> int:
	return a + b + c


func run() -> int:
	var arr := [1, 2, 3]
	var doubled := arr.map(func(x): return x * 2)
	var tripled := arr.map(func(x):
		var y = x * 3
		return y
	)
	var text := "a # b"; var hashes := text.count("#")
	var counter := Counter.new()
	counter.bump(); counter.bump()
	return doubled.size() + tripled.size() + hashes + LABEL.length() + Counter.Nested.twice(2) + helper(1) + signature(1, 2, 3)


func never_called() -> int:
	return 0
