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
		button.custom_minimum_size.y = 60.0
		button.add_theme_font_size_override("font_size", 21)
		# An outline keeps the label readable wherever the art behind the
		# translucent panel happens to be bright.
		button.add_theme_color_override("font_outline_color", INK)
		button.add_theme_constant_override("outline_size", 5)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.focus_mode = Control.FOCUS_ALL
	elif node is Label:
		var label := node as Label
		# Labels the screen already coloured on purpose are left alone; only
		# the plain ones get the default treatment.
		if not label.has_theme_color_override("font_color"):
			label.add_theme_color_override("font_color", PEARL)
		label.add_theme_color_override("font_outline_color", INK)
		label.add_theme_constant_override("outline_size", 6)
		if not label.has_theme_font_size_override("font_size"):
			label.add_theme_font_size_override("font_size", 20 if screen_kind == "menu" else 18)
	elif node is RichTextLabel:
		var rich := node as RichTextLabel
		rich.add_theme_color_override("default_color", PEARL)
		rich.add_theme_color_override("font_outline_color", INK)
		rich.add_theme_constant_override("outline_size", 5)
		rich.add_theme_font_size_override("normal_font_size", 18)
		rich.add_theme_font_size_override("bold_font_size", 20)
	elif node is LineEdit:
		var edit := node as LineEdit
		edit.custom_minimum_size.y = 52.0
		edit.add_theme_font_size_override("font_size", 19)
		edit.add_theme_color_override("font_color", PEARL)
		edit.add_theme_color_override("font_placeholder_color", MUTED)
	elif node is OptionButton:
		var option := node as OptionButton
		option.custom_minimum_size.y = 52.0
		option.add_theme_font_size_override("font_size", 19)
	elif node is ProgressBar:
		(node as ProgressBar).add_theme_color_override("font_color", PEARL)

	for child in node.get_children():
		_style_branch(child)


