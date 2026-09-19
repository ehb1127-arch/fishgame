extends Node

var _host
var _banner: PanelContainer
var _phase: Label
var _hint: Label


func _ready() -> void:
	call_deferred("_attach")


func _attach() -> void:
	_host = get_parent()
	if _host == null:
		return
	_host._ensure_layout()
	_build_banner()
	_host._actions.child_entered_tree.connect(_on_action_added)
	call_deferred("_bind_game")


func _build_banner() -> void:
	_banner = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("123b43e8")
	style.border_color = Color("7ad9ce")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_banner.add_theme_stylebox_override("panel", style)
	_host._root.add_child(_banner)
	_host._root.move_child(_banner, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_banner.add_child(row)
	_phase = Label.new()
	_phase.custom_minimum_size.x = 130
	_phase.add_theme_font_size_override("font_size", 18)
	_phase.add_theme_color_override("font_color", Color("fff0b5"))
	row.add_child(_phase)
	_hint = Label.new()
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color("d7f7f1"))
	row.add_child(_hint)


func _bind_game() -> void:
	if _host.game == null:
		call_deferred("_bind_game")
		return
	if not _host.game.state_changed.is_connected(_refresh):
		_host.game.state_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if _host == null or _host.game == null:
		return
	var game: Game = _host.game
	if game.is_over():
		_phase.text = "���� ����"
		_hint.text = "����� Ȯ���ϼ���."
		return
	if game.awaiting_player() != _host.human_index:
		_phase.text = "��� �ൿ ��"
		_hint.text = "����� ������ ��ٸ��� �ֽ��ϴ�."
		return
	match game.awaiting:
		"mulligan":
			_phase.text = "���� ����"
			_hint.text = "���и� �����ϰų� �� �� �ٽ� ��������."
		"attackers":
			_phase.text = "���� ����"
			_hint.text = "������ �� ī�带 ���� ���ݿ� �����ϰų� �����ϼ���."
		"blockers":
			_phase.text = "��� ��ġ"
			_hint.text = "������ ��� ī�带 �ݺ��ؼ� ���ϸ� ���� �����ڰ� �ٲ�ϴ�."
		"priority":
			_phase.text = "�ൿ ����"
			_hint.text = "���� ����� �� �ִ� �ൿ�� ǥ�õ˴ϴ�."
		_:
			_phase.text = "���� ����"
			_hint.text = "���� ������ �ൿ�� �����ϼ���."


func _on_action_added(child: Node) -> void:
	call_deferred("_decorate_action", child)


func _decorate_action(child: Node) -> void:
	if not is_instance_valid(child):
		return
	if child is Button:
		var button := child as Button
		button.custom_minimum_size.y = 52
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.focus_mode = Control.FOCUS_ALL
	elif child is Label:
		var label := child as Label
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color("c9ebe5"))
