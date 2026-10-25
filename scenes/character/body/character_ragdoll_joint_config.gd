class_name CharacterRagdollJointConfig
## The ragdoll's joints (scenes/character/body/character_ragdoll.gd): each swing joint's limits and
## each hinge's bend and slack, in degrees. A `class_name` holder of `static var`s, read as
## `CharacterRagdollJointConfig.<name>`; there is no instance and no autoload.

## Joint limits: how far each bone may swing off its rest (neck up; arms and legs down) toward the
## front / back / the body's outside / across it, and each hinge's bend range plus the twist out of
## its plane it allows (the elbow's stands in for the upper arm's roll; the knee barely twists).
static var neck_limits: Dictionary = {
	"front": 50.0, "back": 45.0, "out": 40.0, "in": 40.0,
}
static var shoulder_limits: Dictionary = {
	"front": 170.0, "back": 60.0, "out": 160.0, "in": 40.0,
}
static var hip_limits: Dictionary = {
	"front": 120.0, "back": 25.0, "out": 35.0, "in": 30.0,
}
static var elbow_bend: Vector2 = Vector2(0.0, 145.0)
static var elbow_slack: float = 70.0
static var knee_bend: Vector2 = Vector2(0.0, 150.0)
static var knee_slack: float = 20.0
