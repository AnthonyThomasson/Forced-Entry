class_name WeightedPick
## General domain: the weighted roll, shared infrastructure (like `FillBatch`) for any domain that
## draws one entry of several by weight (World-Gen's dressing, Objects' wear, Lighting's rhythms,
## Character's style). A roll takes one `rng.randf()` and lands in [0, total of the weights]; each
## entry, in order, takes the next stretch of it. `strict` sets the two edges, which each caller
## keeps as its own: false, a roll on the end of a stretch takes that entry and one past them all
## (float rounding, or a roll of exactly 1) takes the last; true, it takes the next entry and one
## past them all takes the first.


## The `key_index` value of a row of `rows` (each an Array), drawn by `rng` by the row's
## `weight_index` value.
static func pick(
	rng: RandomNumberGenerator,
	rows: Array,
	key_index := 0,
	weight_index := 1,
	strict := false,
) -> Variant:
	return rows[index(rng, rows, weight_index, strict)][key_index]


## A key of `weights` (key -> weight), drawn by `rng` by its weight, the keys in their order.
static func key(rng: RandomNumberGenerator, weights: Dictionary, strict := false) -> Variant:
	var rows: Array = []
	for k in weights:
		rows.append([k, weights[k]])
	return pick(rng, rows, 0, 1, strict)


## The index of a row of `rows` (each an Array), drawn by `rng` by the row's `weight_index` value.
static func index(
	rng: RandomNumberGenerator,
	rows: Array,
	weight_index := 1,
	strict := false,
) -> int:
	var total := 0.0
	for row: Array in rows:
		total += float(row[weight_index])
	var roll := rng.randf() * total
	for i in rows.size():
		roll -= float(rows[i][weight_index])
		if roll < 0.0 if strict else roll <= 0.0:
			return i
	return 0 if strict else rows.size() - 1
