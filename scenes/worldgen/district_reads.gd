class_name DistrictReads
## World Generation domain: the test reads of a generated district (`WorldGen.generate_district`),
## beside `WorldGen`'s own (`house_of`, `district_rooms`, `district_bounds`): what it placed, as
## metadata of its root.


## The towers of a generated `district`, block 0 to 8 row by row (4 the house), each a dict of
## `block`, `plan`, `turn` (the quarter turns), `node` (the tower: a house node, `get_rooms` and the
## rest read it), `rect` (the bounds of its rooms), `front` (its front doorway), all in WORLD space,
## and, from TowerDressing, `shadow` (its street shadow sprite), `podium` (its band's pieces),
## `awning` and `sign` (the pieces over its front door). (A test read.)
static func get_towers(district: Node2D) -> Array:
	if district == null:
		return []
	return district.get_meta("towers", [])


## The shells of a generated `district` as `{ rect, node, holder }`: `rect` the shell's WORLD rect,
## `node` its outer wall and `holder` the node holding all of it. (A test read.)
static func get_shells(district: Node2D) -> Array:
	if district == null:
		return []
	return district.get_meta("shells", [])


## The street grid of a generated `district` as `{ kind, role, rect, node, block }`: `kind` `street`
## (asphalt: `role` `road` or `junction`) or `sidewalk` (round the block `block`), `rect` the
## piece's WORLD rect and `node` the floor that draws it. (A test read.)
static func get_district_street(district: Node2D) -> Array:
	if district == null:
		return []
	return district.get_meta("streets", [])
