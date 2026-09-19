extends Node

const CollectionCard := preload("res://scripts/ui/collection_card.gd")

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
	guide.text = "카드의 사본과 심연 가루를 모아 별 등급을 올리세요. 영웅 카드는 원화가 표시됩니다."
	guide.add_theme_color_override("font_color", Color("8fb9b8"))
	_content.add_child(guide)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	_content.add_child(grid)

	for entry in Cards.collectible_cards():
		var card := entry as CardData
		var id := str(card.id)
		if not Player.collection.has_card(id):
			continue
		var captured_id := id
		var tile := CollectionCard.new()
		tile.setup(card, Player.collection.copies_of(id), Player.collection.stars_of(id),
			Player.dust, func() -> void:
				Player.upgrade_card(captured_id)
				_collection_enhanced = false
				_host._show_collection())
		grid.add_child(tile)

	var back := Button.new()
	back.text = "‹  대해로 돌아가기"
	back.custom_minimum_size.y = 56
	back.pressed.connect(Callable(_host, "_show_home"))
	_content.add_child(back)
	_busy = false


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

