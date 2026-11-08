extends Node2D
## Objects domain: draws an EnvironmentObject's OVERHANG, the overhead part of a piece that reaches
## out beyond its footprint (a streetlight's arm and lamp head over the road), as the child
## `Overhang`. It hangs above whoever walks under it: drawn at
## `ObjectArtLayerConfig.overhang_z_index` (`DrawLayers.OVERHEAD`, absolute), over the living and a
## vehicle's roof, and it has no collider (only the piece's footprint is solid). Its art is the
## piece's own painter with `part: "overhang"` in the options, at the overhang's `size` (across x
## out, in the canonical frame), centred `reach` px from the piece's centre along its facing. What
## in it gives light (a lens, a sign's tube) is drawn again over it by a child `Emissive` layer
## (emissive_layer.gd), as on the piece. With `fade_under: true` it fades under any `characters`
## member in the drawn area, dead or alive: a physics-server area over it tells when a living one
## comes near, a death posted on the EventBus (`&"death"`) tells when one dies there (a corpse has
## no collision layer, so the area cannot see it), and one shared watcher then reads the character
## group and steps the overhangs that are fading or have a character near. A corpse stays near
## until it is freed, so its overhang stays awake. With none near and none fading the watcher
## sleeps, and the overhang itself has no frame callback.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const EmissiveLayer = preload("res://scenes/objects/emissive_layer.gd")

## One watcher per scene tree; weak references keep a closed tree or a torn-down world alive
## nowhere.
static var _watchers := {}
## The overhangs that fade under a character, held weakly: a death looks here for the ones it is
## under.
static var _fading: Array[WeakRef] = []
## Whether the one EventBus listener for deaths is connected.
static var _hears_deaths := false

## The overhang's pixel art (null for a piece without an art painter: nothing is drawn).
var _art: Texture2D
## Its light-giving pixels, or null when nothing in it gives light.
var _emissive: Texture2D
## The child drawing `_emissive` over the art (null without one).
var _emissive_layer: Node2D
## The area it draws, in its own frame (the piece's).
var _rect := Rect2()
## Whether it fades while a character stands under it (the definition's `fade_under`).
var _fades := false
## Actual alpha writes made by the shared watcher (a test read; zero at rest).
var fade_writes := 0
## The instance ids of the characters whose bodies overlap the overhang's area.
var _near := {}
## The physics server's area over the drawn area, and its shape (`_listen`).
var _area := RID()
var _shape := RID()
## Whether the shared watcher steps it now.
var _awake := false


func _ready() -> void:
	set_process(false)
	if _fades:
		_listen()


func _draw() -> void:
	if _art:
		draw_texture_rect(_art, _rect, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _area.is_valid():
		PhysicsServer2D.area_set_transform(_area, get_global_transform())


func _exit_tree() -> void:
	if _area.is_valid():
		PhysicsServer2D.free_rid(_area)
		_area = RID()
	if _shape.is_valid():
		PhysicsServer2D.free_rid(_shape)
		_shape = RID()


## Make this the `Overhang` child of `piece` (an EnvironmentObject not yet in the tree, its look
## fields set) for the definition's `overhang` (`{ size: Vector2, reach: float }`), and return it.
func setup(piece: Node2D, overhang: Dictionary) -> Node2D:
	name = "Overhang"
	z_as_relative = false
	z_index = ObjectArtLayerConfig.overhang_z_index
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var facing: Vector2 = piece.look.facing
	var canonical: Vector2 = overhang.get("size", Vector2.ZERO)
	var size := Vector2(canonical.y, canonical.x) if absf(facing.x) > absf(facing.y) else canonical
	_rect = Rect2(facing * float(overhang.get("reach", 0.0)) - size * 0.5, size)
	if piece.look.art != "" and size.x > 0.0 and size.y > 0.0:
		var opts: Dictionary = piece.look.art_opts.merged(
			{ "part": "overhang", "material": piece.object_material },
			true,
		)
		_art = ObjectArt.texture(piece.look.art, size, piece.color, facing, opts)
		_emissive = ObjectArt.emissive(piece.look.art, size, piece.color, facing, opts)
		if _emissive:
			_emissive_layer = EmissiveLayer.new().setup(self)
	_fades = overhang.get("fade_under", false)
	piece.add_child(self)
	return self


## Step the fade (called by the shared watcher)'s already-fetched character list, writing only a
## changed alpha. Returns whether it still needs stepping: a character is near or it is not opaque
## yet. Once it does not, the watcher drops it until a character comes near again.
func fade_step(characters: Array, delta: float) -> bool:
	var goal := ObjectFadeConfig.alpha if _character_under(characters) else 1.0
	var speed := (1.0 - ObjectFadeConfig.alpha) / ObjectFadeConfig.seconds
	var next := move_toward(modulate.a, goal, speed * delta)
	if next != modulate.a:
		modulate.a = next
		fade_writes += 1
	for id: int in _near.keys():
		if not is_instance_id_valid(id):
			_near.erase(id)
	_awake = not _near.is_empty() or modulate.a != 1.0
	return _awake


## Whether any of `characters` stands inside the area the overhang draws.
func _character_under(characters: Array) -> bool:
	var area := get_global_transform() * _rect
	for body: Node in characters:
		if body is Node2D and area.has_point((body as Node2D).global_position):
			return true
	return false


## The area the overhang draws, in its own frame (the piece's): what reaches out beyond the
## footprint.
func get_rect() -> Rect2:
	return _rect


## The `Emissive` child layer drawing `_emissive` (null when the overhang has nothing that gives
## light).
func emissive_layer() -> Node2D:
	return _emissive_layer


## Draw the light-giving pixels onto `layer` (the `Emissive` child) over the art.
func draw_emissive(layer: CanvasItem) -> void:
	layer.draw_texture_rect(_emissive, _rect, false)


## Watch the drawn area for characters (the living stand on `PhysicsLayers.SOLID`): one coming near
## wakes the watcher, and a death inside it does too (`_on_death`). An area of the physics server,
## not a node: the overhang has no collider.
func _listen() -> void:
	_fading.append(weakref(self))
	if not _hears_deaths:
		_hears_deaths = true
		EventBus.posted.connect(_on_posted)
	_shape = PhysicsServer2D.rectangle_shape_create()
	PhysicsServer2D.shape_set_data(_shape, _rect.size * 0.5)
	_area = PhysicsServer2D.area_create()
	PhysicsServer2D.area_set_space(_area, get_world_2d().space)
	PhysicsServer2D.area_add_shape(_area, _shape, Transform2D(0.0, _rect.get_center()))
	PhysicsServer2D.area_set_transform(_area, get_global_transform())
	PhysicsServer2D.area_set_collision_layer(_area, 0)
	PhysicsServer2D.area_set_collision_mask(_area, PhysicsLayers.SOLID)
	PhysicsServer2D.area_set_monitorable(_area, false)
	PhysicsServer2D.area_set_monitor_callback(_area, _on_body_event)
	set_notify_transform(true)


## A body came into or left the area (`PhysicsServer2D.AREA_BODY_ADDED` / `_REMOVED`): a character
## coming in wakes the watcher; one leaving is forgotten unless it is dead (dying clears its layer,
## which reads as leaving, and a corpse stays under the overhang).
func _on_body_event(
	status: int, _body: RID, instance_id: int, _body_shape: int, _area_shape: int
) -> void:
	if status == PhysicsServer2D.AREA_BODY_REMOVED:
		var gone := instance_from_id(instance_id)
		if not (gone is Node and (gone as Node).get(&"is_dead") == true):
			_near.erase(instance_id)
		return
	var body := instance_from_id(instance_id) as Node
	if body == null or not body.is_in_group(&"characters"):
		return
	_note_near(instance_id)


## Remember the character `instance_id` as near, and wake the watcher.
func _note_near(instance_id: int) -> void:
	_near[instance_id] = true
	if not _awake:
		_awake = true
		_watch(self)


## The one EventBus listener: a character's death (`&"death"`: `{ character, position }`) under a
## fading overhang makes it a corpse near it, as a living one is.
static func _on_posted(topic: StringName, data: Dictionary) -> void:
	if topic != &"death":
		return
	var at: Vector2 = data["position"]
	var corpse: Object = data["character"]
	for i in range(_fading.size() - 1, -1, -1):
		var overhang = _fading[i].get_ref()
		if overhang == null:
			_fading.remove_at(i)
		elif (
			overhang.is_inside_tree()
			and (overhang.get_global_transform() * overhang._rect).has_point(at)
		):
			overhang._note_near(corpse.get_instance_id())


## Register `overhang` with the tree's one fade watcher, creating it on demand.
static func _watch(overhang: Node2D) -> void:
	var tree := overhang.get_tree()
	var key := tree.get_instance_id()
	var watcher: FadeWatcher
	if _watchers.has(key):
		watcher = (_watchers[key] as WeakRef).get_ref()
	if watcher == null:
		watcher = FadeWatcher.new()
		watcher.name = "OverhangFadeWatcher"
		_watchers[key] = weakref(watcher)
		tree.root.add_child.call_deferred(watcher)
	watcher.watch(overhang)


## The only per-frame callback for fading overhangs: one character-group read for all of the
## awake ones.
class FadeWatcher extends Node:
	## How many times a watcher has read the character group (a test reads it; none at rest).
	static var group_reads := 0

	## Awake overhangs, held weakly so world teardown needs no unregister pass.
	var _overhangs: Array[WeakRef] = []


	## Step every awake overhang; sleep while none is.
	func _process(delta: float) -> void:
		group_reads += 1
		var characters := get_tree().get_nodes_in_group(&"characters")
		for i in range(_overhangs.size() - 1, -1, -1):
			var overhang = _overhangs[i].get_ref()
			if overhang == null:
				_overhangs.remove_at(i)
				continue
			if not overhang.fade_step(characters, delta):
				_overhangs.remove_at(i)
		if _overhangs.is_empty():
			set_process(false)


	## Add an awake overhang and wake the watcher.
	func watch(overhang: Node2D) -> void:
		_overhangs.append(weakref(overhang))
		set_process(true)
