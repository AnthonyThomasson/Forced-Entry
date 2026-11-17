extends GameTest
## The 3D render's toon shaders use per-instance uniforms, and the engine keeps them in one buffer
## (`rendering/limits/global_shader_variables/buffer_size`, 4096 entries by default). A fresh 5v5
## match uses about 2100 of them and a long fight or a bigger district more; when the buffer is
## full the engine logs "Too many instances using shader instance variables" and the meshes lose
## their colour. The project raises the buffer well past the default (at least sixteen times it).

const SETTING := "rendering/limits/global_shader_variables/buffer_size"
const ENGINE_DEFAULT := 4096
const HEADROOM := 16


func describe() -> Dictionary:
	return {
		"name": "The project's shader instance buffer is far past the engine default",
		"description": "project.godot sets rendering/limits/global_shader_variables/buffer_size "
			+ "to at least sixteen times the engine's 4096, so a long fight or a big district "
			+ "does not run out of per-instance shader variables.",
		"tags": ["render", "3d", "project"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	t.require(ProjectSettings.has_setting(SETTING), "the project sets %s" % SETTING)
	if not ProjectSettings.has_setting(SETTING):
		return
	var size := int(ProjectSettings.get_setting(SETTING))
	t.check(
		size >= ENGINE_DEFAULT * HEADROOM,
		"the buffer holds at least %d entries (it holds %d)" % [ENGINE_DEFAULT * HEADROOM, size],
	)
