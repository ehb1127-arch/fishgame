## Screenshot harness: boots a screen, waits for it to settle, saves a PNG.
##
## Run with:
##   godot --path . res://tools/screenshot.tscn -- <screen> <out.png>
## where <screen> is menu, collection, shop, or match.
extends Node

const MAIN_SCENE := "res://scenes/main.tscn"
const MATCH_SCENE := "res://scenes/match.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var screen := args[0] if args.size() > 0 else "menu"
	var out_path := args[1] if args.size() > 1 else "user://shot.png"

	var host: Node = null
	if screen == "match":
		host = load(MATCH_SCENE).instantiate()
		add_child(host)
		await _settle(6)
		host.start_match("corsair_fleet", "leviathan_brood",
			AIPlayer.Skill.NORMAL, MatchRules.standard(), 4242)
	else:
		host = load(MAIN_SCENE).instantiate()
		add_child(host)
		await _settle(6)
		match screen:
			"collection":
				host._show_collection()
			"shop":
				host._show_shop()
			"voyage":
				host._show_voyage()
			_:
				pass

	await _settle(12)
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out_path)
	print("screenshot %s -> %s (err %d, %dx%d)" % [
		screen, out_path, err, image.get_width(), image.get_height()])
	get_tree().quit(0 if err == OK else 1)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
