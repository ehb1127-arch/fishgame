## Plain front-end for everything outside a match.
##
## One screen with swappable panels rather than a scene per feature: the art
## pass will restructure this anyway, and this way every system is reachable
## and testable by hand today.
extends Control

const MATCH_SCENE := "res://scenes/match.tscn"
const DeckEditor := preload("res://scripts/ui/deck_editor.gd")
const MultiplayerLobby := preload("res://scripts/ui/multiplayer_lobby.gd")

var _content: VBoxContainer
var _header: Label
var _voyage: Voyage = null


func _ready() -> void:
	_build_layout()
	_show_home()


## Screens are built into a panel rather than straight onto the artwork, and
## the column is capped and centred so a wide screen does not stretch every
## button across the whole display.
const CONTENT_MAX_WIDTH := 1180.0
const SCREEN_MARGIN := 24


func _build_layout() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SCREEN_MARGIN)
	add_child(margin)

	var centre := HBoxContainer.new()
	margin.add_child(centre)
	centre.add_spacer(false)

	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 720.0
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.0
	column.add_theme_constant_override("separation", 12)
	centre.add_child(column)
	centre.add_spacer(false)

	# The header sits on its own panel so the currency line never has to be
	# read against whatever the background art is doing.
	var header_panel := PanelContainer.new()
	column.add_child(header_panel)
	_header = Label.new()
	_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_header.add_theme_font_size_override("font_size", 20)
	header_panel.add_child(_header)

	var body := PanelContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)


func _notification(what: int) -> void:
	# Keep the column from growing past a comfortable reading width.
	if what == NOTIFICATION_RESIZED and is_inside_tree():
		_apply_column_width()


func _apply_column_width() -> void:
	var margin := get_child(0) if get_child_count() > 0 else null
	if margin == null or margin.get_child_count() == 0:
		return
	var centre := margin.get_child(0) as HBoxContainer
	if centre == null or centre.get_child_count() < 2:
		return
	var column := centre.get_child(1) as Control
	if column == null:
		return
	var available := size.x - SCREEN_MARGIN * 2
	column.custom_minimum_size.x = minf(CONTENT_MAX_WIDTH, maxf(available, 320.0))


func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()


func _refresh_header() -> void:
	_header.text = "%s · %s (%d) · 코인 %d · 가루 %d · 보석 %d" % [
		Player.display_name,
		Rating.tier_name(Player.rating, true), Player.rating,
		Player.coins, Player.dust, Player.gems,
	]


## --- Home ----------------------------------------------------------------

func _show_home() -> void:
	_clear()
	_refresh_header()
	var hero := PanelContainer.new()
	hero.custom_minimum_size.y = 104
	_content.add_child(hero)
	var hero_column := VBoxContainer.new()
	hero_column.add_theme_constant_override("separation", 4)
	hero.add_child(hero_column)
	var title := Label.new()
	title.text = "심해의 심장이 다시 뛰기 시작합니다"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("fff1bd"))
	hero_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "덱을 준비하고 세 수심의 전장을 지배하세요."
	subtitle.add_theme_color_override("font_color", Color("bfe5df"))
	hero_column.add_child(subtitle)

	var primary := HBoxContainer.new()
	primary.add_theme_constant_override("separation", 14)
	_content.add_child(primary)
	_home_button(primary, "빠른 대전\n덱을 선택해 바로 1대1 전투", _show_quick_match, true)
	_home_button(primary, "항해\n스테이지를 돌파하는 모험", _show_voyage, true)

	var section := Label.new()
	section.text = "게임 메뉴"
	section.add_theme_font_size_override("font_size", 20)
	section.add_theme_color_override("font_color", Color("dffbf5"))
	_content.add_child(section)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	_home_button(grid, "다인전\n2대2 · 3인 난투", func() -> void: MultiplayerLobby.open(self))
	_home_button(grid, "컬렉션\n카드 확인과 강화", _show_collection)
	_home_button(grid, "덱 편집\n40장 덱 구성", func() -> void: DeckEditor.open(self))
	_home_button(grid, "상점\n팩과 상품", _show_shop)
	_home_button(grid, "코덱스\n세계관 기록", _show_codex)
	_home_button(grid, "튜토리얼\n기본 전투 다시 보기", _start_tutorial)

	var record := Label.new()
	record.text = "이번 항해 기록   %d승 %d패" % [Player.wins, Player.losses]
	record.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	record.add_theme_color_override("font_color", Color("a9cfcb"))
	_content.add_child(record)


func _home_button(parent: Control, text: String, handler: Callable,
		featured: bool = false) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(0, 88 if featured else 72)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 20 if featured else 18)
	button.pressed.connect(handler)
	parent.add_child(button)


func _start_tutorial() -> void:
	var scene: PackedScene = load(MATCH_SCENE)
	if scene == null:
		return
	var screen := scene.instantiate()
	get_tree().root.add_child(screen)
	screen.start_match("corsair_fleet", "leviathan_brood", AIPlayer.Skill.EASY,
		MatchRules.standard(), 1127, Player.collection.star_map(), false, true)
	hide()


## --- Quick match ---------------------------------------------------------

func _show_quick_match() -> void:
	_clear()
	_label("덱과 모드를 고르세요")
	var mode_index := 0
	var modes := MatchRules.all_modes()

	var mode_row := HBoxContainer.new()
	_content.add_child(mode_row)
	var mode_label := Label.new()
	mode_label.text = "모드: " + modes[mode_index].display_name
	mode_row.add_child(mode_label)
	var cycle := Button.new()
	cycle.text = "모드 변경"
	cycle.pressed.connect(func() -> void:
		mode_index = (mode_index + 1) % modes.size()
		mode_label.text = "모드: %s (턴 %.0f초)" % [
			modes[mode_index].display_name, modes[mode_index].turn_seconds])
	mode_row.add_child(cycle)

	for deck_id in Cards.deck_ids():
		var deck := Cards.get_deck_definition(str(deck_id))
		var captured := str(deck_id)
		_button("%s 로 대전" % str(deck.get("name_ko", deck_id)), func() -> void:
			_launch_match(captured, _random_other_deck(captured), AIPlayer.Skill.NORMAL,
					modes[mode_index]))
	_button("< 뒤로", _show_home)


func _random_other_deck(exclude: String) -> String:
	var ids: Array = []
	for id in Cards.deck_ids():
		if str(id) != exclude:
			ids.append(str(id))
	if ids.is_empty():
		return exclude
	return str(ids[randi() % ids.size()])


func _launch_match(player_deck: String, opponent_deck: String,
		skill: AIPlayer.Skill, rules: MatchRules) -> void:
	var scene: PackedScene = load(MATCH_SCENE)
	if scene == null:
		push_error("Cannot load %s" % MATCH_SCENE)
		return
	var screen := scene.instantiate()
	get_tree().root.add_child(screen)
	screen.start_match(player_deck, opponent_deck, skill, rules, 0,
			Player.collection.star_map())
	hide()


## --- Voyage --------------------------------------------------------------

func _show_voyage() -> void:
	_clear()
	if not Player.voyage_state.is_empty() and not bool(Player.voyage_state.get("finished", true)):
		_voyage = Voyage.from_dict(Player.voyage_state)
	if _voyage == null or _voyage.finished:
		_label("항해를 시작할 덱을 고르세요")
		for deck_id in Cards.deck_ids():
			var deck := Cards.get_deck_definition(str(deck_id))
			var captured := str(deck_id)
			_button(str(deck.get("name_ko", deck_id)), func() -> void:
				_voyage = Voyage.start(captured)
				Player.voyage_state = _voyage.to_dict()
				Player.save_profile()
				_show_voyage())
		_button("< 뒤로", _show_home)
		return

	var stage := _voyage.current_stage()
	_label("%s — %s" % [str(stage.get("region_ko", "")), str(stage.get("name_ko", ""))])
	_label("생명 %d/%d · 클리어 %d/%d · 덱 %d장" % [
		_voyage.life, _voyage.max_life, _voyage.stages_cleared,
		_voyage.total_stages(), _voyage.deck_ids.size()])
	var gimmick := stage.get("gimmick", {}) as Dictionary
	if not gimmick.is_empty():
		_label("특수 규칙: " + str(gimmick.get("text_ko", "")))

	if not _voyage.pending_rewards.is_empty():
		_label("보상 선택")
		for i in _voyage.pending_rewards.size():
			var card: CardData = Cards.get_card(_voyage.pending_rewards[i])
			if card == null:
				continue
			var captured := i
			_button("%s [%s] %s" % [
				card.display_name(true), GameEnums.rarity_name_ko(card.rarity),
				card.mana_cost_text,
			], func() -> void:
				_voyage.take_reward(captured)
				Player.voyage_state = _voyage.to_dict()
				Player.save_profile()
				_show_voyage())
		_button("보상 받지 않기 (덱을 얇게 유지)", func() -> void:
			_voyage.skip_reward()
			Player.voyage_state = _voyage.to_dict()
			Player.save_profile()
			_show_voyage())
		_button("< 뒤로", _show_home)
		return

	_button("전투 시작", func() -> void:
		var rules := MatchRules.standard()
		rules.starting_life = _voyage.life
		var built := Cards.build_from_list(_voyage.deck_ids, _voyage.vault_ids)
		_launch_voyage_match(stage, rules, built))
	_button("항해 포기", func() -> void:
		Player.add_coins(_voyage.coins_earned())
		_voyage = null
		Player.voyage_state = {}
		Player.save_profile()
		_show_home())
	_button("< 뒤로", _show_home)


func _launch_voyage_match(stage: Dictionary, rules: MatchRules, built: Dictionary) -> void:
	var scene: PackedScene = load(MATCH_SCENE)
	if scene == null:
		return
	var screen := scene.instantiate()
	get_tree().root.add_child(screen)
	screen.start_match(
		str(stage.get("deck", "corsair_fleet")),
		str(stage.get("deck", "corsair_fleet")),
		AIPlayer.skill_from_name(str(stage.get("ai", "normal"))),
		rules, 0, Player.collection.star_map())
	hide()


## --- Collection ----------------------------------------------------------

func _show_collection() -> void:
	_clear()
	var completion := Player.collection.completion()
	_label("도감 %d/%d종" % [int(completion["owned"]), int(completion["total"])])

	for card in Cards.collectible_cards():
		var c := card as CardData
		var id := str(c.id)
		if not Player.collection.has_card(id):
			continue
		var stars := Player.collection.stars_of(id)
		var copies := Player.collection.copies_of(id)
		var cost := Currency.upgrade_cost(c.rarity, stars)
		var can := Player.collection.can_upgrade(c, Player.dust)
		var line := "%s %s ×%d [%s]" % [
			c.display_name(true), "★".repeat(stars), copies,
			GameEnums.rarity_name_ko(c.rarity)]
		if cost.is_empty():
			_label(line + " (최대)")
		else:
			var captured := id
			var label := "%s — 강화: 가루 %d, 사본 %d" % [line, int(cost["dust"]), int(cost["copies"])]
			var button := Button.new()
			button.text = label
			button.disabled = not can
			button.pressed.connect(func() -> void:
				Player.upgrade_card(captured)
				_show_collection())
			_content.add_child(button)
	_button("< 뒤로", _show_home)


## --- Shop ----------------------------------------------------------------

func _show_shop() -> void:
	_clear()
	_refresh_header()
	for item in Shop.catalogue():
		var entry := item as Dictionary
		var name := str(entry.get("name_ko", entry.get("name", "")))
		for currency in [Currency.Kind.PEARL_COIN, Currency.Kind.ABYSS_GEM]:
			if not Shop.is_purchasable_with(entry, currency):
				continue
			var price := Shop.price_in(entry, currency)
			var captured_id := str(entry["id"])
			var captured_currency: Currency.Kind = currency
			var button := Button.new()
			button.text = "%s — %d %s" % [name, price, Currency.label(currency, true)]
			button.disabled = not Player.can_afford(currency, price)
			button.pressed.connect(func() -> void:
				var result := Player.purchase(captured_id, captured_currency)
				if bool(result.get("ok", false)):
					_show_purchase_result(result.get("result"))
				else:
					_label(str(result.get("reason", ""))))
			_content.add_child(button)

	_label("")
	_label(PackOdds.disclosure_text(true))
	_button("< 뒤로", _show_home)


func _show_purchase_result(result: Variant) -> void:
	_clear()
	if result is Array:
		_label("개봉 결과")
		for entry in result as Array:
			var e := entry as Dictionary
			var card: CardData = e["card"]
			var tag := ""
			if bool(e.get("inscribed", false)):
				tag = " ★각인★"
			if bool(e.get("new", false)):
				tag += " (NEW)"
			elif int(e.get("dust", 0)) > 0:
				tag += " (+%d 가루)" % int(e["dust"])
			_label("%s [%s]%s" % [card.display_name(true),
					GameEnums.rarity_name_ko(card.rarity), tag])
	else:
		_label("구매 완료: %s" % str(result))
	Codex.refresh()
	_button("< 상점으로", _show_shop)


## --- Codex ---------------------------------------------------------------

func _show_codex() -> void:
	_clear()
	Codex.refresh()
	for entry in Codex.overview():
		var row := entry as Dictionary
		var arc := row["arc"] as Dictionary
		var unlocked := int(row["unlocked"])
		var chapters := arc.get("chapters", []) as Array
		_label("[%d/%d] %s" % [unlocked, chapters.size(), str(arc.get("name_ko", ""))])

		for i in unlocked:
			var chapter := chapters[i] as Dictionary
			var captured := chapter
			_button("  %d. %s" % [i + 1, str(chapter.get("title_ko", ""))], func() -> void:
				_show_chapter(captured))

		var next := row["next"] as Dictionary
		if not next.is_empty():
			_label("  다음: " + str(next.get("description_ko", "")))
	_button("< 뒤로", _show_home)


func _show_chapter(chapter: Dictionary) -> void:
	_clear()
	_label(str(chapter.get("title_ko", "")))
	var body := Label.new()
	body.text = str(chapter.get("text_ko", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(600, 0)
	_content.add_child(body)
	_button("< 코덱스로", _show_codex)


## --- Widgets -------------------------------------------------------------

func _button(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	_content.add_child(button)


func _label(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(label)
