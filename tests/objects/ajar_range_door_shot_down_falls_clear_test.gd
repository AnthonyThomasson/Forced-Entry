extends GameTest
## D18 / DR11 (#194 flatdoor): once a door is down its doorway is clear. The gun range's solid
## panelled door stands ajar 30 degrees out onto the range; the human shoots it down from the range
## with the rifle and the leaf falls out of its frame (it may lean on something beyond, it does not
## stay wedged in the jambs): the doorway is as wide clear as it is free between the jambs.
## The sandbox's own layout and arming, as `player_walks_over_a_fallen_range_door`.

const GunRange := preload("res://sandboxes/player_gun_range_sandbox.gd")
const Probe := preload("res://tests/_objects/piece_probe.gd")
const PlayerPointer := preload("res://tests/_character/player_pointer_probe.gd")
const DOOR := 1
const FIRE_FROM := 140.0
## The free gap between the doorway's jambs (px: `DOORWAY` less the walls' 6 px ends each side).
const FREE_GAP := 48.0


func describe() -> Dictionary:
	return {
		"name": "The gun range's ajar solid door shot down falls clear of its frame",
		"description": "The human shoots the ajar solid door down from the range with the rifle: "
			+ "the leaf is not wedged in the doorway, which is clear.",
		"tags": ["door", "objects", "player"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(GunRange._rooms(), GunRange._doorways())
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })
	s.camera_follow([&"you"])


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var you := t.actor(&"you")
	var door = t.object(&"door_solid_panelled")
	var x: float = GunRange._room_centre_x(DOOR)
	var aim: Vector2 = door.global_position
	you.global_position = Vector2(x, FIRE_FROM)
	await t.frames(5)
	await PlayerPointer.aim(t, you, aim)
	for _shot in 30:
		if door.is_down():
			break
		Input.action_press(Keybinds.FIRE)
		await t.frames(3)
		Input.action_release(Keybinds.FIRE)
		await t.seconds(0.3)
	Pointer.release()
	if not t.require(door.is_down(), "the ajar solid door is shot down"):
		return
	await Probe.settle(t, door, 10.0)
	t.check(
		door.gap() >= FREE_GAP - 1.0,
		"the doorway is clear of the fallen leaf (%.0f of %.0f px; top %.0f, lean %.0f)"
			% [door.gap(), FREE_GAP, Probe.top(door), Probe.lean(door)],
	)
