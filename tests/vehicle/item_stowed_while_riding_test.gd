extends GameTest
## V3 (ticket #54): the held item is put away while seated and taken out again on exit. A character
## holding its pistol boards the car: from the moment it starts folding into the seat until it has
## stepped out again it holds nothing (`inventory.current_item()` null), and once out it has the
## same slot back in hand.

const Probe := preload("res://tests/_vehicle/vehicle_probe.gd")
const VehicleFrame := preload("res://tests/_vehicle/vehicle_frame_probe.gd")
const VehicleRide := preload("res://tests/_vehicle/vehicle_ride_probe.gd")
## The slot it holds before boarding (the pistol).
const SLOT := 3


func describe() -> Dictionary:
	return {
		"name": "The held item is put away while riding",
		"description": "A character holding its pistol boards a car: no item in hand from the fold "
			+ "into the seat until it is out again, then the pistol is back in hand.",
		"tags": ["vehicle", "car", "board", "exit", "item"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600), { "floor": "concrete" })
	s.switch(&"nav.rebake", false)
	s.vehicle(&"car", &"car", Vector2(450, 300))
	s.actor(&"me", &"puppet", Vector2(150, 80), { "start_slot": SLOT })


func run(t: TestContext) -> void:
	if not Probe.ready(t, &"car", [&"me"]):
		return
	var car := t.vehicle(&"car") as Node2D
	var me := t.actor(&"me")
	if not (Probe.has_reads(t, me.movement, [&"posture_folded"], "character me's movement")
			and Probe.has_reads(
				t, me.inventory, [&"current_item", &"current_slot"], "character me's inventory",
			)):
		return
	await t.seconds(0.3)
	if not t.require(
			me.inventory.current_item() != null and me.inventory.current_slot() == SLOT,
			"it starts with its pistol in hand (slot %d)" % me.inventory.current_slot(),
	):
		return
	var held_name: String = me.inventory.item_name()

	if not await _check_boarding(t, car):
		return
	await _check_seated(t)
	await _check_getting_out(t, held_name)


## Boarding: sampled every frame from the E press until seated, nothing in hand while it folds in
## (false: it never got in, the test has ended).
func _check_boarding(t: TestContext, car: Node2D) -> bool:
	var me := t.actor(&"me")
	await VehicleRide.place(t, &"me", VehicleFrame.stand_point(car, &"front_left"))
	t.puppet(&"me").use_vehicle()
	var folding_held := 0
	var folding := 0
	var deadline := t.time + 6.0
	while t.time < deadline and not me.use.is_in_vehicle():
		await t.frames(1)
		if me.use.vehicle() != null and float(me.movement.posture_folded()) > 0.05:
			folding += 1
			if me.inventory.current_item() != null:
				folding_held += 1
	if not t.require(me.use.is_in_vehicle(), "it gets in"):
		return false
	t.check(
		folding > 0 and folding_held == 0,
		"nothing in hand while it folds into the seat (held on %d of %d frames)"
			% [folding_held, folding],
	)
	return true


## A second seated, sampled every frame: nothing in hand.
func _check_seated(t: TestContext) -> void:
	var me := t.actor(&"me")
	var seated := 0
	var seated_held := 0
	var deadline := t.time + 1.0
	while t.time < deadline:
		await t.frames(1)
		seated += 1
		if me.inventory.current_item() != null:
			seated_held += 1
	t.check(
		seated_held == 0,
		"nothing in hand while seated (held on %d of %d frames)" % [seated_held, seated],
	)


## Getting out: still nothing in hand until it is out, then the same slot back (`held_name`).
func _check_getting_out(t: TestContext, held_name: String) -> void:
	var me := t.actor(&"me")
	t.puppet(&"me").use_vehicle()
	var out_held := 0
	var getting_out := 0
	var deadline := t.time + 8.0
	while t.time < deadline and me.use.vehicle() != null:
		getting_out += 1
		if me.inventory.current_item() != null and float(me.movement.posture_folded()) > 0.05:
			out_held += 1
		await t.frames(1)
	if not t.require(me.use.vehicle() == null, "it gets out"):
		return
	t.check(
		out_held == 0,
		"nothing in hand while it rises out of the seat (held on %d of %d frames)"
			% [out_held, getting_out],
	)
	await t.frames(2)
	t.check(me.inventory.current_item() != null, "once out it holds an item again")
	t.check(
		me.inventory.current_slot() == SLOT and me.inventory.item_name() == held_name,
		"the same one it put away (slot %d, %s; was slot %d, %s)"
			% [me.inventory.current_slot(), me.inventory.item_name(), SLOT, held_name],
	)
