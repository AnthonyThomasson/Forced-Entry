extends GameTest
## D19 (#194 flatdoor): in the gun range sandbox a door shot flat could not be walked on: the human
## shoved the leaf along ahead of it. A door lying flat (its top within a step over) is walk-over
## (`docs/doors.md` DR11): in the range's own layout and arming the human shoots each door that can
## fall (the flush hollow one, the glass one: the steel one stops rounds, the solid one is ajar)
## down with the rifle from the range, then holds W through its doorway: the human keeps its pace
## over the leaf and the leaf stays where it lay.

const GunRange := preload("res://sandboxes/player_gun_range_sandbox.gd")
const Probe := preload("res://tests/_objects/piece_probe.gd")
const PlayerPointer := preload("res://tests/_character/player_pointer_probe.gd")
## The range doors that fall to a rifle (indices of `RANGE_DOORS`).
const DOORS := [0, 3]
## How far (px) the aim may sit off the door's ground point: with the picture shown the player
## aims at the standing door's face, which the cursor's line meets 3 px before it (the window).
const DOOR_FACE := 6.0
## The firing spot south of a doorway (px of y).
const FIRE_FROM := 140.0
## How long W is held (s): at the walking pace (about 100 px/s) it covers 250 px, from the firing
## spot to well beyond where the leaf lies in the room.
const HOLD := 2.5
## Where the walk must have got to (px of y): the human ends about 230 px north of the doorway's
## row; shoving the leaf along ahead of it (before the fix) it was held to about 70.
const REACHED := -150.0
## The most the leaf may be shoved by the walk (px).
const MOVED := 5.0


func describe() -> Dictionary:
	return {
		"name": "The player walks over a door it shot flat in the gun range",
		"description": "The human shoots a range door down from the range with the rifle, it lies "
			+ "flat, and the human walks across its doorway into the room at its pace over the "
			+ "leaf without moving it.",
		"tags": ["door", "objects", "player"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	s.layout(GunRange._rooms(), GunRange._doorways())
	s.actor(&"you", &"player", Vector2(240, 320), { "start_slot": 6 })
	s.camera_follow([&"you"])


func run(t: TestContext) -> void:
	await t.seconds(0.5)
	var you := t.actor(&"you")
	for i: int in DOORS:
		var door_name: String = GunRange.RANGE_DOORS[i]["name"]
		var door = t.object(StringName(door_name))
		var x: float = GunRange._room_centre_x(i)
		you.global_position = Vector2(x, FIRE_FROM)
		await t.frames(5)
		await PlayerPointer.aim(t, you, Vector2(x, 0.0), DOOR_FACE)
		for _shot in 12:
			if door.is_down():
				break
			Input.action_press(Keybinds.FIRE)
			await t.frames(3)
			Input.action_release(Keybinds.FIRE)
			await t.seconds(0.3)
		Pointer.release()
		if not t.require(door.is_down(), "%s is shot down" % door_name):
			return
		await Probe.settle(t, door, 10.0)
		t.require(door.footprint.flat, "%s lies flat (top %.1f px)" % [door_name, Probe.top(door)])
		var lay := Probe.middle(door)
		you.global_position = Vector2(x, FIRE_FROM)
		await t.frames(5)
		Input.action_press(Keybinds.MOVE_UP)
		await t.seconds(HOLD)
		Input.action_release(Keybinds.MOVE_UP)
		var shoved := Probe.middle(door).distance_to(lay)
		t.check(
			you.global_position.y < REACHED,
			"%s: the player kept its pace over the leaf (ended %s)" % [
				door_name,
				you.global_position,
			],
		)
		t.check(shoved < MOVED, "%s: the leaf was not shoved (moved %.0f px)" % [door_name, shoved])
