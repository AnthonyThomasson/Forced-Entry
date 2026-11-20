extends GameTest
## V3 and V5 (`docs/player-vision.md`, #194 D9): a character inside the cone is drawn only if one
## of its body points (head, chest, hips at its posture) is clear from the viewer's eye. A standing
## enemy right behind a sofa (back 38 px, facing the viewer) is drawn; the same enemy ducked
## (eye point 32 px, 24 px chest, 18 px hips, as seen from an eye 69 px up 450 px away) is not,
## though the cone reaches it; it is drawn again as it stands.

const Probe := preload("res://tests/_vision/vision_probe.gd")
const EYE_AT := Vector2(150, 350)
const SOFA_AT := Vector2(600, 350)
const ENEMY_AT := Vector2(645, 350)
const OPEN_AT := Vector2(645, 150)

var _mirror: MeshCarrier


func describe() -> Dictionary:
	return {
		"name": "A ducked enemy behind a sofa in the cone is not drawn",
		"description": "A standing enemy behind a sofa in the cone is drawn and a ducked one is "
			+ "hidden, drawn again when it stands; one ducked in the open is drawn.",
		"tags": ["vision", "mirror", "3d", "heights", "posture"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 600))
	s.switch(&"vision.enabled", true)
	s.switch(&"nav.rebake", false)
	s.object(&"sofa", "sofa", SOFA_AT, { "facing": Vector2.RIGHT, "rotated": true })
	s.actor(&"eye", &"puppet", EYE_AT)
	s.actor(&"enemy", &"puppet", ENEMY_AT)
	s.actor(&"open", &"puppet", OPEN_AT)
	s.view(&"eye")


func run(t: TestContext) -> void:
	var eye := t.actor(&"eye")
	if not t.require(
		await Probe.place(t, eye, EYE_AT, Vector2.RIGHT),
		"premise: the viewer faces east",
	):
		return
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	_mirror = MeshCarrier.new()
	view.add_child(_mirror)
	CharacterMeshes.register(_mirror.builders)
	_mirror.carry(t.world)
	await t.frames(4)
	var enemy := _shown_of(t.actor(&"enemy"))
	var open := _shown_of(t.actor(&"open"))
	if not t.require(enemy != null and open != null, "premise: both are mirrored"):
		return
	t.check(Probe.reached_by(ENEMY_AT), "premise: the cone reaches the enemy behind the sofa")
	t.check(enemy.visible, "a standing enemy behind the sofa is drawn")
	t.require(t.actor(&"enemy").movement.set_posture(&"crouch"), "premise: it can duck")
	t.require(t.actor(&"open").movement.set_posture(&"crouch"), "premise: the other can duck")
	await t.frames(6)
	t.check(Probe.reached_by(ENEMY_AT), "the cone still reaches the ducked enemy")
	t.check(not enemy.visible, "a ducked enemy behind the sofa is not drawn")
	t.check(open.visible, "a ducked enemy in the open is drawn")
	t.require(
		await t.until(func(): return t.actor(&"enemy").movement.set_posture(&"stand"), 3.0),
		"premise: the enemy stands up",
	)
	await t.frames(6)
	t.check(enemy.visible, "the enemy is drawn again as it stands")


## The one mesh `body` is shown by (null: the test ends).
func _shown_of(body: Node) -> Node3D:
	var found := _mirror.proxies_of(body)
	return null if found.is_empty() else found[0]
