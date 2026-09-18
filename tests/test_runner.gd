## Entry point for the headless test suite.
##
## Run with:
##   godot --headless --path . res://tests/test_runner.tscn
##
## Exits non-zero when anything fails, so CI can gate on it.
extends Node


func _ready() -> void:
	# Wait one frame before running anything. A node is still "setting up
	# children" during its own _ready, so add_child would be refused there,
	# and the UI test needs to attach a real screen to the tree.
	await get_tree().process_frame

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
