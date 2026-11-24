extends GameTest
## Interface 9, #194 nav3d-b: a plan polygon (the planning region of a district) laid on one scratch
## map through the 2D API (`NavigationServer2D`) and on another through the nav's own path
## (`NavPlan.assign`, a `NavigationRegion3D`, `NavPlan` queries) gives the same closest points and
## routes, to the point: a grid of probes and a stride of ordered pairs of them (`NavQueryProbe`).
## What the nav adds to the engine's own conversion is what this pins; a mesh made wrongly (a vertex
## lifted to the wrong place, a polygon dropped, a cell the map does not take) shows here.


func describe() -> Dictionary:
	return {
		"name": "A district's plan polygon answers alike through the 2D API and through NavPlan",
		"description": "The planning region's polygon on a scratch map through NavigationServer2D "
			+ "and on another through NavPlan.assign: equal closest points and routes.",
		"tags": ["navigation", "district"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.district(7)


func run(t: TestContext) -> void:
	await t.seconds(1.0)
	await NavQueryProbe.compare(t, "district", NavWorld.map_of(t.world))
