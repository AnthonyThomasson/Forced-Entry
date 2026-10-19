extends SceneTree
## Helper of tools/test_gdunit_wrap.py: runs gdUnit4's own test discovery, the one its editor panel
## runs (`GdUnitTestDiscoverer.run`: the folders the `test_lookup_folder` setting names, each
## suite's `test_parameters` evaluated), and prints every test case it finds as one `CASE {json}`
## line, then `DISCOVERED <count>`.
##   godot --headless --path . -s res://tools/gdunit_discover.gd

const GdUnitTools := preload("res://addons/gdUnit4/src/core/GdUnitTools.gd")


func _initialize() -> void:
	_discover.call_deferred()


## Runs gdUnit's discovery, prints a `CASE` line per case and the count, and quits.
func _discover() -> void:
	var cases: Array[GdUnitTestCase] = await GdUnitTestDiscoverer.run()
	for c in cases:
		print("CASE " + JSON.stringify({
			"suite": c.source_file,
			"test": c.test_name,
			"name": c.display_name,
			"index": c.attribute_index,
		}))
	print("DISCOVERED %d" % cases.size())
	cases.clear()
	# What gdUnit's own command-line runner does before it quits: its singletons outlive the tree
	# otherwise, and the engine crashes freeing them at exit.
	GdUnitTools.dispose_all()
	await GdUnitMemoryObserver.gc_on_guarded_instances()
	quit()
