extends Node

var _host
var _panel: PanelContainer
var _title: Label
var _body: Label
var _dismiss: Button
var _seen: Dictionary = {}
var _last_phase := ""
var _finished := false


func _ready() -> void:
	call_deferred("_attach")


func _attach() -> void:
	_host = get_parent()
	if _host == null:
		return
	if not _host.tutorial_mode:
		return
	_build_panel()
	call_deferred("_bind_game")


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.anchor_left = 0.08
	_panel.anchor_right = 0.92
	_panel.offset_top = 92
	_panel.offset_bottom = 238
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f7efdff2")
	style.border_color = Color("ef8b69")
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	_host.add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_panel.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 21)
	_title.add_theme_color_override("font_color", Color("183d48"))
	column.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_color_override("font_color", Color("34545b"))
	column.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	var skip := Button.new()
	skip.text = "튜토리얼 건너뛰기"
	skip.custom_minimum_size.y = 48
	skip.pressed.connect(_skip)
	buttons.add_child(skip)
	_dismiss = Button.new()
	_dismiss.text = "알겠어요"
	_dismiss.custom_minimum_size = Vector2(120, 48)
	_dismiss.pressed.connect(func() -> void: _panel.hide())
	buttons.add_child(_dismiss)


func _bind_game() -> void:
	if _host.game == null:
		call_deferred("_bind_game")
		return
	if not _host.game.state_changed.is_connected(_on_state_changed):
		_host.game.state_changed.connect(_on_state_changed)
	_show_intro()


func _show_intro() -> void:
	_title.text = "심해로 향하는 첫 항해"
	_body.text = "카드 비용, 세 수심의 전장, 공격과 방어를 한 번씩 익혀봅니다. 안내를 닫아도 다음 단계에서 다시 나타납니다."
	_panel.show()


func _on_state_changed() -> void:
	if _finished or _host.game == null:
		return
	var game: Game = _host.game
	if game.is_over():
		_finish()
		return
	if game.awaiting_player() != _host.human_index:
		return
	var phase := str(game.awaiting)
	if phase == _last_phase:
		return
	_last_phase = phase
	_seen[phase] = true
	match phase:
		"mulligan":
			_show_step("1. 시작 손패", "처음 받은 카드를 유지하거나 다시 뽑을 수 있습니다. 카드 이름 옆 숫자는 사용에 필요한 마나입니다.")
		"priority":
			_show_step("2. 카드와 마나", "대지는 마나를 만듭니다. 오른쪽에는 지금 실제로 할 수 있는 행동만 표시되므로 위에서부터 선택해도 안전합니다.")
		"attackers":
			_show_step("3. 공격", "청록색으로 빛나는 내 카드를 탭하세요. 선택된 공격 카드는 금색 테두리로 바뀝니다.")
		"blockers":
			_show_step("4. 방어", "공격과 같은 수심의 생물로 막을 수 있습니다. 방어 카드를 반복해서 탭하면 막을 대상이 바뀝니다.")
	if game.turn_number >= 2 and _seen.has("priority") and _seen.has("attackers"):
		_finish()


func _show_step(title: String, body: String) -> void:
	_title.text = title
	_body.text = body
	_panel.show()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var rewarded := Player.complete_tutorial(true)
	_title.text = "튜토리얼 완료"
	_body.text = "기본 조작을 익혔습니다. 보상으로 진주 코인 100개를 받았습니다." if rewarded else "기본 조작을 다시 확인했습니다."
	_dismiss.text = "계속하기"
	_panel.show()


func _skip() -> void:
	_finished = true
	Player.complete_tutorial(false)
	_panel.queue_free()
