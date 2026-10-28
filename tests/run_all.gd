extends SceneTree
## Runs every tests/unit/test_*.gd. usage:
##   godot --headless --path . -s tests/run_all.gd [-- name-filter]

func _init() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var passed := 0
	var failed := 0
	var assertions := 0
	var report := PackedStringArray()
	var dir := DirAccess.open("res://tests/unit")
	var files := PackedStringArray()
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		if script == null or not script.can_instantiate():
			failed += 1
			report.append("%s: failed to load" % f)
			continue
		var methods := PackedStringArray()
		for m in script.get_script_method_list():
			if String(m["name"]).begins_with("test_"):
				methods.append(m["name"])
		methods.sort()
		for m in methods:
			if not filter.is_empty() and not (f + "." + m).contains(filter):
				continue
			var case: GcTestCase = script.new()
			case.begin(f + "." + m)
			case.call(m)
			assertions += case.assertions
			if case.failures.is_empty():
				passed += 1
			else:
				failed += 1
				report.append_array(case.failures)
	for line in report:
		print("FAIL ", line)
	print("%d tests passed, %d failed, %d assertions" % [passed, failed, assertions])
	quit(1 if failed > 0 else 0)
