extends RefCounted
## Every statement form issue #68 verified on Godot 4.4 headless before this fixture: a simple and a compound
## statement, if / elif / else and match-arm bodies, one-line bodies, a multi-line lambda in a variable, a statement
## wrapped over several lines and the one after it, for and while bodies.


func run(v: int) -> int:
	var total := 0
	if v > 2:
		total += 1
	elif v > 0:
		total += 2
	else:
		total += 3
	if v > 5: total += 10
	elif v > 2: total += 20
	else: total += 30
	match v:
		3:
			total += 100
		_:
			total += 200
	match v:
		1: total += 1
		3: total += 3
	for i in v:
		total += i
	for i in 2: total += i
	var n := 0
	while n < 2:
		n += 1
	while n < 4: n += 1
	var f := func(x: int) -> int:
		var y := x * 2
		return y
	total += f.call(1)
	total += _sum(1,
			2,
			3)
	total += n
	return total


func _sum(a: int, b: int, c: int) -> int:
	return a + b + c
