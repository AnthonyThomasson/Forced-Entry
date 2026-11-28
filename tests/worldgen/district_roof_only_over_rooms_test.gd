extends GameTest
## D11a: a roof is over a room and over nothing else of a district (`Floor.roofed`, the twin space's
## `TWIN_ROOF` layer): a ray from the sky onto the middle of a room of the towers lands on a roof,
## and onto a roofless shell or a road it reaches no roof, so a lob over the street
## or into a shell is never capped (`GrenadeArc._top`).

const Probe := preload("res://tests/_general/twin_probe.gd")
const SEED := 7
const PLAN := "garage_home"
## The walls' height: where a roof is, and the open sky has none.
const WALLS := 96.0
## The most street pieces looked at.
const STREET_PIECES := 12


func describe() -> Dictionary:
	return {
		"name": "A district has a roof over its rooms, none over a shell or the street",
		"description": "A ray from the sky strikes a roof over the middle of each room of the "
			+ "district's towers, and none over the middle of a shell or of a road or junction.",
		"tags": ["worldgen", "district", "twins", "3d", "roof"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.district(SEED, PLAN)
	s.von_down()
	s.declared_match({ "defenders": { "count": 1 }, "invaders": { "count": 1 } })


func run(t: TestContext) -> void:
	var district := t.world.match_handle.get("district") as Node2D
	if not t.require(district != null, "the world holds the district"):
		return
	await t.frames(3)
	var roofs := PhysicsLayers.TWIN_ROOF
	var rooms := WorldGen.district_rooms(district)
	var roofed := 0
	for room: Dictionary in rooms:
		if Probe.top_at(t, (room["rect"] as Rect2).get_center(), roofs) >= WALLS:
			roofed += 1
	t.check(
		roofed == rooms.size(),
		"a roof is over every room of the towers (%d of %d)" % [roofed, rooms.size()],
	)
	var bare := 0
	var shells := DistrictReads.get_shells(district)
	for shell: Dictionary in shells:
		if Probe.top_at(t, (shell["rect"] as Rect2).get_center(), roofs) > -500.0:
			bare += 1
	t.check(not shells.is_empty() and bare == 0, "no roof is over a shell (%d roofed)" % bare)
	var pieces := DistrictReads.get_district_street(district).filter(
		func(piece: Dictionary) -> bool: return piece["kind"] == "street"
	)
	var seen := 0
	for piece: Dictionary in pieces.slice(0, STREET_PIECES):
		seen += 1
		if Probe.top_at(t, (piece["rect"] as Rect2).get_center(), roofs) > -500.0:
			bare += 1
	t.check(seen > 0 and bare == 0, "nor over a road or a junction (%d roofed in all)" % bare)
