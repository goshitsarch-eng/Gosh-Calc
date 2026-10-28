extends GcTestCase
## Replays the golden corpus recorded from the Rust release of Gosh Calc 0.2
## (166k calculator steps across every mode, base, error path and limit, plus
## the whole keyboard map). Every step compares the *entire* application state.


func test_golden_corpus_matches_rust_release() -> void:
	var r := GcCorpus.replay("res://tests/golden/requests.jsonl.gz", "res://tests/golden/expected.jsonl.gz")
	check(r["steps"] > 150000, "corpus unexpectedly small: %d steps" % r["steps"])
	for failure in r["failures"]:
		check(false, failure)
	check(r["failures"].is_empty())
