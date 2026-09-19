## A deliberately plain match screen.
##
## The art pass will replace this entirely, so it is built for correctness and
## not for looks: the board is read straight out of the engine each time the
## state changes, and every legal action is offered as a button. Nothing here
## knows any rules — if a button exists, the engine said it was legal.
extends Control

const AI_THINK_DELAY := 0.35
const CardTile := preload("res://scripts/ui/card_tile.gd")

var game: Game = null
var ai_players: Dictionary = {}
var human_index: int = 0
## Off in tests, where the screen is driven step by step and the thinking
## pause would only make the suite slow.
var auto_play_ai: bool = true
var tutorial_mode: bool = false

var _turn_time_left: float = 0.0
var _clock_running: bool = false

@onready var _root: VBoxContainer = $Root
var _status: Label
var _board: RichTextLabel
var _log: RichTextLabel
var _actions: VBoxContainer
var _clock_bar: ProgressBar
var _clock_label: Label
var _hand_row: HBoxContainer
var _hand_count: Label


func _ready() -> void:
	_ensure_layout()
	if game == null:
		start_match("corsair_fleet", "leviathan_brood", AIPlayer.Skill.NORMAL, MatchRules.standard())


## --- Setup ---------------------------------------------------------------

func start_match(player_deck: String, opponent_deck: String,
		ai_skill: AIPlayer.Skill = AIPlayer.Skill.NORMAL,
		rules: MatchRules = null, seed_value: int = 0,
		star_levels: Dictionary = {}, use_saved_player_deck: bool = true,
		is_tutorial: bool = false) -> void:
	# A caller can start a match before the node has entered the tree, so
	# make sure the widgets exist before anything tries to draw into them.
	_ensure_layout()
	tutorial_mode = is_tutorial
	game = Game.new()
	var player_build := Cards.build_deck(player_deck)
	if use_saved_player_deck and Player.decks.has(player_deck):
		var saved := Player.decks[player_deck] as Dictionary
		var card_ids := saved.get("cards", []) as Array
		var vault_ids := saved.get("vault", []) as Array
		if Player.collection.validate_deck(card_ids).is_empty():
			player_build = Cards.build_from_list(card_ids, vault_ids)
	game.setup(
		[Player.display_name, "Opponent"],
		[player_build, Cards.build_deck(opponent_deck)],
		seed_value,
		[false, true],
		rules if rules != null else MatchRules.standard(),
		[star_levels, {}]
	)
	ai_players = {1: AIPlayer.create(1, ai_skill)}

	game.state_changed.connect(_on_state_changed)
	game.game_ended.connect(_on_game_ended)
	_on_state_changed()


func start_multiplayer(player_deck: String, ai_decks: Array[String], teams: Array[int],
		ai_skill: AIPlayer.Skill = AIPlayer.Skill.NORMAL,
		rules: MatchRules = null, seed_value: int = 0,
		star_levels: Dictionary = {}) -> void:
	_ensure_layout()
	tutorial_mode = false
	game = Game.new()
	var names: Array[String] = [Player.display_name]
	var decks: Array = [_saved_or_default_deck(player_deck)]
	var ai_flags: Array[bool] = [false]
	var stars: Array = [star_levels]
	ai_players.clear()
	for i in ai_decks.size():
		var seat := i + 1
		names.append("AI 잠수부 %d" % seat)
		decks.append(Cards.build_deck(ai_decks[i]))
		ai_flags.append(true)
		stars.append({})
		ai_players[seat] = AIPlayer.create(seat, ai_skill, seed_value + seat)
	game.setup(names, decks, seed_value, ai_flags,
		rules if rules != null else MatchRules.standard(), stars, teams)
	game.state_changed.connect(_on_state_changed)
	game.game_ended.connect(_on_game_ended)
	_on_state_changed()


func _saved_or_default_deck(deck_id: String) -> Dictionary:
	if Player.decks.has(deck_id):
		var saved := Player.decks[deck_id] as Dictionary
		var card_ids := saved.get("cards", []) as Array
		if Player.collection.validate_deck(card_ids).is_empty():
			return Cards.build_from_list(card_ids, saved.get("vault", []) as Array)
	return Cards.build_deck(deck_id)


## --- Layout --------------------------------------------------------------

## Builds the widgets once, whoever asks first.
func _ensure_layout() -> void:
	if _status == null:
		_build_layout()


func _build_layout() -> void:
	if _root == null:
		_root = VBoxContainer.new()
		_root.name = "Root"
		_root.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_root)
	_root.add_theme_constant_override("separation", 6)
	# Keep the board off the very edge of the screen.
	_root.offset_left = 10
	_root.offset_top = 8
	_root.offset_right = -10
	_root.offset_bottom = -8

	# The turn state and the clock go on a panel; they sit over the artwork
	# and were the hardest things to read without one.
	var header := PanelContainer.new()
	header.custom_minimum_size.y = 64
	_root.add_child(header)
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 6)
	header.add_child(header_box)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 16)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header_box.add_child(_status)

	var clock_row := HBoxContainer.new()
	_clock_label = Label.new()
	_clock_label.custom_minimum_size = Vector2(70, 0)
	_clock_label.add_theme_font_size_override("font_size", 15)
	_clock_bar = ProgressBar.new()
	_clock_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock_bar.custom_minimum_size.y = 12
	_clock_bar.show_percentage = false
	clock_row.add_child(_clock_label)
	clock_row.add_child(_clock_bar)
	header_box.add_child(clock_row)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 930
	_root.add_child(split)

	var arena_column := VBoxContainer.new()
	arena_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arena_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_column.size_flags_stretch_ratio = 3.4
	arena_column.add_theme_constant_override("separation", 5)
	split.add_child(arena_column)

	_board = RichTextLabel.new()
	_board.bbcode_enabled = true
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(760, 0)
	arena_column.add_child(_board)

	var hand_panel := PanelContainer.new()
	hand_panel.custom_minimum_size.y = 126
	arena_column.add_child(hand_panel)
	var hand_column := VBoxContainer.new()
	hand_column.add_theme_constant_override("separation", 3)
	hand_panel.add_child(hand_column)
	var hand_header := HBoxContainer.new()
	hand_column.add_child(hand_header)
	var hand_title := Label.new()
	hand_title.text = "내 손패"
	hand_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_title.add_theme_font_size_override("font_size", 16)
	hand_title.add_theme_color_override("font_color", Color("fff0b0"))
	hand_header.add_child(hand_title)
	_hand_count = Label.new()
	_hand_count.add_theme_font_size_override("font_size", 14)
	hand_header.add_child(_hand_count)
	var hand_scroll := ScrollContainer.new()
	hand_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_column.add_child(hand_scroll)
	_hand_row = HBoxContainer.new()
	_hand_row.add_theme_constant_override("separation", 8)
	hand_scroll.add_child(_hand_row)

	var command_panel := PanelContainer.new()
	command_panel.custom_minimum_size.x = 285
	command_panel.size_flags_horizontal = Control.SIZE_FILL
	split.add_child(command_panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	command_panel.add_child(right)
	var command_title := Label.new()
	command_title.text = "행동"
	command_title.add_theme_font_size_override("font_size", 18)
	command_title.add_theme_color_override("font_color", Color("fff0b0"))
	right.add_child(command_title)

	var actions_scroll := ScrollContainer.new()
	actions_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actions_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(actions_scroll)
	_actions = VBoxContainer.new()
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_scroll.add_child(_actions)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.custom_minimum_size = Vector2(0, 112)
	_log.add_theme_font_size_override("normal_font_size", 14)
	right.add_child(_log)


## --- State ---------------------------------------------------------------

func _on_state_changed() -> void:
	if game == null:
		return
	_refresh_status()
	_refresh_board()
	_refresh_actions()
	_refresh_hand()
	_refresh_log()

	if game.is_over():
		_clock_running = false
		return

	# Hand over to the AI when it is their decision.
	var index := game.awaiting_player()
	if ai_players.has(index):
		_clock_running = false
		if not auto_play_ai:
			return
		await get_tree().create_timer(AI_THINK_DELAY).timeout
		_take_ai_turn(index)
	else:
		_start_clock()


func _take_ai_turn(index: int) -> void:
	if game == null or game.is_over() or game.awaiting_player() != index:
		return
	var ai: AIPlayer = ai_players[index]
	var action := ai.decide(game)
	if action == null:
		action = GameAction.pass_priority(index)
	if not game.perform(action):
		game.perform(GameAction.pass_priority(index))


func _refresh_status() -> void:
	if _status == null:
		return
	var seats: Array[String] = []
	for player in game.players:
		var team_text := " · 팀 %d" % (player.team + 1) if game.players.size() == 4 else ""
		seats.append("%s %d점 (손 %d%s)" % [player.name, player.life, player.hand.size(), team_text])
	_status.text = "턴 %d · %s · %s | %s | 난파선 %d장" % [
		game.turn_number,
		GameEnums.step_name(game.current_step),
		GameEnums.tide_name(game.tide),
		"  vs  ".join(seats),
		game.wreck_size(),
	]


func _refresh_board() -> void:
	if _board == null:
		return
	var lines: Array[String] = []
	var display_order: Array[int] = []
	for player in game.players:
		if player.index != human_index:
			display_order.append(player.index)
	display_order.append(human_index)
	for index in display_order:
		var p := game.get_player(index)
		lines.append("[b]%s[/b]" % p.name)
		for band in GameEnums.DEPTH_ORDER:
			var here: Array[String] = []
			for uid in p.battlefield:
				var c := game.get_card(uid)
				if c == null or not c.is_creature():
					continue
				if c.depth != band:
					continue
				here.append(_describe_permanent(c))
			var marker := " <" if int(band) == GameEnums.favoured_band(game.tide) else ""
			lines.append("  %-9s%s %s" % [
				GameEnums.depth_name(band), marker,
				", ".join(here) if not here.is_empty() else "-",
			])

		var others: Array[String] = []
		for uid in p.battlefield:
			var c := game.get_card(uid)
			if c != null and not c.is_creature() and not c.is_land():
				others.append(_describe_permanent(c))
		if not others.is_empty():
			lines.append("  기타      " + ", ".join(others))

		var lands := 0
		var untapped := 0
		for uid in p.battlefield:
			var c := game.get_card(uid)
			if c != null and c.is_land():
				lands += 1
				if not c.tapped:
					untapped += 1
		lines.append("  대지 %d (사용 가능 %d)" % [lands, untapped])
		lines.append("")

	if not game.stack.is_empty():
		var names: Array[String] = []
		for uid in game.stack:
			names.append(game.get_card(uid).data.display_name(true))
		lines.append("[b]스택[/b]: " + " | ".join(names))

	_board.text = "\n".join(lines)


func _describe_permanent(c: CardInstance) -> String:
	var text := c.data.display_name(true)
	if c.is_creature():
		text += " %d/%d" % [c.eff_power, c.eff_toughness]
	if c.is_champion():
		text += " [%d]" % c.fathom_count()
	if c.star_level > 1:
		text += c.star_text()
	if c.tapped:
		text += "(탭)"
	if c.attacking:
		text += "(공격)"
	if not c.blocking.is_empty():
		text += "(방어)"
	return text


## --- Actions -------------------------------------------------------------

func _refresh_actions() -> void:
	if _actions == null:
		return
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()

	if game.is_over():
		_add_label("게임 종료: %s 승리" % (
			game.get_player(game.winner_index).name if game.winner_index >= 0 else "무승부"))
		return

	if game.awaiting_player() != human_index:
		_add_label("상대 차례...")
		return

	match game.awaiting:
		"mulligan":
			_add_label("멀리건 결정")
			_add_button("이 손으로 시작", func() -> void:
				game.perform(GameAction.keep_hand(human_index)))
			_add_button("멀리건", func() -> void:
				game.perform(GameAction.mulligan(human_index)))

		"attackers":
			_build_attack_controls()

		"blockers":
			_build_block_controls()

		"priority":
			_build_priority_controls()


func _build_priority_controls() -> void:
	_add_label("행동 선택")
	var actions := game.get_legal_actions(human_index)
	for action in actions:
		var label := action.description
		if label.is_empty():
			label = str(action)
		var captured := action
		_add_button(label, func() -> void: game.perform(captured))


func _refresh_hand() -> void:
	if _hand_row == null or game == null:
		return
	for child in _hand_row.get_children():
		_hand_row.remove_child(child)
		child.queue_free()
	var player := game.get_player(human_index)
	_hand_count.text = "%d장 · 덱 %d" % [player.hand.size(), player.library.size()]
	var actions_by_card: Dictionary = {}
	if game.awaiting_player() == human_index:
		for action in game.get_legal_actions(human_index):
			if action.card_uid <= 0:
				continue
			if not actions_by_card.has(action.card_uid):
				actions_by_card[action.card_uid] = []
			(actions_by_card[action.card_uid] as Array).append(action)
	for uid in player.hand:
		var card: CardInstance = game.get_card(uid)
		if card == null:
			continue
		var card_actions: Array = actions_by_card.get(uid, []) as Array
		var tile := CardTile.new()
		var captured_actions: Array = card_actions.duplicate()
		var on_play := Callable()
		if captured_actions.size() == 1:
			on_play = func() -> void: game.perform(captured_actions[0])
		tile.setup(card, not card_actions.is_empty(), false, on_play)
		tile.custom_minimum_size = Vector2(172, 82)
		_hand_row.add_child(tile)


## Attacking is picked one creature at a time, then confirmed, so the button
## list stays short instead of enumerating every subset.
var _chosen_attackers: Array[int] = []
var _attack_target_index: int = 0

func _build_attack_controls() -> void:
	_add_label("공격자 선택 (선택: %d)" % _chosen_attackers.size())
	var defender := game.opponents_of(human_index)
	if defender.is_empty():
		return
	_attack_target_index = clampi(_attack_target_index, 0, defender.size() - 1)
	if defender.size() > 1:
		var target := game.get_player(defender[_attack_target_index])
		_add_button("공격 대상: %s (탭하여 변경)" % target.name, func() -> void:
			_attack_target_index = (_attack_target_index + 1) % defender.size()
			_refresh_actions())
	for uid in game.possible_attackers(human_index):
		var c := game.get_card(uid)
		var chosen := uid in _chosen_attackers
		var captured := uid
		_add_button("%s %s %s" % [
			"[x]" if chosen else "[ ]",
			c.data.display_name(true),
			"%d/%d %s" % [c.eff_power, c.eff_toughness, GameEnums.depth_name(c.depth)],
		], func() -> void:
			if captured in _chosen_attackers:
				_chosen_attackers.erase(captured)
			else:
				_chosen_attackers.append(captured)
			_refresh_actions())

	_add_button("공격 확정", func() -> void:
		var assignment := {}
		for uid in _chosen_attackers:
			assignment[uid] = defender[_attack_target_index]
		_chosen_attackers.clear()
		game.perform(GameAction.declare_attackers(human_index, assignment)))


var _chosen_blocks: Dictionary = {}

func _build_block_controls() -> void:
	_add_label("방어 배치")
	var options := game.possible_blocks(human_index)
	for blocker_uid in options:
		var blocker := game.get_card(int(blocker_uid))
		var assigned := int(_chosen_blocks.get(blocker_uid, -1))
		var label := "%s %d/%d %s -> %s" % [
			blocker.data.display_name(true), blocker.eff_power, blocker.eff_toughness,
			GameEnums.depth_name(blocker.depth),
			game.get_card(assigned).data.display_name(true) if assigned >= 0 else "없음",
		]
		var captured_blocker := int(blocker_uid)
		var attackers := (options[blocker_uid] as Array).duplicate()
		_add_button(label, func() -> void:
			# Cycle through the attackers this blocker could stop.
			var current := int(_chosen_blocks.get(captured_blocker, -1))
			var position := attackers.find(current)
			if position + 1 >= attackers.size():
				_chosen_blocks.erase(captured_blocker)
			else:
				_chosen_blocks[captured_blocker] = attackers[position + 1]
			_refresh_actions())

	_add_button("방어 확정", func() -> void:
		var blocks := _chosen_blocks.duplicate()
		_chosen_blocks.clear()
		if not game.perform(GameAction.declare_blockers(human_index, blocks)):
			_refresh_actions())


func _add_button(text: String, handler: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 52
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	_actions.add_child(button)


func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	_actions.add_child(label)


## --- Log -----------------------------------------------------------------

func _refresh_log() -> void:
	if _log == null:
		return
	var lines: Array[String] = []
	var start: int = maxi(0, game.event_log.size() - 24)
	for i in range(start, game.event_log.size()):
		var e := game.event_log[i]
		var text := _format_event(e)
		if not text.is_empty():
			lines.append(text)
	_log.text = "\n".join(lines)
	_log.scroll_to_line(maxi(0, _log.get_line_count() - 1))


func _format_event(e: Dictionary) -> String:
	var kind := str(e.get("kind", ""))
	match kind:
		"cast":
			return "%s 발동" % _card_name(int(e.get("uid", 0)))
		"land_played":
			return "%s 놓음" % str(e.get("name", ""))
		"resolve_spell", "resolve_ability":
			return "  -> %s 해결" % str(e.get("name", ""))
		"damage_player":
			return "플레이어 %d에게 %d 피해" % [int(e.get("player", 0)), int(e.get("amount", 0))]
		"dies":
			return "%s 파괴됨" % _card_name(int(e.get("uid", 0)))
		"depth_change":
			return "%s -> %s" % [_card_name(int(e.get("uid", 0))), str(e.get("name", ""))]
		"tide":
			return "== %s ==" % str(e.get("name", ""))
		"dice":
			return "주사위: %s (+%d) = %d" % [str(e.get("faces", [])), int(e.get("bonus", 0)),
					int(e.get("total", 0))]
		"roll_outcome":
			return "  결과: %s" % str(e.get("label", ""))
		"molt":
			return "%s 탈피" % str(e.get("name", ""))
		"salvage":
			return "인양 %d장 (난파선 %d 남음)" % [int(e.get("amount", 0)), int(e.get("remaining", 0))]
		"timeout":
			return "시간 초과!"
		"turn_start":
			return "--- 턴 %d ---" % int(e.get("turn", 0))
		"game_over":
			return "=== 게임 종료 ==="
		_:
			return ""


func _card_name(uid: int) -> String:
	var c := game.get_card(uid) if game != null else null
	return c.data.display_name(true) if c != null else "?"


## --- The clock -----------------------------------------------------------

func _start_clock() -> void:
	if _clock_bar == null or _clock_label == null:
		return
	if game == null or not game.rules.has_clock():
		_clock_label.text = ""
		_clock_bar.value = 0
		return
	_turn_time_left = game.turn_time_limit(human_index)
	if _turn_time_left <= 0.0:
		_turn_time_left = game.remaining_match_clock(human_index)
	_clock_bar.max_value = maxf(_turn_time_left, 1.0)
	_clock_running = _turn_time_left > 0.0


func _process(delta: float) -> void:
	if not _clock_running or game == null or game.is_over():
		return
	_turn_time_left -= delta
	_clock_bar.value = maxf(_turn_time_left, 0.0)
	_clock_label.text = "%0.1f초" % maxf(_turn_time_left, 0.0)
	if game.rules.uses_match_clock():
		game.consume_match_clock(human_index, delta)
	if _turn_time_left <= 0.0:
		_clock_running = false
		game.handle_timeout(human_index)


func _on_game_ended(winner_index: int) -> void:
	_clock_running = false
	var won := winner_index == human_index
	if winner_index < 0 and game != null and game.winning_team >= 0:
		won = game.get_player(human_index).team == game.winning_team
	Player.record_match(won, Rating.STARTING_RATING)
