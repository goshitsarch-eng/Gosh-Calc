extends GcTestCase
## The settings JSON reader/writer and the legacy RON reader.


func test_json_integers_stay_exact() -> void:
	var r := GcJson.parse('{"a": 9007199254740993, "b": -9223372036854775808, "c": 9223372036854775807, "d": 9223372036854775808, "e": 1.0, "f": 1e2}')
	check(r["ok"])
	var v: Dictionary = r["value"]
	eq(v["a"], 9007199254740993)
	eq(v["b"], GcEngine.INT_MIN)
	eq(v["c"], GcEngine.INT_MAX)
	eq(typeof(v["d"]), TYPE_FLOAT) # beyond i64: float, like serde_json's f64 path
	eq(typeof(v["e"]), TYPE_FLOAT)
	eq(v["f"], 100.0)


func test_json_rejects_what_serde_rejects() -> void:
	for doc in ['', ' ', '{', '[1,]', '{"a":1,}', '{"a" 1}', '{a:1}', "{'a':1}", '01', '-', '1.', '.5', '+1', '1e', 'nul', 'tru',
			'"\\x"', '"\\ud800"', '"\\udc00"', '"a\nb"', '[1] x', '﻿{}', '// c\n{}', '{"a":NaN}', '{"a":Infinity}']:
		check(not GcJson.parse(doc)["ok"], "accepted %s" % var_to_str(doc))


func test_json_strings_and_nesting() -> void:
	var r := GcJson.parse('"a\\n\\t\\"\\\\\\/\\u00e9\\ud83d\\ude00"')
	eq(r["value"], "a\n\t\"\\/é😀")
	check(GcJson.parse("[".repeat(128) + "]".repeat(128))["ok"])
	check(not GcJson.parse("[".repeat(200) + "]".repeat(200))["ok"], "depth limit")


func test_json_stringify_matches_serde_pretty() -> void:
	var text := GcJson.stringify({"a": [], "b": {}, "c": [1, 2.5, "x\"\n\u0001"], "d": {"e": null, "f": true}})
	eq(text, '{\n  "a": [],\n  "b": {},\n  "c": [\n    1,\n    2.5,\n    "x\\"\\n\\u0001"\n  ],\n  "d": {\n    "e": null,\n    "f": true\n  }\n}')


func test_ron_legacy_history_forms() -> void:
	var r := GcRon.parse('[(expr: "12 + 3 × 4", result: "24"),\r\n  (expr: "a\\"b\\u{3c0}", result: r#"raw"quote"#, value: Some(F(2.5))), ]\r\n')
	check(r["ok"])
	eq(r["value"].size(), 2)
	eq(r["value"][0], {"expr": "12 + 3 × 4", "result": "24"})
	eq(r["value"][1]["expr"], "a\"bπ")
	eq(r["value"][1]["result"], "raw\"quote")
	eq(r["value"][1]["value"], {"$variant": "Some", "$value": {"$variant": "F", "$value": 2.5}})
	eq(GcRon.parse('"scientific"\r\n')["value"], "scientific")
	eq(GcRon.parse('/* c */ "rad" // t')["value"], "rad")
	eq(GcRon.parse('[]')["value"], [])


func test_ron_rejects_malformed_input() -> void:
	for doc in ['', 'not valid RON', '[', '[(expr: "a"', '"unterminated', '"a" "b"', '[1 2]', '"\\q"', '"\\u{110000}"', '"\\0"', '(a: 1, 2)']:
		check(not GcRon.parse(doc)["ok"], "accepted %s" % var_to_str(doc))
