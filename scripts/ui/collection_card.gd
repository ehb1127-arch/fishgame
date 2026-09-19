class_name AbyssCollectionCard
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


func setup(card: CardData, copies: int, stars: int, dust: int,
		on_upgrade: Callable, on_view: Callable = Callable()) -> void:
	custom_minimum_size = Vector2(260, 344)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void:
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color("f6ffff"), 0.12))
	mouse_exited.connect(func() -> void:
		var tween := create_tween()
		tween.tween_property(self, "modulate", Color.WHITE, 0.12))
	if on_view.is_valid():
		gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				on_view.call()
				accept_event()
			elif event is InputEventScreenTouch and event.pressed:
				on_view.call()
				accept_event())
	var faction: Color = FACTION_COLORS.get(card.faction, Color("78949b"))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.025, 0.13, 0.17, 0.96)
	frame.border_color = GameEnums.rarity_color(card.rarity).lerp(faction, 0.35)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(18)
	frame.content_margin_left = 12
	frame.content_margin_right = 12
	frame.content_margin_top = 12
	frame.content_margin_bottom = 12
	add_theme_stylebox_override("panel", frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var art := ArtRegistry.texture_for(card.id, card.faction)
	if art != null:
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(0, 136)
		portrait.texture = art
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(portrait)

	var title := Label.new()
	title.text = "%s   %s" % [card.display_name(true), card.mana_cost_text]
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override("font_color", faction)
	title.add_theme_font_size_override("font_size", 18)
	column.add_child(title)

	var meta := Label.new()
	meta.text = "%s · %s · ×%d" % [GameEnums.rarity_name_ko(card.rarity), "★".repeat(stars), copies]
	meta.add_theme_color_override("font_color", Color("9fc6c5"))
	meta.add_theme_font_size_override("font_size", 13)
	column.add_child(meta)

	# Printed cards always reserve a readable parchment area for both the
	# mechanical rules and the worldbuilding line. Art never consumes it.
	var text_panel := PanelContainer.new()
	text_panel.custom_minimum_size.y = 92
	text_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var parchment := StyleBoxFlat.new()
	parchment.bg_color = Color("f4ecd7")
	parchment.border_color = faction.darkened(0.28)
	parchment.set_border_width_all(1)
	parchment.set_corner_radius_all(8)
	parchment.content_margin_left = 9
	parchment.content_margin_right = 9
	parchment.content_margin_top = 7
	parchment.content_margin_bottom = 7
	text_panel.add_theme_stylebox_override("panel", parchment)
	column.add_child(text_panel)

	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 5)
	text_panel.add_child(text_column)
	var rules := Label.new()
	var printed_rules := card.display_text(true)
	rules.text = printed_rules if not printed_rules.is_empty() else "효과 문구를 입력하세요"
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rules.max_lines_visible = 4
	rules.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rules.add_theme_color_override("font_color", Color("18313a") if not printed_rules.is_empty() else Color("87949a"))
	rules.add_theme_font_size_override("font_size", 14)
	text_column.add_child(rules)

	var flavor_text := card.display_flavor(true)
	var flavor := Label.new()
	flavor.text = "“%s”" % flavor_text if not flavor_text.is_empty() else "세계관 문구를 입력하세요"
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	flavor.max_lines_visible = 2
	flavor.add_theme_color_override("font_color", Color("65747a") if not flavor_text.is_empty() else Color("9a9d98"))
	flavor.add_theme_font_size_override("font_size", 11)
	text_column.add_child(flavor)

	var cost := Currency.upgrade_cost(card.rarity, stars)
	var upgrade := Button.new()
	upgrade.custom_minimum_size.y = 48
	upgrade.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if cost.is_empty():
		upgrade.text = "최대 등급"
		upgrade.disabled = true
	else:
		upgrade.text = "강화  가루 %d · 사본 %d" % [int(cost["dust"]), int(cost["copies"])]
		upgrade.disabled = not Player.collection.can_upgrade(card, dust)
		upgrade.pressed.connect(on_upgrade)
	column.add_child(upgrade)
