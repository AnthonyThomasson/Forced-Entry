extends SceneTree
## Testing domain: `tools/run_tests.sh --list [words]`. Prints the tests a run given the same
## options would select (test_batch.gd: the catalog's, then the native suites'), one line each (id,
## flags, tags, name), and `<n> test(s)`; runs nothing.
##   godot --headless --path . -s res://scenes/testing/test_list.gd -- [the run's options]

## Loaded once the autoloads are up, not preloaded: this main-loop script compiles before they are
## registered, and the testing scripts name them (EventBus, Despawner ...).
var test_batch: GDScript


func _initialize() -> void:
	_list.call_deferred()


## Prints the selected catalog tests, then the selected native suites, then the count, and quits.
func _list() -> void:
	test_batch = load("res://scenes/testing/test_batch.gd")
	var lines := 0
	for e in test_batch.selection():
		var flags := PackedStringArray()
		if e["requires_von"]:
			flags.append("von")
		print("%-45s %-12s [%s]  %s"
				% [e["id"], ",".join(flags), ", ".join(PackedStringArray(e["tags"])), e["name"]])
		lines += 1
	for path in test_batch.native_suites_under("res://tests"):
		if test_batch.native_selected(path):
			var e: Dictionary = test_batch.native_entry(path)
			print("%-45s %-12s [%s]  %s" % [e["id"], "native", "", e["name"]])
			lines += 1
	print("%d test(s)" % lines)
	quit(0)
