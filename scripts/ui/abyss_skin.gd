extends Node

## Shared presentation layer for the dynamically-built prototype screens.
## It keeps the game/rules UI decoupled while giving every generated widget
## a consistent, touch-friendly visual hierarchy.

@export var screen_kind: String = "menu"

const INK := Color("071522")
const PEARL := Color("d7f6f2")
const MUTED := Color("86aaa9")
const TIDE := Color("55dfd3")
const CORAL := Color("ff886e")


func _ready() -> void:
	get_parent().child_entered_tree.connect(_on_child_added)
	call_deferred("_refresh_tree")


func _on_child_added(_child: Node) -> void:
	call_deferred("_refresh_tree")


func _refresh_tree() -> void:
	var host := get_parent() as Control
	if host == null:
		return
	for child in host.get_children():
		if child == self:
			continue
		_style_branch(child)


func _style_branch(node: Node) -> void:
	if node is Button:
		var button := node as Button
		button.custom_minimum_size.y = 56.0
		button.add_theme_font_size_override("font_size", 18)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.focus_mode = Control.FOCUS_ALL
	elif node is Label:
		var label := node as Label
		label.add_theme_color_override("font_color", PEARL)
		label.add_theme_color_override("font_shadow_color", INK)
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.add_theme_font_size_override("font_size", 18 if screen_kind == "menu" else 16)
	elif node is RichTextLabel:
		var rich := node as RichTextLabel
		rich.add_theme_color_override("default_color", PEARL)
		rich.add_theme_font_size_override("normal_font_size", 16)
		rich.add_theme_font_size_override("bold_font_size", 18)
	elif node is ProgressBar:
		(node as ProgressBar).add_theme_color_override("font_color", PEARL)

	for child in node.get_children():
		_style_branch(child)


