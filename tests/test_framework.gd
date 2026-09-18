## A very small test harness, so the engine tests need no addons.
##
## Failures are collected rather than thrown, so one broken assertion does not
## hide the rest of the suite.
class_name TestFramework
extends RefCounted

var passed: int = 0
var failed: int = 0
var failures: Array[String] = []
var _current: String = ""


func start(name: String) -> void:
	_current = name


func check(condition: bool, message: String) -> bool:
	if condition:
		passed += 1
		return true
	failed += 1
	failures.append("%s: %s" % [_current, message])
	return false


func eq(actual: Variant, expected: Variant, message: String) -> bool:
	return check(actual == expected,
		"%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func ne(actual: Variant, unexpected: Variant, message: String) -> bool:
	return check(actual != unexpected, "%s (should not be %s)" % [message, str(unexpected)])


func gt(actual: float, threshold: float, message: String) -> bool:
	return check(actual > threshold, "%s (%s should exceed %s)" % [message, actual, threshold])


func approx(actual: float, expected: float, tolerance: float, message: String) -> bool:
	return check(absf(actual - expected) <= tolerance,
		"%s (expected %s +/- %s, got %s)" % [message, expected, tolerance, actual])


func report() -> String:
	var lines: Array[String] = []
	lines.append("")
	lines.append("%d passed, %d failed" % [passed, failed])
	for failure in failures:
		lines.append("  FAIL  " + failure)
	if failed == 0:
		lines.append("ALL TESTS PASSED")
	return "\n".join(lines)
