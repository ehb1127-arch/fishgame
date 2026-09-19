class_name AbyssDeckEditor
extends RefCounted

const REQUIRED_SIZE := 40
const FACTION_LABELS := {
	"": "모든 진영",
	"coral": "산호 협약",
	"conclave": "심연 의회",
	"drowned": "익사자",
	"corsair": "해적 함대",
	"brood": "레비아탄",
	"shard": "파편",
}


static func open(host, requested_deck: String = "") -> void:
	host._clear()
	var deck_ids: Array[String] = []
	for id in Player.decks.keys():
		deck_ids.append(str(id))
	if deck_ids.is_empty():
		for id in Cards.deck_ids():
			deck_ids.append(str(id))
	deck_ids.sort()
	if deck_ids.is_empty():
		_add_label(host._content, "편집할 덱이 없습니다.")
		_add_back(host)
		return

	var deck_id := requested_deck if requested_deck in deck_ids else deck_ids[0]
	var saved := Player.decks.get(deck_id, {}) as Dictionary
	if saved.is_empty():
		var built := Cards.build_deck(deck_id)
		saved = {"cards": _ids_from_cards(built.get("main", []) as Array), "vault": []}
	var draft: Array = (saved.get("cards", []) as Array).duplicate()

	var title := Label.new()
	title.text = "덱 편집"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("e7fff9"))
	host._content.add_child(title)

	var deck_picker := OptionButton.new()
	deck_picker.custom_minimum_size.y = 52
	for id in deck_ids:
		var definition := Cards.get_deck_definition(id)
		deck_picker.add_item(str(definition.get("name_ko", id)))
	deck_picker.selected = deck_ids.find(deck_id)
	deck_picker.item_selected.connect(func(index: int) -> void:
		open(host, deck_ids[index]))
	host._content.add_child(deck_picker)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	host._content.add_child(tools)
	var search := LineEdit.new()
	search.placeholder_text = "카드 이름 검색"
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(220, 52)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(search)
	var faction := OptionButton.new()
	faction.custom_minimum_size = Vector2(150, 52)
	var faction_ids: Array[String] = ["", "coral", "conclave", "drowned", "corsair", "brood", "shard"]
	for id in faction_ids:
		faction.add_item(FACTION_LABELS[id])
	tools.add_child(faction)

	var status_panel := PanelContainer.new()
	host._content.add_child(status_panel)
	var status_row := HBoxContainer.new()
	status_panel.add_child(status_row)
	var count_label := Label.new()
	count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count_label.add_theme_font_size_override("font_size", 20)
	status_row.add_child(count_label)
	var save := Button.new()
	save.text = "덱 저장"
	save.custom_minimum_size = Vector2(140, 52)
	status_row.add_child(save)

	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host._content.add_child(message)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	host._content.add_child(list)

	# A lambda cannot call itself: it captures by value, and the variable does
	# not exist yet while its own body is being built. This array holds the
	# finished callable so the row buttons can reach it.
	var rerender: Array = []
	var render := func() -> void:
		for child in list.get_children():
			child.queue_free()
		var problems := Player.collection.validate_deck(draft, REQUIRED_SIZE)
		count_label.text = "%d / %d장" % [draft.size(), REQUIRED_SIZE]
		count_label.add_theme_color_override("font_color", Color("7ce6cf") if problems.is_empty() else Color("ffd58d"))
		save.disabled = not problems.is_empty()
		message.text = "저장할 수 있는 덱입니다." if problems.is_empty() else _friendly_problem(problems[0])
		message.add_theme_color_override("font_color", Color("91d9ca") if problems.is_empty() else Color("ffb49f"))

		var query := search.text.strip_edges().to_lower()
		var selected_faction := faction_ids[faction.selected]
		var cards := Cards.collectible_cards()
		cards.sort_custom(func(a: CardData, b: CardData) -> bool:
			return a.display_name(true) < b.display_name(true))
		for entry in cards:
			var card := entry as CardData
			var id := str(card.id)
			if not Player.collection.has_card(id):
				continue
			if not selected_faction.is_empty() and card.faction != selected_faction:
				continue
			if not query.is_empty() and query not in card.display_name(true).to_lower() \
					and query not in card.display_name(false).to_lower():
				continue
			var used := draft.count(id)
			var owned := Player.collection.copies_of(id)
			var allowed := REQUIRED_SIZE if card.is_basic_land() else mini(owned, card.deck_limit())
			var row := HBoxContainer.new()
			row.custom_minimum_size.y = 54
			list.add_child(row)
			var info := Label.new()
			info.text = "%s   %s · 보유 %d · 제한 %d" % [card.display_name(true), card.mana_cost_text, owned, allowed]
			info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var minus := Button.new()
			minus.text = "−"
			minus.custom_minimum_size = Vector2(52, 52)
			minus.disabled = used <= 0
			row.add_child(minus)
			var amount := Label.new()
			amount.text = "%d" % used
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			amount.custom_minimum_size.x = 40
			row.add_child(amount)
			var plus := Button.new()
			plus.text = "+"
			plus.custom_minimum_size = Vector2(52, 52)
			plus.disabled = draft.size() >= REQUIRED_SIZE or used >= allowed
			row.add_child(plus)
			var captured_id := id
			minus.pressed.connect(func() -> void:
				draft.erase(captured_id)
				(rerender[0] as Callable).call())
			plus.pressed.connect(func() -> void:
				draft.append(captured_id)
				(rerender[0] as Callable).call())

	rerender.append(render)

	search.text_changed.connect(func(_value: String) -> void: render.call())
	faction.item_selected.connect(func(_index: int) -> void: render.call())
	save.pressed.connect(func() -> void:
		var problems := Player.collection.validate_deck(draft, REQUIRED_SIZE)
		if not problems.is_empty():
			message.text = _friendly_problem(problems[0])
			return
		Player.decks[deck_id] = {"cards": draft.duplicate(), "vault": (saved.get("vault", []) as Array).duplicate()}
		Player.save_profile()
		message.text = "저장했습니다. 빠른 대전에서 이 덱이 사용됩니다.")
	render.call()
	_add_back(host)


static func _ids_from_cards(cards: Array) -> Array[String]:
	var ids: Array[String] = []
	for card in cards:
		ids.append(str((card as CardData).id))
	return ids


static func _friendly_problem(problem: String) -> String:
	if problem.begins_with("Deck has"):
		return "덱은 정확히 %d장이어야 합니다." % REQUIRED_SIZE
	if "limit is" in problem:
		return "같은 카드의 덱 제한을 초과했습니다."
	if "you own" in problem:
		return "보유한 수량보다 많은 카드가 들어 있습니다."
	return problem


static func _add_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


static func _add_back(host) -> void:
	var back := Button.new()
	back.text = "‹  대해로 돌아가기"
	back.custom_minimum_size.y = 56
	back.pressed.connect(Callable(host, "_show_home"))
	host._content.add_child(back)
