extends StaticBody2D

var wall_thickness := 24.0
var look := Look.new()

## Test probe (not a test): a wall-kind body (it has a `wall_thickness`) that also carries a
## `look.art`, as a furniture piece does, to prove the mirror's finer hook key (`furniture:<art>`)
## is for furniture alone and never answers another kind.


class Look:
	var art := "table"
