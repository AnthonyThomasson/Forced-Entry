extends CanvasLayer
## Composition root part (beside `main.gd`): the 3D view of a match played in the 3D render mode
## (`Settings.render_mode`, `docs/adr/0013-the-3d-render-mirrors-the-2d-sim.md`). A `CanvasLayer`
## named `View3D` on `RenderConfig.canvas_layer`, below the HUD, holding a `TextureRect` that shows
## a `SubViewport` of a 3D world of its own: General's `CameraRig` (an orthographic `Camera3D`
## following the sim's `Camera2D`), one shadow-casting sun with a flat ambient
## (`RenderLightConfig`) and Art's `WorldMirror` of the match's 2D bodies (interface 27). The
## picture is nearest-filtered and the viewport sized by the rig (`RenderConfig.internal_lines`:
## the internal resolution of the pixel post), drawn through Art's toon material and an outline
## quad under the camera (`PixelPost`, `PixelPostConfig`). With `PixelPostConfig.supersample` above
## 1 the 3D picture is rendered that many times larger and averaged down, through a filtered
## stage, to the internal size before the nearest upscale (the shimmer mitigation of a turning
## camera).
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
## The 3D world's viewport, the rect that shows the picture on screen (it covers the window) and the
## viewport the rect shows: the 3D one, or the averaged-down stage after it when supersampling.
var viewport := SubViewport.new()
var rect := TextureRect.new()
var shown: SubViewport = viewport
var _stage: SubViewport


func _init() -> void:
	name = "View3D"
	layer = RenderConfig.canvas_layer
	process_priority = STAGE_PRIORITY  # after the rig, which sizes the 3D picture this frame


func _process(_delta: float) -> void:
	if _stage != null and rig != null and _stage.size != rig.internal_size():
		_stage.size = rig.internal_size()


func _exit_tree() -> void:
	GroundLayer.enabled = false
	GroundLayer.forget()
	RenderingServer.directional_soft_shadow_filter_set_quality(_project_shadow_quality())


## Build the view following `camera` (the sim's `Camera2D`).
func begin(camera: Camera2D) -> void:
	GroundLayer.enabled = true  # the view's overlays draw flat over this picture
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
	viewport.add_child(rig)
	rig.bind(camera, viewport, rect)
	PixelPost.attach(rig.camera, rig.oversample)
	_show(rig.oversample)
	viewport.add_child(_environment())
	viewport.add_child(_sun())
	mirror = WorldMirror.new()
	viewport.add_child(mirror)
	fade = WallFade.new()
	fade.rig = rig
	fade.source = camera
	fade.listen(mirror)
	viewport.add_child(fade)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)


## Show the 3D picture on the rect: directly, or (`oversample` above 1) through a stage that
## averages it down to the picture's size with a filtered, exactly `oversample`-to-1 sample.
func _show(oversample: int) -> void:
	if oversample <= 1:
		rect.texture = viewport.get_texture()
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
	shown = _stage
	rect.texture = _stage.get_texture()


## Mirror the 2D bodies under `world`: from now on the view follows them, and the shots made in it
## (tracers, casings) are shown by their layer.
func mirror_world(world: Node) -> void:
	_register_meshes()
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


## One directional light with hard shadows (`RenderLightConfig`).
func _sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = RenderLightConfig.sun_rotation
	sun.light_color = RenderLightConfig.sun_color
	sun.light_energy = RenderLightConfig.sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = RenderLightConfig.shadow_max_distance
	sun.shadow_bias = RenderLightConfig.shadow_bias
	sun.shadow_normal_bias = RenderLightConfig.shadow_normal_bias
	sun.light_angular_distance = 0.0
	return sun


## A flat ambient over a plain background, no tonemap, glow or fog: what the pixel post expects.
func _environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = RenderLightConfig.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = RenderLightConfig.ambient_color
	env.ambient_light_energy = RenderLightConfig.ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var holder := WorldEnvironment.new()
	holder.name = "Environment"
	holder.environment = env
	return holder


## The directional shadow filter the project is set to (the renderer's own default is soft, low).
func _project_shadow_quality() -> RenderingServer.ShadowQuality:
	var setting := "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
	var fallback := RenderingServer.SHADOW_QUALITY_SOFT_LOW
	return int(ProjectSettings.get_setting(setting, fallback)) as RenderingServer.ShadowQuality
