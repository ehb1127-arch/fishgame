class_name AbyssCardTile
extends PanelContainer

const ArtRegistry := preload("res://scripts/ui/card_art_registry.gd")

const FACTION_COLORS := {
	"coral": Color("d9e7d0"),
	"conclave": Color("55b9d8"),
	"drowned": Color("8f72b8"),
	"corsair": Color("ef7257"),
	"brood": Color("72b778"),
	"shard": Color("c8a96a"),
}

var _card: CardInstance
var _art: Texture2D
var _on_action := Callable()


func setup(card: CardInstance, actionable: bool = false, selected: bool = false,
		on_action: Callable = Callable()) -> void:
	_card = card
	_on_action = on_action
	_art = ArtRegistry.texture_for(card.data.id)
	custom_minimum_size = Vector2(158, 92)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = _tooltip(card)
	gui_input.connect(_on_gui_input)

	var frame := StyleBoxFlat.new()
	var faction_color: Color = FACTION_COLORS.get(card.data.faction, Color("78949b"))
	frame.bg_color = Color(0.02, 0.12, 0.17, 0.94) if not card.tapped else Color(0.08, 0.14, 0.18, 0.86)
	frame.border_color = Color("ffd166") if selected else (Color("70e1d4") if actionable else GameEnums.rarity_color(card.data.rarity).lerp(faction_color, 0.35))
	frame.set_border_width_all(4 if selected or card.attacking else (3 if actionable else 2))
	frame.set_corner_radius_all(14)
	frame.content_margin_left = 9
	frame.content_margin_right = 9
	frame.content_margin_top = 7
	frame.content_margin_bottom = 7
	add_theme_stylebox_override("panel", frame)
	modulate = Color(0.72, 0.78, 0.82, 1.0) if card.tapped else Color.WHITE
	if actionable:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	if _art != null:
		var art := TextureRect.new()
		art.texture = _art
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(1, 1, 1, 0.34)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)

		var shade := ColorRect.new()
		shade.color = Color(0.01, 0.04, 0.07, 0.54)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
	else:
		var faction_wash := ColorRect.new()
		faction_wash.color = Color(faction_color.r, faction_color.g, faction_color.b, 0.34)
		faction_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(faction_wash)
		var crest := Label.new()
		crest.text = "◈"
		crest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crest.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crest.add_theme_font_size_override("font_size", 34)
		crest.add_theme_color_override("font_color", Color(1, 1, 1, 0.18))
		crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(crest)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	if actionable:
		var action_badge := Label.new()
		action_badge.text = "선택됨" if selected else "탭하여 선택"
		action_badge.add_theme_color_override("font_color", Color("ffd166") if selected else Color("8ff4e7"))
		action_badge.add_theme_font_size_override("font_size", 11)
		column.add_child(action_badge)

	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var name := Label.new()
	name.text = card.data.display_name(true)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.add_theme_color_override("font_color", faction_color)
	name.add_theme_font_size_override("font_size", 14)
	title_row.add_child(name)
	var cost := Label.new()
	cost.text = card.data.mana_cost_text
	cost.add_theme_color_override("font_color", Color("f4e5ad"))
	title_row.add_child(cost)

	var detail := Label.new()
	detail.text = _detail_line(card)
	detail.add_theme_color_override("font_color", Color("9fc6c5"))
	detail.add_theme_font_size_override("font_size", 12)
	column.add_child(detail)

	var footer := HBoxContainer.new()
	column.add_child(footer)
	var state := Label.new()
	state.text = _state_text(card)
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.add_theme_color_override("font_color", Color("ff9f87") if card.attacking else Color("83ded5"))
	state.add_theme_font_size_override("font_size", 12)
	footer.add_child(state)
	if card.is_creature():
		var stats := Label.new()
		stats.text = "%d / %d" % [card.eff_power, card.eff_toughness]
		stats.add_theme_color_override("font_color", Color("fff2c4"))
		stats.add_theme_font_size_override("font_size", 16)
		footer.add_child(stats)
	elif card.is_champion():
		var fathom := Label.new()
		fathom.text = "◉ %d" % card.fathom_count()
		fathom.add_theme_color_override("font_color", Color("7ce6e1"))
		footer.add_child(fathom)


func _detail_line(card: CardInstance) -> String:
	var type_name := " · ".join(card.data.types)
	var rarity := GameEnums.rarity_name_ko(card.data.rarity)
	return "%s  |  %s" % [type_name, rarity]


func _state_text(card: CardInstance) -> String:
	var states: Array[String] = []
	if card.attacking:
		states.append("공격")
	if not card.blocking.is_empty():
		states.append("방어")
	if card.tapped:
		states.append("소진")
	if card.star_level > 1:
		states.append("★".repeat(card.star_level))
	return " · ".join(states) if not states.is_empty() else "준비"


func _tooltip(card: CardInstance) -> String:
	var lines := [card.data.display_name(true), card.data.type_line(), card.data.display_text(true)]
	var flavor := card.data.display_flavor(true)
	if not flavor.is_empty():
		lines.append("“%s”" % flavor)
	return "\n".join(lines)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _on_action.is_valid():
			_on_action.call()
		else:
			_show_detail()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		if _on_action.is_valid():
			_on_action.call()
		else:
			_show_detail()
		accept_event()


func _show_detail() -> void:
	if _card == null:
		return
	var popup := PopupPanel.new()
	popup.name = "CardDetail"
	popup.transparent_bg = true
	get_tree().root.add_child(popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	popup.add_child(margin)

	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(340, 0)
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	if _art != null:
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(300, 300)
		portrait.texture = _art
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		content.add_child(portrait)

	var title := Label.new()
	title.text = "%s     %s" % [_card.data.display_name(true), _card.data.mana_cost_text]
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", FACTION_COLORS.get(_card.data.faction, Color.WHITE))
	content.add_child(title)

	var type_line := Label.new()
	type_line.text = "%s · %s" % [_card.data.type_line(), GameEnums.rarity_name_ko(_card.data.rarity)]
	type_line.add_theme_color_override("font_color", Color("9fc6c5"))
	content.add_child(type_line)

	var rules := Label.new()
	rules.text = _card.data.display_text(true)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(340, 70)
	content.add_child(rules)

	var flavor := Label.new()
	flavor.text = "“%s”" % _card.data.display_flavor(true)
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.add_theme_color_override("font_color", Color("789a9d"))
	content.add_child(flavor)

	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size.y = 52
	close.pressed.connect(popup.queue_free)
	content.add_child(close)
	popup.popup_hide.connect(popup.queue_free)
	popup.popup_centered_clamped(Vector2i(420, 650), 0.88)

