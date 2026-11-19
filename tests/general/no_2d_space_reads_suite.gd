extends UnitSuite
## The 2D physics space is not read (#194 del2d): nothing under `scenes/` asks it a question. The
## sim's truth is the 3D twin space (`TwinSpace`, interface 29), so no script holds a
## `PhysicsDirectSpaceState2D`, builds a 2D shape, ray or point query, reads a 2D world's direct
## space, tests or makes a 2D body's motion, or allocates in the 2D physics server. The scan reads
## every script's code (a comment is not code) and names each line that does; a script listed in
## `PENDING` is one the ragdoll's move to 3D has not reached yet, and the list shrinks to empty.

## What a line of code must not contain: a 2D query, a 2D world's direct space, a 2D body's motion
## or the 2D physics server.
const FORBIDDEN := [
	"PhysicsDirectSpaceState2D",
	"PhysicsShapeQueryParameters2D",
	"PhysicsRayQueryParameters2D",
	"PhysicsPointQueryParameters2D",
	"PhysicsTestMotionParameters2D",
	"PhysicsServer2D",
	"get_world_2d().direct_space_state",
	"world_2d.direct_space_state",
	".move_and_collide(",
	".test_move(",
	"move_and_slide()",
]
## The scripts allowed to hold one for now: the ragdoll's wall sweeps and the blood's floor and wall
## queries, which move with the ragdoll (`ragdoll3d`).
const PENDING := [
	"res://scenes/physics/ragdoll.gd",
	"res://scenes/character/body/character_ragdoll.gd",
	"res://scenes/character/body/character_anatomy.gd",
	"res://scenes/physics/blood/blood_flow.gd",
	"res://scenes/physics/blood/blood_pool.gd",
	"res://scenes/physics/blood/blood_splat.gd",
]
## The one script that moves a body in 3D (`CharacterBody3D.move_and_slide`, `test_move`).
const WALKER := "res://scenes/character/character_twin.gd"


func test_no_script_asks_the_2d_physics_space() -> void:
	var found: Array[String] = []
	for path in _scripts("res://scenes"):
		if path in PENDING or path == WALKER:
			continue
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			var code := _code_of(lines[i])
			for banned: String in FORBIDDEN:
				if code.contains(banned):
					found.append("%s:%d: %s" % [path, i + 1, banned])
	assert_array(found).is_empty()


func test_the_pending_list_names_scripts_that_still_ask_it() -> void:
	for path: String in PENDING:
		var code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			code += _code_of(line) + "\n"
		var asks := false
		for banned: String in FORBIDDEN:
			asks = asks or code.contains(banned)
		assert_bool(asks).override_failure_message("%s asks no more: drop it from PENDING" % path) \
			.is_true()


## Every `.gd` under `dir`, recursively.
func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	return out


## `line` without its comment (a `#` outside a string starts one: no scene script writes a `#` in
## a string).
func _code_of(line: String) -> String:
	var at := line.find("#")
	return line if at < 0 else line.substr(0, at)
