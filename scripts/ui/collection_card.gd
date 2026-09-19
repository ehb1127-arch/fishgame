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
		on_upgrade: Callable) -> void:
	custom_minimum_size = Vector2(250, 270)
	var faction: Color = FACTION_COLORS.get(card.faction, Color("78949b"))
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("091923")
	frame.border_color = GameEnums.rarity_color(card.rarity).lerp(faction, 0.35)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(14)
	frame.content_margin_left = 12
	frame.content_margin_right = 12
	frame.content_margin_top = 12
	frame.content_margin_bottom = 12
	add_theme_stylebox_override("panel", frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	var art := ArtRegistry.texture_for(card.id)
	if art != null:
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(0, 112)
		portrait.texture = art
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(portrait)

	var title := Label.new()
	title.text = "%s   %s" % [card.display_name(true), card.mana_cost_text]
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override("font_color", faction)
	title.add_theme_font_size_override("font_size", 17)
	column.add_child(title)

	var meta := Label.new()
	meta.text = "%s · %s · ×%d" % [GameEnums.rarity_name_ko(card.rarity), "★".repeat(stars), copies]
	meta.add_theme_color_override("font_color", Color("9fc6c5"))
	meta.add_theme_font_size_override("font_size", 13)
	column.add_child(meta)

	var rules := Label.new()
	rules.text = card.display_text(true)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rules.max_lines_visible = 3
	rules.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rules.add_theme_font_size_override("font_size", 13)
	column.add_child(rules)

	var cost := Currency.upgrade_cost(card.rarity, stars)
	var upgrade := Button.new()
	upgrade.custom_minimum_size.y = 48
	if cost.is_empty():
		upgrade.text = "최대 등급"
		upgrade.disabled = true
	else:
		upgrade.text = "강화  가루 %d · 사본 %d" % [int(cost["dust"]), int(cost["copies"])]
		upgrade.disabled = not Player.collection.can_upgrade(card, dust)
		upgrade.pressed.connect(on_upgrade)
	column.add_child(upgrade)


