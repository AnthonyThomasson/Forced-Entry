extends GameTest
## #193 phase 3 (L2 in 3D): a lamp's pool ends in a soft tail, as the 2D one does, and not on a hard
## flat disc. The pool's bands (`ToonLightConfig.pool_levels`, what the shader's `pool_levels` holds
## times `pool_strength`) climb from a trace to the light whole in at least seven small steps: the
## dimmest is under a sixth of the brightest, no step is more than a third of it, and the shader
## reads them all.

const Bands := 7


func describe() -> Dictionary:
	return {
		"name": "A toon pool fades to nothing in small steps",
		"description": "The pool's band strengths climb from a trace to the light whole, none a "
			+ "jump of more than a third of the top, so the rim of a pool is soft.",
		"tags": ["art", "lighting", "3d"],
		"timeout": 4.0,
	}


func run(t: TestContext) -> void:
	var rows := ToonLightConfig.pool_levels
	var strength := ToonLightConfig.pool_strength
	t.check(rows.size() >= Bands and rows.size() <= 8, "the pool has %d bands" % rows.size())
	var top := float(rows[rows.size() - 1]) * strength
	t.check(float(rows[0]) * strength <= top / 6.0, "the dimmest band is a trace of the top")
	var worst := float(rows[0]) * strength
	for k in range(1, rows.size()):
		t.check(
			float(rows[k]) >= float(rows[k - 1]),
			"band %d is no darker than band %d" % [k, k - 1],
		)
		worst = maxf(worst, (float(rows[k]) - float(rows[k - 1])) * strength)
	t.check(
		worst <= top / 3.0,
		"no step is more than a third of the top (%.2f of %.2f)" % [worst, top],
	)
	var pooled := ToonLightConfig.pool()
	t.expect_eq(pooled.size(), 8, "the shader's eight slots")
	t.expect_near(pooled[rows.size() - 1], top, 0.001, "the last band is the light whole")
