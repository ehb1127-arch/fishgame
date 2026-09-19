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
		_phase.text = "전투 종료"
		_hint.text = "결과를 확인하세요."
		return
	if game.awaiting_player() != _host.human_index:
		_phase.text = "상대 행동 중"
		_hint.text = "상대의 선택을 기다리고 있습니다."
		return
	match game.awaiting:
		"mulligan":
			_phase.text = "시작 손패"
			_hint.text = "손패를 유지하거나 한 번 다시 뽑으세요."
		"attackers":
			_phase.text = "공격 선택"
			_hint.text = "빛나는 내 카드를 탭해 공격에 포함하거나 제외하세요."
		"blockers":
			_phase.text = "방어 배치"
			_hint.text = "빛나는 방어 카드를 반복해서 탭하면 막을 공격자가 바뀝니다."
		"priority":
			_phase.text = "행동 선택"
			_hint.text = "현재 사용할 수 있는 행동만 표시됩니다."
		_:
			_phase.text = "전투 진행"
			_hint.text = "현재 가능한 행동을 선택하세요."


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
