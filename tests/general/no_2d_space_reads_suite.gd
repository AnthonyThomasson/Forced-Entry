extends UnitSuite
## The 2D physics space is not read (#194 del2d): nothing under `scenes/` asks it a question. The
## sim's truth is the 3D twin space (`TwinSpace`, interface 29), so no script holds a
## `PhysicsDirectSpaceState2D`, builds a 2D shape, ray or point query, reads a 2D world's direct
## space, casts a 2D ray or shape node, listens to a 2D body's contacts or overlaps, reads a 2D
## body's slide collisions, tests or makes a 2D body's motion, or allocates in the 2D physics
## server. The scan reads every script's code (a comment is not code; a string is read, for it can
## name a class or a signal) and names each line that does; a script listed in `PENDING` is one the
## ragdoll's move to 3D has not reached
## yet, and the list shrinks to empty.
## The contact and overlap names (`body_entered`, `contact_monitor`, `get_colliding_bodies`, ...)
## are banned on a 3D body too: no sim script reads contact events (Jolt's are not deterministic),
## so the scan is stricter than the 2D rule it checks.

## What a line of code must not contain: a 2D query, node or body event, the 2D physics server, a
## 2D body's motion.
const FORBIDDEN := [
	"PhysicsDirectSpaceState2D",
	"PhysicsShapeQueryParameters2D",
	"PhysicsRayQueryParameters2D",
	"PhysicsPointQueryParameters2D",
	"PhysicsTestMotionParameters2D",
	"PhysicsTestMotionResult2D",
	"PhysicsServer2D",
	"KinematicCollision2D",
	"RayCast2D",
	"ShapeCast2D",
	"Area2D",
	"get_world_2d().direct_space_state",
	"get_world_2d().space",
	"world_2d.direct_space_state",
	"get_colliding_bodies",
	"get_overlapping_bodies",
	"get_overlapping_areas",
	"contact_monitor",
	"max_contacts_reported",
	"body_entered",
	"body_exited",
	"area_entered",
	"area_exited",
	"get_slide_collision",
	"move_and_collide(",
	"move_and_slide(",
	"test_move(",
]
## The calls of a direct space state: a script that makes one must hold a 3D spelling (below) in its
## code, so a bare call on an untyped state is a 3D one (the 2D spellings are forbidden above).
const STATE_CALLS := [
	".intersect_ray(", ".intersect_shape(", ".intersect_point(", ".get_rest_info(",
	".collide_shape(", ".cast_motion(",
]
## What marks a script as one that reads the 3D space.
const SPACE_3D := [
	"PhysicsDirectSpaceState3D", "PhysicsRayQueryParameters3D", "PhysicsShapeQueryParameters3D",
	"PhysicsPointQueryParameters3D", "TwinSpace",
]
## What a `.direct_space_state` read must name on its line: a 3D world, by a call or as a property
## of something (`view.world_3d`): a bare `world_3d` is a variable that may hold a 2D world.
const WORLD_3D := (
	"(^|[^A-Za-z0-9_])(get_world_3d\\(\\)|find_world_3d\\(\\))\\.direct_space_state"
	+ "|\\.world_3d\\.direct_space_state"
)
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
## The one script that moves a body in 3D (`CharacterBody3D`).
const WALKER := "res://scenes/character/character_twin.gd"
## What a script may hold that the scan forbids elsewhere: the walker's 3D moves, and the test
## switch that pads the physics servers' RID allocations (it asks no question of the 2D space; it
## goes with the 2D bodies).
const ALLOWED := {
	"res://scenes/character/character_twin.gd": [
		"move_and_slide(",
		"test_move(",
		"get_slide_collision",
	],
	"res://scenes/testing/allocation_padding.gd": ["PhysicsServer2D"],
}


func test_no_script_asks_the_2d_physics_space() -> void:
	var found: Array[String] = []
	for path in _scripts("res://scenes"):
		if path in PENDING:
			continue
		found.append_array(_findings(path, _code_lines(path)))
	assert_array(found).is_empty()


func test_the_pending_list_names_scripts_that_still_ask_it() -> void:
	for path: String in PENDING:
		assert_bool(_findings(path, _code_lines(path)).is_empty()) \
			.override_failure_message("%s asks no more: drop it from PENDING" % path).is_false()


func test_the_walker_is_a_3d_body() -> void:
	var code := "\n".join(_code_lines(WALKER))
	assert_bool(code.contains("extends CharacterBody3D")).is_true()


## The dodges the scan must catch: each line is code that reads or moves a 2D body or space.
func test_each_way_to_ask_the_2d_space_is_caught() -> void:
	var dodges := [
		"var s := get_world_2d().direct_space_state",
		"var s := world.direct_space_state",
		"var s: PhysicsDirectSpaceState2D = null",
		"var r := PhysicsRayQueryParameters2D.create(a, b)",
		"if body.test_move(xf, motion): pass",
		"var hit := body.move_and_collide(motion)",
		"body.move_and_slide()",
		"var ray := RayCast2D.new()",
		"var area := Area2D.new()",
		"var touching := body.get_colliding_bodies()",
		"body.contact_monitor = true",
		"body.body_entered.connect(f)",
		"var c := body.get_slide_collision(0)",
		"var rid := PhysicsServer2D.body_create()",
		"var world_3d := get_viewport().find_world_2d().direct_space_state",
		"var s := world_3d.direct_space_state",
		"var s := get_world_2d().direct_space_state if get_world_3d() else null",
		"var server := Engine.get_singleton(\"PhysicsServer2D\")",
		"var area := ClassDB.instantiate(\"Area2D\")",
		"var ray := ClassDB.instantiate(\"RayCast2D\")",
		"var s = world.get(\"direct_space_state\")",
		"body.connect(\"body_entered\", f)",
	]
	for line: String in dodges:
		assert_array(_findings("res://scenes/x.gd", [line, ""], [])) \
			.override_failure_message("not caught: %s" % line).is_not_empty()
	var fine := [
		"var s := get_world_3d().direct_space_state",
		"var s := node.find_world_3d().direct_space_state",
		"var s := view.world_3d.direct_space_state",
	]
	for line: String in fine:
		assert_array(_findings("res://scenes/x.gd", [line], [])) \
			.override_failure_message("flagged: %s" % line).is_empty()
	var bare := ["var hit := state.intersect_ray(query)", "var f := s.get_rest_info(q)"]
	for line: String in bare:
		assert_array(_findings("res://scenes/x.gd", [line], [])).is_not_empty()
		assert_array(_findings("res://scenes/x.gd", ["var s: TwinSpace", line], [])).is_empty()


## A comment is not scanned, a string is (a class or a signal can be named by one): a `#` inside a
## string does not start a comment.
func test_a_comment_is_not_code_and_a_string_is() -> void:
	assert_str(_code_of("var x := 1  # test_move(a)")).is_equal("var x := 1  ")
	assert_str(_code_of("var g := \"#fff\" + test_move(a)")) \
		.is_equal("var g := \"#fff\" + test_move(a)")
	assert_str(_code_of("var g := \"a # test_move(b)\"")).is_equal("var g := \"a # test_move(b)\"")
	assert_str(_code_of("var g := '\"#' + \"x\" # c")).is_equal("var g := '\"#' + \"x\" ")
	assert_str(_code_of("var a := \"\\\"#\" # c")).is_equal("var a := \"\\\"#\" ")


## The findings in `lines` of the script `path`: each as `path:line: what`. `allowed` is the calls
## the script may hold (the walker's).
func _findings(path: String, lines: Array, allowed: Array = []) -> Array[String]:
	var found: Array[String] = []
	var skip: Array = ALLOWED.get(path, allowed)
	var code := "\n".join(lines)
	var world_3d_state := RegEx.create_from_string(WORLD_3D)
	var reads_3d := false
	for spelling: String in SPACE_3D:
		reads_3d = reads_3d or code.contains(spelling)
	for i in lines.size():
		var line: String = lines[i]
		for banned: String in FORBIDDEN:
			if line.contains(banned) and banned not in skip:
				found.append("%s:%d: %s" % [path, i + 1, banned])
		if line.contains("direct_space_state"):
			if line.contains("world_2d") or world_3d_state.search(line) == null:
				found.append("%s:%d: a direct_space_state not of a 3D world" % [path, i + 1])
		if not reads_3d:
			for state_call: String in STATE_CALLS:
				if line.contains(state_call):
					found.append("%s:%d: %s on a state that is not 3D" % [path, i + 1, state_call])
	return found


## The code of each line of the script `path` (comments cut off, strings kept).
func _code_lines(path: String) -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		out.append(_code_of(line))
	return out


## Every `.gd` under `dir`, recursively.
func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	return out


## `line` without its comment (a `#` inside a string does not start one, a quote inside the other
## kind of quote does not close the string). The strings stay: a class, a signal or a property can
## be named by one (`ClassDB.instantiate("Area2D")`, `connect("body_entered", f)`).
func _code_of(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				out += c
				i += 1
				c = line[i] if i < line.length() else ""
			elif c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			break
		out += c
		i += 1
	return out
