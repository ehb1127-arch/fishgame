extends Node

const CollectionCard := preload("res://scripts/ui/collection_card.gd")
const ArtRegistry := preload("res://scripts/ui/card_art_registry.gd")

var _host
var _content: VBoxContainer
var _busy := false
var _collection_enhanced := false


func _ready() -> void:
	call_deferred("_attach")


func _attach() -> void:
	_host = get_parent()
	if _host == null:
		return
	_content = _host._content
	if _content == null:
		call_deferred("_attach")
		return
	_content.child_entered_tree.connect(_on_content_changed)
	call_deferred("_inspect_screen")


func _on_content_changed(_child: Node) -> void:
	if not _busy:
		call_deferred("_inspect_screen")


func _inspect_screen() -> void:
	if _busy or _content == null or _content.get_child_count() == 0:
		return
	var first := _content.get_child(0)
	if first is Label and (first as Label).text.begins_with("도감 "):
		if not _collection_enhanced:
			_build_collection_gallery()
	else:
		_collection_enhanced = false
		if first is Label and (first as Label).text == "개봉 결과":
			_animate_pack_result()


func _build_collection_gallery() -> void:
	_busy = true
	_collection_enhanced = true
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()

	var completion := Player.collection.completion()
	var title := Label.new()
	title.text = "수집 기록   %d / %d종" % [int(completion["owned"]), int(completion["total"])]
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("dffbf5"))
	_content.add_child(title)

	var guide := Label.new()
	guide.text = "카드를 눌러 크게 보고, 이름이나 진영으로 빠르게 찾을 수 있습니다."
	guide.add_theme_color_override("font_color", Color("8fb9b8"))
	_content.add_child(guide)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	_content.add_child(tools)

	var search := LineEdit.new()
	search.placeholder_text = "카드 이름 검색"
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(220, 52)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(search)

	var faction := OptionButton.new()
	faction.custom_minimum_size = Vector2(150, 52)
	var faction_filters := ["", "coral", "conclave", "drowned", "corsair", "brood", "shard"]
	for label in ["모든 진영", "산호 협약", "심연 의회", "익사자", "해적 함대", "레비아탄", "파편"]:
		faction.add_item(label)
	tools.add_child(faction)

	var count_label := Label.new()
	count_label.add_theme_color_override("font_color", Color("b8d9d5"))
	_content.add_child(count_label)

	var grid := GridContainer.new()
	var viewport_width: float = _host.get_viewport_rect().size.x
	grid.columns = 2 if viewport_width < 900 else (3 if viewport_width < 1180 else 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_content.add_child(grid)


	var render := func() -> void:
		for child in grid.get_children():
			child.queue_free()
		var visible_count := 0
		var query := search.text.strip_edges().to_lower()
		var selected_faction: String = faction_filters[faction.selected]
		for entry in Cards.collectible_cards():
			var card := entry as CardData
			var id := str(card.id)
			if not Player.collection.has_card(id):
				continue
			if not selected_faction.is_empty() and card.faction != selected_faction:
				continue
			if not query.is_empty() and query not in card.display_name(true).to_lower() \
					and query not in card.display_name(false).to_lower():
				continue
			visible_count += 1
			var captured_id := id
			var captured_card := card
			var tile := CollectionCard.new()
			tile.setup(card, Player.collection.copies_of(id), Player.collection.stars_of(id),
				Player.dust, func() -> void:
					Player.upgrade_card(captured_id)
					_collection_enhanced = false
					_host._show_collection(), func() -> void:
					_show_card_detail(captured_card))
			grid.add_child(tile)
		count_label.text = "%d장의 카드" % visible_count

	search.text_changed.connect(func(_value: String) -> void: render.call())
	faction.item_selected.connect(func(_index: int) -> void: render.call())
	render.call()

	var back := Button.new()
	back.text = "‹  대해로 돌아가기"
	back.custom_minimum_size.y = 56
	back.pressed.connect(Callable(_host, "_show_home"))
	_content.add_child(back)
	_busy = false


func _show_card_detail(card: CardData) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = card.display_name(true)
	dialog.ok_button_text = "닫기"
	dialog.min_size = Vector2i(420, 620)
	_host.add_child(dialog)
	dialog.confirmed.connect(func() -> void: dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390, 540)
	dialog.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	var art := ArtRegistry.texture_for(card.id, card.faction)
	if art != null:
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(0, 260)
		portrait.texture = art
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		column.add_child(portrait)

	var heading := Label.new()
	heading.text = "%s   %s" % [card.display_name(true), card.mana_cost_text]
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)

	var meta := Label.new()
	meta.text = "%s · %s" % [card.type_line(), GameEnums.rarity_name_ko(card.rarity)]
	meta.add_theme_color_override("font_color", Color("9fc6c5"))
	column.add_child(meta)

	var rules := Label.new()
	var printed_rules := card.display_text(true)
	rules.text = printed_rules if not printed_rules.is_empty() else "효과 문구를 입력하세요"
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size.y = 100
	rules.add_theme_color_override("font_color", Color("edf7f3") if not printed_rules.is_empty() else Color("8aa09f"))
	column.add_child(rules)

	var flavor := Label.new()
	var printed_flavor := card.display_flavor(true)
	flavor.text = "“%s”" % printed_flavor if not printed_flavor.is_empty() else "세계관 문구를 입력하세요"
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.add_theme_color_override("font_color", Color("b8d0cb"))
	column.add_child(flavor)

	dialog.popup_centered_clamped(Vector2i(460, 680), 0.92)


func _animate_pack_result() -> void:
	_busy = true
	var delay := 0.0
	for child in _content.get_children():
		if not child is Label or (child as Label).text == "개봉 결과":
			continue
		var label := child as Label
		label.modulate = Color(1, 1, 1, 0)
		label.scale = Vector2(0.86, 0.86)
		label.pivot_offset = label.size * 0.5
		var tween := label.create_tween()
		tween.set_parallel(true)
		tween.tween_property(label, "modulate", Color.WHITE, 0.28).set_delay(delay)
		tween.tween_property(label, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(delay)
		delay += 0.12
	_busy = false
