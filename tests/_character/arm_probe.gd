extends RefCounted
## Shared helper for the long-gun Character tests (not a test itself):
## `const Arms := preload("res://tests/_character/arm_probe.gd")`. Whatever a held gun does to the
## hands, both arms keep (about) their configured length (`check_lengths`).

const Rig = preload("res://scenes/character/body/character_rig.gd")
## How far a bone may differ from its configured length (fraction), as in the standing-body rig
## test.
const BONE_TOLERANCE := 0.06


## Both arms of character `c` keep (about) their configured length; `when` heads each message.
static func check_lengths(t: TestContext, c: Node, when: String) -> void:
	var rig = c.anatomy.rig()
	var r: float = c.radius
	var bones := [
		["upper arm", Rig.SHOULDER, Rig.ELBOW, CharacterBodyConfig.upper_arm],
		["forearm", Rig.ELBOW, Rig.HAND, CharacterBodyConfig.forearm],
	]
	for i in 2:
		for bone in bones:
			var want: float = bone[3] * r
			var got: float = rig.point(bone[1][i]).distance_to(rig.point(bone[2][i]))
			t.check(absf(got / want - 1.0) <= BONE_TOLERANCE,
				"%s: the %s (side %d) is %.1f px, want %.1f" % [when, bone[0], i, got, want])
