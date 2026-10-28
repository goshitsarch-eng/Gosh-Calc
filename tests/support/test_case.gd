class_name GcTestCase
extends RefCounted
## Minimal xUnit-style base: methods named test_* are run by tests/run_all.gd.

var failures: Array = []
var assertions := 0
var _current := ""


func check(condition: bool, message: String = "") -> void:
	assertions += 1
	if not condition:
		failures.append("%s: %s" % [_current, message if not message.is_empty() else "assertion failed"])


func eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		var detail := "expected %s (%s), got %s (%s)" % [
				var_to_str(expected), type_string(typeof(expected)),
				var_to_str(actual), type_string(typeof(actual))]
		failures.append("%s: %s%s" % [_current, message + " " if not message.is_empty() else "", detail])


func begin(test_name: String) -> void:
	_current = test_name
