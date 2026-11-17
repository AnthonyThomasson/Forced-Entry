extends GameTest
## A shader that writes `ALPHA` is a transparent surface unless it cuts: the pixel post's outline
## quad (`hint_screen_texture`, a transparent pass) copies the screen before it and draws over every
## transparent surface sorted before it, so such a surface is erased (the drop shadow was invisible
## for it). So a `.gdshader` under `scenes/` that writes `ALPHA` either cuts with
## `ALPHA_SCISSOR_THRESHOLD` or a dither discard (`toon_dropped`), which keeps it opaque, or it is
## the drop shadow (`shade.gdshader`), whose material sorts after the outline
## (`ToonMaterial.SHADE_PRIORITY`). A source scan, so a new shader that writes `ALPHA` is caught
## headless, without a window.

const ROOT := "res://scenes"
const TRANSPARENT_SHADER := "shade.gdshader"


func describe() -> Dictionary:
	return {
		"name": "A shader that writes ALPHA cuts, or is the drop shadow sorted after the outline",
		"description": "Every .gdshader under scenes/ that assigns ALPHA also sets "
			+ "ALPHA_SCISSOR_THRESHOLD or discards by the dither, except shade.gdshader, whose "
			+ "material has a render priority of ToonMaterial.SHADE_PRIORITY or more.",
		"tags": ["render", "3d", "shader"],
		"timeout": 5.0,
	}


func run(t: TestContext) -> void:
	var shaders := _shaders(ROOT)
	t.require(shaders.size() >= 5, "premise: the scan finds the shaders (%d)" % shaders.size())
	var writers := 0
	for path in shaders:
		var source := FileAccess.get_file_as_string(path)
		if not _writes_alpha(source):
			continue
		writers += 1
		if path.get_file() == TRANSPARENT_SHADER:
			continue
		t.check(
			source.contains("ALPHA_SCISSOR_THRESHOLD") or source.contains("toon_dropped("),
			"%s writes ALPHA without ALPHA_SCISSOR_THRESHOLD or a dither discard" % path,
		)
	t.check(writers >= 2, "premise: the scan reads the shaders that write ALPHA (%d)" % writers)
	var shade := ToonMaterial.shade()
	t.check(
		shade.shader.resource_path.get_file() == TRANSPARENT_SHADER,
		"premise: the drop shadow's material runs %s" % TRANSPARENT_SHADER,
	)
	t.check(
		shade.render_priority >= ToonMaterial.SHADE_PRIORITY,
		"the drop shadow sorts after the outline (priority %d, at least %d)" % [
			shade.render_priority, ToonMaterial.SHADE_PRIORITY,
		],
	)


## Whether the source assigns `ALPHA` itself (not `ALPHA_SCISSOR_THRESHOLD` or a comment's word).
func _writes_alpha(source: String) -> bool:
	var assign := RegEx.create_from_string("(?m)^[^/\\n]*\\bALPHA\\s*=[^=]")
	return assign.search(source) != null


## Every `.gdshader` below `dir`.
func _shaders(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gdshader"):
			found.append("%s/%s" % [dir, file])
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_shaders("%s/%s" % [dir, sub]))
	return found
