class_name AbyssMultiplayerLobby
extends RefCounted

const MATCH_SCENE := "res://scenes/match.tscn"


static func open(host) -> void:
	host._clear()
	var title := Label.new()
	title.text = "다인전 로비"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("e7fff9"))
	host._content.add_child(title)

	var guide := Label.new()
	guide.text = "한 기기에서 AI 잠수부들과 2대2 팀전 또는 3인 난투를 시작합니다. 온라인 초대는 네트워크 업데이트에서 추가됩니다."
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide.add_theme_color_override("font_color", Color("a9cfcb"))
	host._content.add_child(guide)

	var mode := OptionButton.new()
	mode.custom_minimum_size.y = 56
	mode.add_item("2대2 팀전")
	mode.add_item("1대1대1 난투")
	host._content.add_child(mode)

	var deck_ids: Array[String] = []
	for id in Player.decks.keys():
		deck_ids.append(str(id))
	if deck_ids.is_empty():
		for id in Cards.deck_ids():
			deck_ids.append(str(id))
	deck_ids.sort()
	var deck_picker := OptionButton.new()
	deck_picker.custom_minimum_size.y = 56
	for id in deck_ids:
		var definition := Cards.get_deck_definition(id)
		deck_picker.add_item("내 덱 · %s" % str(definition.get("name_ko", id)))
	host._content.add_child(deck_picker)

	var difficulty := OptionButton.new()
	difficulty.custom_minimum_size.y = 56
	difficulty.add_item("AI 쉬움")
	difficulty.add_item("AI 보통")
	difficulty.add_item("AI 어려움")
	difficulty.selected = 1
	host._content.add_child(difficulty)

	var summary := Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", Color("ffdca0"))
	host._content.add_child(summary)
	var refresh_summary := func(_index: int = 0) -> void:
		summary.text = "나 + AI 아군 1명 vs AI 2명" if mode.selected == 0 else "나 vs AI 2명 · 최후의 한 명 승리"
	mode.item_selected.connect(refresh_summary)
	refresh_summary.call()

	var start := Button.new()
	start.text = "다인전 시작"
	start.custom_minimum_size.y = 64
	start.add_theme_font_size_override("font_size", 20)
	start.disabled = deck_ids.is_empty()
	start.pressed.connect(func() -> void:
		var scene: PackedScene = load(MATCH_SCENE)
		if scene == null:
			return
		var screen := scene.instantiate()
		host.get_tree().root.add_child(screen)
		var pool: Array = Cards.deck_ids()
		pool.shuffle()
		var ai_count := 3 if mode.selected == 0 else 2
		var ai_decks: Array[String] = []
		for i in ai_count:
			ai_decks.append(str(pool[i % pool.size()]))
		var teams: Array[int] = [0, 1, 0, 1] if mode.selected == 0 else [0, 1, 2]
		var skills := [AIPlayer.Skill.EASY, AIPlayer.Skill.NORMAL, AIPlayer.Skill.HARD]
		screen.start_multiplayer(deck_ids[deck_picker.selected], ai_decks, teams,
			skills[difficulty.selected], MatchRules.standard(), randi(),
			Player.collection.star_map())
		host.hide())
	host._content.add_child(start)

	var back := Button.new()
	back.text = "‹  대해로 돌아가기"
	back.custom_minimum_size.y = 56
	back.pressed.connect(Callable(host, "_show_home"))
	host._content.add_child(back)
