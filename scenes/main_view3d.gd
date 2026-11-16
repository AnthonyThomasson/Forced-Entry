extends CanvasLayer
## Composition root part (beside `main.gd`): the 3D view of a match, the only way one is drawn
## (`docs/adr/0013-the-3d-render-mirrors-the-2d-sim.md`), and of a test world in a window. A
## `CanvasLayer` named `View3D` on `RenderConfig.canvas_layer`, below the HUD, holding a
## `TextureRect` that shows a `SubViewport` of a 3D world of its own: General's `CameraRig` (an
## orthographic `Camera3D` following the sim's `Camera2D`), the Lighting domain's dusk
## (`WorldLighting3D`: the sky, the fixtures' and pieces' lights, the ambient) and Art's
## `WorldMirror` of the match's 2D bodies (interface 27). The
## picture is nearest-filtered and the viewport sized by the rig (a picture pixel is one art pixel
## times the zoom, `RenderConfig.texel_match`), drawn through Art's toon material and an outline
## quad under the camera (`PixelPost`, `PixelPostConfig`). The shimmer mitigation of a turning
## camera is a supersample: the 3D picture is rendered that many times larger and averaged down,
## through a filtered stage, to the picture's size before the nearest upscale
## (`PixelPostConfig.supersample` at rest, `turn_supersample` while a quarter turn is under way: the
## rig says which, and the view keeps the stage, the outline's widths and the shown picture in
## step).
##
## Main builds it before the match (`begin`, so no frame of the 2D world is ever drawn) and mirrors
## the match once it is built (`mirror_world`). The hard shadow filter is a global of the
## renderer: it is set here and put back to the project's value when the view leaves the tree.

## The view runs after the camera rig (`process_priority` 50) and the player's view (100) so the
## stage that averages the 3D picture down is sized in the frame the rig sizes the picture.
const STAGE_PRIORITY := 200

## The camera rig and the mirror, for a caller that reads them (the tests, the pixel post).
var rig: CameraRig
var mirror: WorldMirror
## The wall fade: walls and tall pieces between the camera and the player fade (rule 9).
var fade: WallFade
## The 3D dusk's lights (null while `LightingConfig.enabled` is off).
var lighting: WorldLighting3D
## The 3D world's viewport, the rect that shows the picture on screen (it covers the window) and the
## viewport the rect shows: the 3D one, or the averaged-down stage after it when supersampling.
var viewport := SubViewport.new()
var rect := TextureRect.new()
var shown: SubViewport = viewport
var _stage: SubViewport
## The outline quad under the camera, and the supersample the picture is drawn with now.
var _outline: MeshInstance3D
var _oversample := 1
## How far below the pavement the road lies at a spot (Objects' street, read from the world): what
## the effects that lie on the ground are put lower by.
var _ground := StreetGround.new()
## The sim's camera the view follows (where the lights are on).
var _camera: Camera2D


func _init() -> void:
	name = "View3D"
	layer = RenderConfig.canvas_layer
	process_priority = STAGE_PRIORITY  # after the rig, which sizes the 3D picture this frame


func _process(_delta: float) -> void:
	if rig == null:
		return
	_follow_oversample()
	if _stage != null and _stage.size != rig.internal_size():
		_stage.size = rig.internal_size()


func _exit_tree() -> void:
	GroundLayer.forget()
	var server := RenderingServer
	server.directional_soft_shadow_filter_set_quality(_project_shadow_quality("directional"))
	server.positional_soft_shadow_filter_set_quality(_project_shadow_quality("positional"))


## Build the view following `camera` (the sim's `Camera2D`).
func begin(camera: Camera2D) -> void:
	_camera = camera
	add_child(GroundLayer.shared())
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.use_debanding = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	rig = CameraRig.new()
	rig.oversample = maxi(PixelPostConfig.supersample, 1)
	rig.turn_oversample = maxi(PixelPostConfig.turn_supersample, 1)
	viewport.add_child(rig)
	rig.bind(camera, viewport, rect)
	_oversample = rig.current_oversample()
	_outline = PixelPost.attach(rig.camera, _oversample)
	_build_stage(maxi(rig.oversample, rig.turn_oversample))
	_show(_oversample > 1)
	viewport.add_child(_environment())
	viewport.positional_shadow_atlas_size = LightingCostConfig.shadow_atlas
	for quadrant in 4:
		viewport.set_positional_shadow_atlas_quadrant_subdiv(
			quadrant, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4
		)
	mirror = WorldMirror.new()
	viewport.add_child(mirror)
	# debris, bursts, blood and blasts show from the first frame, on the road a kerb lower
	PhysicsMeshes.install(mirror, _ground.offset_at)
	fade = WallFade.new()
	fade.rig = rig
	fade.source = camera
	fade.listen(mirror)
	viewport.add_child(fade)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)


## The stage that averages the 3D picture down to the picture's size, with a filtered, exactly
## `most`-to-1 sample: built when any state of the view draws the picture larger than its size (it
## is idle while the picture is not).
func _build_stage(most: int) -> void:
	if most <= 1:
		return
	_stage = SubViewport.new()
	_stage.name = "Stage"
	_stage.size = rig.internal_size()
	_stage.disable_3d = true
	_stage.gui_disable_input = true
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var average := TextureRect.new()
	average.texture = viewport.get_texture()
	average.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	average.stretch_mode = TextureRect.STRETCH_SCALE
	average.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	average.set_anchors_preset(Control.PRESET_FULL_RECT)
	average.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(average)
	add_child(_stage)


## Show the 3D picture on the rect: directly, or (`averaged`) through the stage.
func _show(averaged: bool) -> void:
	shown = _stage if averaged and _stage != null else viewport
	rect.texture = shown.get_texture()
	if _stage != null:
		_stage.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if averaged else SubViewport.UPDATE_DISABLED
		)


## The rig drew this frame's picture at `current_oversample()` times its size: the outline's widths
## (in drawn pixels) and the stage follow it in the same frame.
func _follow_oversample() -> void:
	var now := rig.current_oversample()
	if now == _oversample:
		return
	_oversample = now
	PixelPost.refresh(_outline, now)
	_show(now > 1)


## Mirror the 2D bodies under `world`: from now on the view follows them, and the shots made in it
## (tracers, casings) are shown by their layer.
func mirror_world(world: Node) -> void:
	_register_meshes()
	_ground.refresh(world)
	mirror.mirror(world)
	ProjectileMeshes.install(mirror, world)


## Plug each domain's own meshes into the mirror (its builders, `WorldMirror.builders`), so a body
## of a kind that has one is shown by it and the rest by their proxies.
func _register_meshes() -> void:
	ObjectMeshes.register(mirror.builders)
	ObjectMeshes.track(mirror)
	VehicleMeshes.register(mirror.builders)
	CharacterMeshes.register(mirror.builders)
	ItemMeshes.register(mirror)


## Light the 3D world for the match's 2D world `world` (the Lighting domain's dusk, `rooms` the
## match's every room, the seed its rhythms'): the lights follow the camera's focus for what they
## cost.
func light_world(world: Node2D, seed_value: int, rooms: Array) -> void:
	lighting = WorldLighting3D.light(
		viewport, world, seed_value, rooms,
		func() -> Vector2: return (
			_camera.get_screen_center_position() if is_instance_valid(_camera) else Vector2.ZERO
		)
	)
	if lighting != null:
		lighting.glow_changed.connect(_dim_glow)


## A piece's light changed its level: its mesh's glow follows (a mesh without glows says nothing).
func _dim_glow(piece: Node, level: float) -> void:
	for mesh in mirror.proxies_of(piece):
		if mesh.has_method(&"set_glow_level"):
			mesh.call(&"set_glow_level", level)


## A plain background, no tonemap, glow or fog (the toon shaders take their ambient from the
## Lighting domain's `ToonLight` globals, not the environment): what the pixel post expects.
func _environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = RenderLightConfig.background_color
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var holder := WorldEnvironment.new()
	holder.name = "Environment"
	holder.environment = env
	return holder


## The soft shadow filter the project is set to for `kind` (`directional` or `positional`; the
## renderer's own default is soft, low).
func _project_shadow_quality(kind: String) -> RenderingServer.ShadowQuality:
	var setting := "rendering/lights_and_shadows/%s_shadow/soft_shadow_filter_quality" % kind
	var fallback := RenderingServer.SHADOW_QUALITY_SOFT_LOW
	return int(ProjectSettings.get_setting(setting, fallback)) as RenderingServer.ShadowQuality
