extends SceneTree
## Replays any recorded corpus and prints mismatches.
## usage: godot --headless -s tests/diff_runner.gd -- <requests.jsonl[.gz]> <expected.jsonl[.gz]>


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <requests.jsonl> <expected.jsonl>")
		quit(2)
		return
	var started := Time.get_ticks_msec()
	var r := GcCorpus.replay(args[0], args[1], 12)
	for failure in r["failures"]:
		print("MISMATCH ", failure)
	print("%d requests, %d steps, %d mismatches, %d ms" % [
			r["requests"], r["steps"], r["failures"].size(), Time.get_ticks_msec() - started])
	quit(1 if not r["failures"].is_empty() else 0)
