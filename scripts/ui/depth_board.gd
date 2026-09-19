class_name AbyssDepthBoard
extends VBoxContainer

const CardTile := preload("res://scripts/ui/card_tile.gd")
const CARD_BACK := preload("res://assets/ui/card_back_heart.png")

const DEPTH_NAMES := {
	GameEnums.Depth.SURFACE: "수면  SURFACE",
	GameEnums.Depth.MIDWATER: "중층  MIDWATER",
	GameEnums.Depth.ABYSS: "심해  ABYSS",
}

const DEPTH_COLORS := {
	GameEnums.Depth.SURFACE: Color(0.08, 0.48, 0.58, 0.82),
	GameEnums.Depth.MIDWATER: Color(0.04, 0.33, 0.50, 0.84),
	GameEnums.Depth.ABYSS: Color(0.20, 0.16, 0.43, 0.86),
}


func render(game: Game, human_index: int, chosen_attackers: Array[int] = [],
		chosen_blocks: Dictionary = {}, on_card_action: Callable = Callable()) -> void:
	_clear_now()
	if game == null:
		return

	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)

	var other_indices: Array[int] = []
	for player in game.players:
		if player.index != human_index:
			other_indices.append(player.index)
	var possible_attackers: Array = game.possible_attackers(human_index) if game.awaiting == "attackers" else []
	var possible_blocks: Dictionary = game.possible_blocks(human_index) if game.awaiting == "blockers" else {}
	for index in other_indices:
		_add_player_header(game, index, true)
	for band in GameEnums.DEPTH_ORDER:
		_add_depth_lane(game, human_index, other_indices, band, possible_attackers,
			possible_blocks, chosen_attackers, chosen_blocks, on_card_action)
	_add_player_header(game, human_index, false)

	if not game.stack.is_empty():
		var names: Array[String] = []
		for uid in game.stack:
			names.append(game.get_card(uid).data.display_name(true))
		var stack_label := Label.new()
		stack_label.text = "파도 위의 주문  ›  " + "  ·  ".join(names)
		stack_label.add_theme_color_override("font_color", Color("ffd58d"))
		stack_label.add_theme_font_size_override("font_size", 17)
		add_child(stack_label)


func _clear_now() -> void:
	for child in get_children():
		remove_child(child)
		child.free()


func _add_player_header(game: Game, index: int, show_backs: bool) -> void:
	var player := game.get_player(index)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 46
	add_child(row)

	var identity := Label.new()
	identity.text = "%s   ♥ %d" % [player.name, player.life]
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_color_override("font_color", Color("e2fbf6"))
	identity.add_theme_font_size_override("font_size", 21)
	row.add_child(identity)

	if show_backs:
		var backs := HBoxContainer.new()
		backs.add_theme_constant_override("separation", -18)
		for i in mini(player.hand.size(), 7):
			var back := TextureRect.new()
			back.custom_minimum_size = Vector2(32, 44)
			back.texture = CARD_BACK
			back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			back.mouse_filter = Control.MOUSE_FILTER_IGNORE
			backs.add_child(back)
		row.add_child(backs)

	var resources := Label.new()
	resources.text = "손 %d   대지 %d/%d" % [player.hand.size(), _untapped_lands(game, player), _land_count(game, player)]
	resources.add_theme_color_override("font_color", Color("b6dedd"))
	resources.add_theme_font_size_override("font_size", 16)
	row.add_child(resources)


func _add_depth_lane(game: Game, human_index: int, other_indices: Array[int],
		band: GameEnums.Depth, possible_attackers: Array, possible_blocks: Dictionary,
		chosen_attackers: Array[int], chosen_blocks: Dictionary,
		on_card_action: Callable) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = DEPTH_COLORS[band]
	var favoured := int(band) == GameEnums.favoured_band(game.tide)
	style.border_color = Color("ffd978") if favoured else Color("9fe8df")
	style.set_border_width_all(2 if favoured else 1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var row := HBoxContainer.new()
	panel.add_child(row)
	var band_label := Label.new()
	band_label.text = ("≈ " if favoured else "") + DEPTH_NAMES[band]
	band_label.custom_minimum_size.x = 108
	band_label.add_theme_color_override("font_color", Color("ffdf95") if favoured else Color("b3dcde"))
	band_label.add_theme_font_size_override("font_size", 16)
	row.add_child(band_label)

	var sides := VBoxContainer.new()
	sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.add_theme_constant_override("separation", 4)
	row.add_child(sides)
	for index in other_indices:
		var player := game.get_player(index)
		var relation := "아군" if game.are_allies(human_index, index) else "상대"
		_add_card_row(sides, game, player, band, "%s · %s" % [relation, player.name],
			[], {}, [], {}, Callable())
	_add_card_row(sides, game, game.get_player(human_index), band, "나",
		possible_attackers, possible_blocks, chosen_attackers, chosen_blocks, on_card_action)


func _add_card_row(parent: VBoxContainer, game: Game, player, band: GameEnums.Depth,
		prefix: String, possible_attackers: Array, possible_blocks: Dictionary,
		chosen_attackers: Array[int], chosen_blocks: Dictionary,
		on_card_action: Callable) -> void:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	parent.add_child(flow)
	var found := false
	for uid in player.battlefield:
		var card: CardInstance = game.get_card(uid)
		if card == null or not card.is_creature() or card.depth != band:
			continue
		found = true
		var tile := CardTile.new()
		var actionable: bool = uid in possible_attackers or possible_blocks.has(uid)
		var selected: bool = uid in chosen_attackers or chosen_blocks.has(uid)
		var captured_uid := int(uid)
		tile.setup(card, actionable, selected,
			func() -> void:
				if on_card_action.is_valid():
					on_card_action.call(captured_uid))
		flow.add_child(tile)
	if not found:
		var empty := Label.new()
		empty.text = "%s · 비어 있음" % prefix
		empty.add_theme_color_override("font_color", Color("8fb0b4"))
		empty.add_theme_font_size_override("font_size", 15)
		flow.add_child(empty)


func _land_count(game: Game, player) -> int:
	var count := 0
	for uid in player.battlefield:
		var card: CardInstance = game.get_card(uid)
		if card != null and card.is_land():
			count += 1
	return count


func _untapped_lands(game: Game, player) -> int:
	var count := 0
	for uid in player.battlefield:
		var card: CardInstance = game.get_card(uid)
		if card != null and card.is_land() and not card.tapped:
			count += 1
	return count


