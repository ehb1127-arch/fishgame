extends Node

var _host
var _overlay: Control
var _flash: ColorRect
var _audio: AudioStreamPlayer
var _seen_events := 0


func _ready() -> void:
	call_deferred("_attach")


func _attach() -> void:
	_host = get_parent()
	if _host == null:
		return
	_build_overlay()
	call_deferred("_bind_game")


func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 100
	_host.add_child(_overlay)

	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color.TRANSPARENT
	_overlay.add_child(_flash)

	_audio = AudioStreamPlayer.new()
	_audio.volume_db = -15.0
	_host.add_child(_audio)


func _bind_game() -> void:
	if _host.game == null:
		call_deferred("_bind_game")
		return
	_seen_events = _host.game.event_log.size()
	if not _host.game.state_changed.is_connected(_on_state_changed):
		_host.game.state_changed.connect(_on_state_changed)


func _on_state_changed() -> void:
	if _host == null or _host.game == null:
		return
	# Headless UI tests disable the AI. Skipping decoration there keeps them fast
	# while the real match screen receives every feedback event.
	if not _host.auto_play_ai:
		_seen_events = _host.game.event_log.size()
		return
	while _seen_events < _host.game.event_log.size():
		var event := _host.game.event_log[_seen_events] as Dictionary
		_seen_events += 1
		_present(event)


func _present(event: Dictionary) -> void:
	match str(event.get("kind", "")):
		"cast":
			_toast("카드 발동", Color("70e1d4"))
			_tone(520.0, 0.08)
		"resolve_spell", "resolve_ability":
			_toast(str(event.get("name", "효과 해결")), Color("ffd166"))
			_tone(660.0, 0.10)
		"damage_player":
			var amount := int(event.get("amount", 0))
			_toast("−%d 피해" % amount, Color("ff806e"), 28)
			_flash_screen(Color("ff5f5540"))
			_shake()
			_tone(170.0, 0.12)
		"dies":
			_toast("심연으로 가라앉았습니다", Color("b8a6d9"))
			_tone(120.0, 0.14)
		"land_played":
			_toast("마나의 흐름이 열렸습니다", Color("89d6a3"))
			_tone(390.0, 0.07)
		"tide":
			_toast(str(event.get("name", "조류 변화")), Color("87ddeb"), 23)
			_flash_screen(Color("58cce426"))
		"turn_start":
			_toast("턴 %d" % int(event.get("turn", 0)), Color("fff0b5"), 24)


func _toast(text: String, color: Color, font_size: int = 20) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.position = Vector2(-210, 132)
	label.size = Vector2(420, 54)
	label.modulate = Color(1, 1, 1, 0)
	label.scale = Vector2(0.86, 0.86)
	label.pivot_offset = label.size * 0.5
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate", Color.WHITE, 0.16)
	tween.tween_property(label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", 102.0, 0.85).set_delay(0.2)
	tween.chain().tween_property(label, "modulate", Color(1, 1, 1, 0), 0.22)
	tween.chain().tween_callback(label.queue_free)


func _flash_screen(color: Color) -> void:
	_flash.color = color
	var tween := _flash.create_tween()
	tween.tween_property(_flash, "color", Color.TRANSPARENT, 0.28)


func _shake() -> void:
	var origin: Vector2 = _host._root.position
	var tween: Tween = _host._root.create_tween()
	tween.tween_property(_host._root, "position", origin + Vector2(8, 0), 0.045)
	tween.tween_property(_host._root, "position", origin + Vector2(-7, 2), 0.045)
	tween.tween_property(_host._root, "position", origin + Vector2(4, -1), 0.045)
	tween.tween_property(_host._root, "position", origin, 0.055)


func _tone(frequency: float, duration: float) -> void:
	var mix_rate := 22050
	var frames := int(mix_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for i in frames:
		var envelope := 1.0 - float(i) / float(frames)
		var sample := int(sin(TAU * frequency * float(i) / float(mix_rate)) * 9000.0 * envelope)
		bytes.encode_s16(i * 2, sample)
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = mix_rate
	wave.stereo = false
	wave.data = bytes
	_audio.stream = wave
	_audio.play()
