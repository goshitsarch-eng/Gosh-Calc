class_name GcCorpus
extends RefCounted
## Replays recorded request/response corpora (optionally gzip-compressed).


static func read_lines(path: String) -> PackedStringArray:
	var bytes := FileAccess.get_file_as_bytes(path)
	if path.ends_with(".gz"):
		bytes = bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var lines := bytes.get_string_from_utf8().split("\n", false)
	return lines


## Returns {"requests": int, "steps": int, "failures": Array[String]}.
static func replay(requests_path: String, expected_path: String, max_reports: int = 8) -> Dictionary:
	var requests := read_lines(requests_path)
	var expected := read_lines(expected_path)
	var result := {"requests": requests.size(), "steps": 0, "failures": []}
	if requests.size() != expected.size():
		result["failures"].append("corpus size mismatch: %d requests, %d expectations" % [
				requests.size(), expected.size()])
		return result
	for i in requests.size():
		var req: Dictionary = JSON.parse_string(requests[i])
		var want: Variant = JSON.parse_string(expected[i])
		var got: Variant = GcTestCodec.run_request(req)
		if req.has("seq"):
			result["steps"] += req["seq"].size()
			for j in req["seq"].size():
				if got[j] != want[j]:
					if result["failures"].size() < max_reports:
						result["failures"].append("request %d step %d after %s\n  want: %s\n  got:  %s" % [
								i, j, req["seq"].slice(0, j + 1),
								String(want[j]).replace("\t", " | "), String(got[j]).replace("\t", " | ")])
					break
		elif got != want:
			if result["failures"].size() < max_reports:
				result["failures"].append("key mismatch %s: want %s got %s" % [req, want, got])
	return result
