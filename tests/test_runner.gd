## Entry point for the headless test suite.
##
## Run with:
##   godot --headless --path . res://tests/test_runner.tscn
##
## Exits non-zero when anything fails, so CI can gate on it.
extends Node


func _ready() -> void:
	# Cards autoloads before us, but be explicit so a reordering cannot make
	# the suite quietly test an empty database.
	if Cards.all_cards().is_empty():
		Cards.load_all()

	var t := TestFramework.new()
	print("=== Abyss TCG engine tests ===")

	TestRules.run(t)
	TestMeta.run(t)
	TestAI.run(t)
	TestUI.run(t, get_tree())

	print(t.report())
	get_tree().quit(0 if t.failed == 0 else 1)
