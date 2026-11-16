extends GameTest
## A thing that moves is marked for the shaders to cut it at the cone's edge (#193 vision-mask,
## `MeshNodes.moving`, `toon_common.gdshaderinc`'s `moving` instance uniform,
## `docs/player-vision.md` V12): the shader's discard reads the mark, so a mark that is missing
## draws a mover (or a bullet) whole outside the cone. Asserted on the instance uniform of what is
## shown: the mesh the mirror shows a mover by while a view is on (and not a table, and not once the
## view is off), the bullet batch, a burst's bits and sparks, a blast's parts, and a part added
## later under a marked node. What the shader makes of the mark is judged windowed
## (`vision/vision_mask_3d_windowed`).

const SCRATCH := "user://settings_moving_mark_test.json"
const MOVER_AT := Vector2(300, 300)
const TABLE_AT := Vector2(600, 300)


func describe() -> Dictionary:
	return {
		"name": "What moves is marked for the view's cut, what stays is not",
		"description": "With a view on, a mirrored mover, the bullet batch, a burst's bits and "
			+ "sparks and a blast's parts carry the moving mark, a table does not, the mover "
			+ "loses it with the view, and a part added later under a marked node takes it.",
		"tags": ["mirror", "3d", "render", "vision"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"nav.rebake", false)
	s.set_static(Settings, &"path", SCRATCH)
	s.set_static(Settings, &"setup", {})
	s.set_static(Settings, &"overlays", {})
	s.set_static(Settings, &"debug", false)
	s.actor(&"mover", &"puppet", MOVER_AT)
	s.object(&"table", "coffee_table", TABLE_AT)
	s.von_script([])


func run(t: TestContext) -> void:
	_view_on()
	await _mirrored(t)
	_batches(t)
	_added_later(t)
	ToonMask.clear()


## A mask is set, as the view sets it, so the mirror marks its movers.
func _view_on() -> void:
	var white := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	ToonMask.set_mask(ImageTexture.create_from_image(white), Rect2(0, 0, 1000, 700), 0.0)


func _mirrored(t: TestContext) -> void:
	var view := SubViewport.new()
	view.own_world_3d = true
	t.world.add_child(view)
	var mirror := WorldMirror.new()
	view.add_child(mirror)
	mirror.mirror(t.world)
	await t.frames(3)
	var mover := mirror.proxies_of(t.actor(&"mover"))
	var table := mirror.proxies_of(t.object(&"table"))
	if not t.require(not mover.is_empty() and not table.is_empty(), "premise: both are mirrored"):
		return
	t.check(_marked(mover[0]), "the mesh a mover is shown by is marked moving")
	t.check(not _marked(table[0]), "a table is not")
	ToonMask.clear()
	await t.frames(3)
	t.check(not _marked(mover[0]), "and the mover is not once the view is off")
	_view_on()
	await t.frames(3)
	t.check(_marked(mover[0]), "marked again when a view is on")


func _batches(t: TestContext) -> void:
	var shots := ShotLayer.new()
	t.world.add_child(shots)
	t.check(_marked(shots.tracer_batch()), "the bullet batch is marked moving")
	var parent := Node3D.new()
	t.world.add_child(parent)
	var burst := BurstFx.new(parent, FxWorld.new())
	t.check(_marked(burst.bits().node), "a burst's bits are marked moving")
	t.check(_marked(burst.sparks().node), "and its sparks")
	var rig_parent := Node3D.new()
	t.world.add_child(rig_parent)
	var blast := BlastRig.new(rig_parent, FxWorld.new())
	var parts: Array[Node] = [blast.ring]
	parts.append_array(blast.flash)
	parts.append_array(blast.fire)
	parts.append_array(blast.puffs)
	t.check(parts.size() > 3, "premise: a blast has parts")
	var unmarked := parts.filter(func(p: Node) -> bool: return not _marked(p))
	t.expect_eq(unmarked.size(), 0, "every part of a blast is marked moving")


## A part added under a marked node (a dent patch, a new outfit piece) takes its parent's mark, at
## any depth; one added under an unmarked node does not.
func _added_later(t: TestContext) -> void:
	var root := Node3D.new()
	t.world.add_child(root)  # a signal of joining is sent in the tree only
	var limb := Node3D.new()
	root.add_child(limb)
	MeshNodes.moving(root)
	var patch := MeshInstance3D.new()
	limb.add_child(patch)
	var deep := MeshInstance3D.new()
	patch.add_child(deep)
	t.check(_marked(patch), "a part added later under a marked node is marked")
	t.check(_marked(deep), "and a part added under that")
	MeshNodes.moving(root, false)
	var after := MeshInstance3D.new()
	limb.add_child(after)
	t.check(not _marked(after), "a part added once it is unmarked is not")
	var plain := Node3D.new()
	t.world.add_child(plain)
	var other := MeshInstance3D.new()
	plain.add_child(other)
	t.check(not _marked(other), "nor one under a node never marked")
	root.free()
	plain.free()


func _marked(node: Node) -> bool:
	var value: Variant = (node as GeometryInstance3D).get_instance_shader_parameter(&"moving")
	return value is float and value > 0.5
