## The rules engine.
##
## The engine never asks anyone for input. A controller (the UI, the AI, or a
## test) reads [method awaiting_player] and [method get_legal_actions], then
## hands one action back through [method perform]. Everything that happens is
## appended to [member event_log] so a view layer can animate it without
## reading game state directly.
##
## Deliberate simplifications versus paper Magic are listed in docs/rules.md.
class_name Game
extends RefCounted

signal state_changed()
signal event_logged(event: Dictionary)
signal game_ended(winner_index: int)

const STARTING_HAND_SIZE := 7
const MAX_HAND_SIZE := 7

## What the engine is currently waiting for: "mulligan", "priority",
## "attackers", "blockers", or "" when the game is over.
var awaiting: String = ""
var awaiting_index: int = 0

var cards: Dictionary = {}
var players: Array[PlayerState] = []
var stack: Array[int] = []

var turn_number: int = 0
var active_player_index: int = 0
var priority_player_index: int = 0
var current_step: GameEnums.Step = GameEnums.Step.UNTAP
## 0 = first-strike damage still to be dealt, 1 = regular damage.
var combat_damage_substep: int = 0

var passes_in_succession: int = 0
var pending_triggers: Array = []
var life_lost_this_turn: Dictionary = {}

## The global tide, recomputed at the start of every turn.
var tide: GameEnums.Tide = GameEnums.Tide.HIGH
## Spells cast this turn per player, which is what Frenzy and Feeding Frenzy
## effects read.
var spells_cast_this_turn: Dictionary = {}
## The shared graveyard. Both players' dead cards pile up here in the order
## they sank, and Salvage costs are paid out of it.
var wreck: Array[int] = []

## Match settings, including the clock.
var rules: MatchRules = null

## Per-player turn clock overrides set by cards, in seconds. Absent means the
## match default. Cleared at end of turn when the effect was for one turn.
var turn_time_overrides: Dictionary = {}
var turn_time_overrides_temporary: Dictionary = {}
## Extra life lost when this player runs out of time, on top of the rules.
var timeout_penalties: Dictionary = {}
## Remaining match clock per player, for chess-clock modes.
var match_clock: Dictionary = {}

## Players who must skip their next turn, and players owed an extra one.
var skipped_turns: Dictionary = {}
var extra_turns: Array[int] = []

## Hands currently revealed to the opponent, set by information effects.
var revealed_hands: Dictionary = {}

## Snapshot of the board as it stood when the current turn began, which rewind
## effects restore.
var _turn_snapshot: Dictionary = {}
## Attacked players still waiting to declare blocks this combat.
var _blocker_queue: Array[int] = []

var game_over: bool = false
## The surviving player in a duel; -1 when a team of several won.
var winner_index: int = -1
## The team that won, which is what multiplayer results are read from.
var winning_team: int = -1

var event_log: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()

var _next_uid: int = 1
## Player who has not yet decided to keep their opening hand.
var _mulligan_queue: Array[int] = []
## Set while a spell or ability is resolving, so nested effects know the source.
var _resolving_source: CardInstance = null


## --- Setup ---------------------------------------------------------------

## [param decks] is one array of CardData per player, already expanded to the
## full 60 cards (or however many).
func setup(player_names: Array, decks: Array, seed_value: int = 0,
		ai_flags: Array = [], match_rules: MatchRules = null,
		star_levels: Array = [], teams: Array = []) -> void:
	rules = match_rules if match_rules != null else MatchRules.standard()
	rng.seed = seed_value if seed_value != 0 else randi()
	players.clear()
	cards.clear()
	stack.clear()
	wreck.clear()
	event_log.clear()
	spells_cast_this_turn.clear()
	turn_time_overrides.clear()
	turn_time_overrides_temporary.clear()
	revealed_hands.clear()
	extra_turns.clear()
	_turn_snapshot.clear()

	for i in player_names.size():
		var team_id := int(teams[i]) if i < teams.size() else i
		var p := PlayerState.create(i, str(player_names[i]), rules.starting_life, team_id)
		p.is_ai = i < ai_flags.size() and bool(ai_flags[i])
		players.append(p)
		var stars := (star_levels[i] as Dictionary) if i < star_levels.size() else {}
		var deck_entry: Variant = decks[i]
		var main_deck: Array = deck_entry as Array
		var vault_cards: Array = []
		if deck_entry is Dictionary:
			main_deck = (deck_entry as Dictionary).get("main", []) as Array
			vault_cards = (deck_entry as Dictionary).get("vault", []) as Array
		for card_data in main_deck:
			var level := int(stars.get(str((card_data as CardData).id), GameEnums.MIN_STARS))
			var inst := CardInstance.create(_next_uid, card_data, i, level)
			_next_uid += 1
			cards[inst.uid] = inst
			p.library.append(inst.uid)
		for card_data in vault_cards:
			var level := int(stars.get(str((card_data as CardData).id), GameEnums.MIN_STARS))
			var inst := CardInstance.create(_next_uid, card_data, i, level)
			_next_uid += 1
			inst.zone = GameEnums.Zone.VAULT
			cards[inst.uid] = inst
			p.vault.append(inst.uid)
		_shuffle_library(i)
		life_lost_this_turn[i] = 0
		spells_cast_this_turn[i] = 0
		match_clock[i] = rules.match_seconds
		skipped_turns[i] = 0
		timeout_penalties[i] = 0

	for p in players:
		_draw_without_loss(p.index, rules.starting_hand)

	active_player_index = 0
	turn_number = 0
	_mulligan_queue = []
	for p in players:
		_mulligan_queue.append(p.index)
	_begin_mulligan_decision()


func _begin_mulligan_decision() -> void:
	if _mulligan_queue.is_empty():
		_start_first_turn()
		return
	awaiting = "mulligan"
	awaiting_index = _mulligan_queue[0]
	_notify()


func _start_first_turn() -> void:
	turn_number = 1
	active_player_index = 0
	_update_tide()
	log_event("game_start", {"active": active_player_index})
	refresh_continuous()
	_turn_snapshot = capture_snapshot()
	_enter_step(GameEnums.Step.UNTAP)


func _shuffle_library(player_index: int) -> void:
	var lib := players[player_index].library
	for i in range(lib.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := lib[i]
		lib[i] = lib[j]
		lib[j] = tmp


## --- Accessors -----------------------------------------------------------

func get_card(uid: int) -> CardInstance:
	return cards.get(uid, null)

func get_player(index: int) -> PlayerState:
	return players[index] if index >= 0 and index < players.size() else null

## The next seat in turn order, skipping players who have already lost.
func next_in_turn_order(index: int) -> int:
	var count := players.size()
	for step in range(1, count + 1):
		var candidate := (index + step) % count
		if not players[candidate].has_lost:
			return candidate
	return index


## Kept for two-player convenience; with more players use [method opponents_of].
func opponent_of(index: int) -> int:
	return next_in_turn_order(index)


## Every living player not on this player's team.
func opponents_of(index: int) -> Array[int]:
	var out: Array[int] = []
	var team := get_player(index).team
	for p in players:
		if p.index != index and p.team != team and not p.has_lost:
			out.append(p.index)
	return out


## Every living ally, not counting the player themselves.
func teammates_of(index: int) -> Array[int]:
	var out: Array[int] = []
	var team := get_player(index).team
	for p in players:
		if p.index != index and p.team == team and not p.has_lost:
			out.append(p.index)
	return out


func are_allies(a: int, b: int) -> bool:
	return get_player(a).team == get_player(b).team


func living_players() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if not p.has_lost:
			out.append(p.index)
	return out

func is_over() -> bool:
	return game_over

## The player whose input the engine is waiting for.
func awaiting_player() -> int:
	return awaiting_index

## Players currently being attacked, in seat order.
func defending_players() -> Array[int]:
	var out: Array[int] = []
	for uid in attacking_uids():
		var c := get_card(uid)
		if c != null and c.attack_target >= 0 and c.attack_target not in out:
			out.append(c.attack_target)
	out.sort()
	return out


## The single defender, for two-player games and for damage that has to land
## somewhere when no target was recorded.
func defending_player_index() -> int:
	var defenders := defending_players()
	if not defenders.is_empty():
		return defenders[0]
	var enemies := opponents_of(active_player_index)
	return enemies[0] if not enemies.is_empty() else next_in_turn_order(active_player_index)

func stack_is_empty() -> bool:
	return stack.is_empty()

func current_phase() -> GameEnums.Phase:
	return GameEnums.phase_of(current_step)

## Sorcery speed: your main phase, empty stack, and you have priority.
func can_act_at_sorcery_speed(player_index: int) -> bool:
	return player_index == active_player_index \
		and GameEnums.is_main_step(current_step) \
		and stack.is_empty() \
		and awaiting == "priority" \
		and priority_player_index == player_index


func log_event(kind: String, data: Dictionary) -> void:
	var e := data.duplicate()
	e["kind"] = kind
	e["turn"] = turn_number
	event_log.append(e)
	event_logged.emit(e)

func _notify() -> void:
	state_changed.emit()

func refresh_continuous() -> void:
	ContinuousEffects.apply_all(self)


## The tide flips every round. Both players get the same number of turns
## under each state, so it is a shared rhythm rather than an advantage.
func _update_tide() -> void:
	var next_tide := GameEnums.tide_for_turn(turn_number)
	if next_tide != tide or turn_number <= 1:
		tide = next_tide
		log_event("tide", {"tide": tide, "name": GameEnums.tide_name(tide)})
		emit_trigger_event("tide_changed", {"tide": tide, "player": active_player_index})
	refresh_continuous()


## --- The wreck (shared graveyard) ---------------------------------------

func wreck_size() -> int:
	return wreck.size()

## Can this player pay a Salvage cost of [param amount]?
func can_salvage(amount: int) -> bool:
	return wreck.size() >= amount

## Exiles [param amount] cards from the bottom of the wreck (the oldest
## wrecks first) to pay a Salvage cost.
func pay_salvage(player_index: int, amount: int) -> bool:
	if not can_salvage(amount):
		return false
	for _i in amount:
		if wreck.is_empty():
			return false
		var uid: int = wreck[0]
		var card := get_card(uid)
		if card == null:
			wreck.remove_at(0)
			continue
		move_to_zone(card, GameEnums.Zone.EXILE, "salvaged")
	log_event("salvage", {"player": player_index, "amount": amount,
			"remaining": wreck.size()})
	return true


## --- Zone movement -------------------------------------------------------

## Moves a card between zones, firing the enters/leaves events that triggered
## abilities listen for.
func move_to_zone(card: CardInstance, dest: GameEnums.Zone, reason: String = "") -> void:
	var owner := get_player(card.owner_index)
	var controller := get_player(card.controller_index)
	var from := card.zone

	# Remove from wherever it is now.
	if from == GameEnums.Zone.STACK:
		stack.erase(card.uid)
	else:
		var src_player := controller if from == GameEnums.Zone.BATTLEFIELD else owner
		src_player.zone_array(from).erase(card.uid)

	if from == GameEnums.Zone.GRAVEYARD:
		wreck.erase(card.uid)

	if from == GameEnums.Zone.BATTLEFIELD:
		log_event("leaves_battlefield", {"uid": card.uid, "reason": reason})

	# A token that leaves the battlefield ceases to exist.
	if card.is_token and dest != GameEnums.Zone.BATTLEFIELD:
		card.zone = GameEnums.Zone.EXILE
		cards.erase(card.uid)
		refresh_continuous()
		return

	# Anything leaving the battlefield or the stack becomes a new object: its
	# damage, counters and temporary buffs are forgotten.
	if from == GameEnums.Zone.BATTLEFIELD or from == GameEnums.Zone.STACK:
		card.counters.clear()
		card.reset_turn_state()
		card.tapped = false
		card.targets.clear()
		card.stack_kind = ""
		card.stack_ability = {}
		card.chosen_x = 0
		card.controller_index = card.owner_index

	card.zone = dest
	match dest:
		GameEnums.Zone.BATTLEFIELD:
			card.summoning_sick = true
			card.entered_on_turn = turn_number
			card.depth = card.data.native_depth
			if card.data.is_champion() and card.data.fathom > 0:
				card.counters[GameEnums.COUNTER_FATHOM] = card.data.fathom
			get_player(card.controller_index).battlefield.append(card.uid)
			refresh_continuous()
			log_event("enters_battlefield", {"uid": card.uid})
			emit_trigger_event("enters_battlefield", {"uid": card.uid, "player": card.controller_index})
		GameEnums.Zone.STACK:
			stack.append(card.uid)
		GameEnums.Zone.LIBRARY:
			owner.library.append(card.uid)
		GameEnums.Zone.GRAVEYARD:
			owner.graveyard.append(card.uid)
			wreck.append(card.uid)
		_:
			owner.zone_array(dest).append(card.uid)

	refresh_continuous()
	log_event("zone_change", {
		"uid": card.uid, "from": from, "to": dest, "reason": reason,
	})


func put_on_battlefield(card: CardInstance, controller_index: int, tapped: bool = false) -> void:
	card.controller_index = controller_index
	move_to_zone(card, GameEnums.Zone.BATTLEFIELD)
	if tapped:
		card.tapped = true


## --- The clock -----------------------------------------------------------

## Seconds this player gets for their turn, after any card effects. Returns 0
## when the mode has no per-turn limit.
func turn_time_limit(player_index: int) -> float:
	var base := rules.turn_seconds
	if turn_time_overrides.has(player_index):
		base = float(turn_time_overrides[player_index])

	# Permanents that squeeze or stretch the clock are static effects, so the
	# limit goes back to normal the moment one leaves the battlefield.
	for p in players:
		for uid in p.battlefield:
			var c := get_card(uid)
			if c == null:
				continue
			for ability in c.data.abilities_of_kind("static"):
				var eff := (ability as Dictionary).get("effect", {}) as Dictionary
				if str(eff.get("type", "")) != "turn_timer":
					continue
				var scope := str(eff.get("target", "opponent"))
				var applies := (scope == "you" and player_index == c.controller_index) \
					or (scope == "opponent" and player_index != c.controller_index) \
					or scope == "all"
				if not applies:
					continue
				if eff.has("seconds"):
					var seconds := float(eff["seconds"])
					# A clock-setting permanent installs a limit even in modes
					# that otherwise have none.
					base = seconds if base <= 0.0 else minf(base, seconds)
				if eff.has("factor"):
					if base > 0.0:
						base *= float(eff["factor"])

	if base <= 0.0:
		return 0.0
	return maxf(1.0, base)


## Sets a player's turn clock from a card effect.
## [param temporary] wears off at the next cleanup step.
func set_turn_time_limit(player_index: int, seconds: float, temporary: bool) -> void:
	turn_time_overrides[player_index] = maxf(1.0, seconds)
	turn_time_overrides_temporary[player_index] = temporary
	log_event("turn_clock", {
		"player": player_index, "seconds": turn_time_limit(player_index),
		"temporary": temporary,
	})


## Multiplies the current limit, which is how "halve their time" and "double
## your time" are written on cards.
func scale_turn_time_limit(player_index: int, factor: float, temporary: bool) -> void:
	var base := turn_time_limit(player_index)
	if base <= 0.0:
		# No clock to scale: a shortening effect installs one instead so the
		# card still does something in Standard.
		if factor < 1.0:
			set_turn_time_limit(player_index, 30.0 * factor, temporary)
		return
	set_turn_time_limit(player_index, base * factor, temporary)


func add_timeout_penalty(player_index: int, life: int) -> void:
	timeout_penalties[player_index] = int(timeout_penalties.get(player_index, 0)) + life
	log_event("timeout_penalty", {"player": player_index, "life": life})


## Called by the controller when a player's clock runs out. The engine decides
## the consequence so that every mode behaves the same way in tests.
func handle_timeout(player_index: int) -> void:
	if game_over:
		return
	log_event("timeout", {"player": player_index})

	if rules.timeout_rule == MatchRules.Timeout.LOSE_GAME:
		_player_loses(player_index, "out of time")
		return

	var life_loss := rules.timeout_life_loss + int(timeout_penalties.get(player_index, 0))
	if rules.timeout_rule == MatchRules.Timeout.END_TURN_DAMAGE and life_loss > 0:
		lose_life(player_index, life_loss)
		check_state_based_actions()
		if game_over:
			return

	# Clear the stack by letting everything resolve, then jump to the end of
	# the turn. A player out of time does not get to act further.
	if player_index == active_player_index:
		_force_end_turn()
	else:
		# The non-active player simply loses priority for the rest of the step.
		if awaiting == "priority" and priority_player_index == player_index:
			_pass_priority()
		elif awaiting == "blockers" and awaiting_index == player_index:
			# No blocks declared.
			perform(GameAction.declare_blockers(player_index, {}))


func _force_end_turn() -> void:
	log_event("forced_end", {"player": active_player_index})
	# Anything on the stack still resolves, oldest first.
	var guard := 0
	while not stack.is_empty() and guard < 100 and not game_over:
		guard += 1
		_resolve_top()
	if game_over:
		return
	Combat.end_combat(self)
	_enter_step(GameEnums.Step.CLEANUP)


## Chess clock bookkeeping, driven by the controller.
func consume_match_clock(player_index: int, seconds: float) -> void:
	if not rules.uses_match_clock():
		return
	var left := float(match_clock.get(player_index, 0.0)) - seconds
	match_clock[player_index] = maxf(0.0, left)
	if left <= 0.0:
		handle_timeout(player_index)


func remaining_match_clock(player_index: int) -> float:
	return float(match_clock.get(player_index, 0.0))


## --- Turn control --------------------------------------------------------

func skip_next_turn(player_index: int) -> void:
	skipped_turns[player_index] = int(skipped_turns.get(player_index, 0)) + 1
	log_event("skip_turn", {"player": player_index})


func grant_extra_turn(player_index: int) -> void:
	extra_turns.append(player_index)
	log_event("extra_turn", {"player": player_index})


## --- Dice ----------------------------------------------------------------

## Rolls [param count] dice of [param sides] and adds the player's dice bonus
## from permanents. Gambling cards branch on the result.
func roll_dice(player_index: int, sides: int, count: int = 1) -> int:
	var raw := 0
	var faces: Array[int] = []
	for _i in maxi(count, 1):
		var face := rng.randi_range(1, maxi(sides, 2))
		faces.append(face)
		raw += face
	var bonus := dice_bonus_for(player_index)
	var total := raw + bonus
	log_event("dice", {
		"player": player_index, "sides": sides, "faces": faces,
		"raw": raw, "bonus": bonus, "total": total,
	})
	return total


## Total dice bonus granted by permanents this player controls. Stacking these
## is a deck archetype in its own right.
func dice_bonus_for(player_index: int) -> int:
	var total := 0
	for uid in get_player(player_index).battlefield:
		var c := get_card(uid)
		if c == null:
			continue
		for ability in c.data.abilities_of_kind("static"):
			var eff := (ability as Dictionary).get("effect", {}) as Dictionary
			if str(eff.get("type", "")) == "dice_bonus":
				total += int(eff.get("amount", 0))
	return total


## --- Rewind --------------------------------------------------------------

## Captures the whole board. Taken at the start of each turn so that a rewind
## effect can undo everything that happened during it.
func capture_snapshot() -> Dictionary:
	var card_states := {}
	for uid in cards:
		card_states[uid] = (cards[uid] as CardInstance).snapshot()
	var player_states := []
	for p in players:
		player_states.append(p.snapshot())
	return {
		"cards": card_states,
		"players": player_states,
		"stack": stack.duplicate(),
		"wreck": wreck.duplicate(),
		"turn": turn_number,
		"active": active_player_index,
		"tide": tide,
		"spells": spells_cast_this_turn.duplicate(),
		"life_lost": life_lost_this_turn.duplicate(),
		"next_uid": _next_uid,
	}


## Restores a snapshot. [param keep_uids] are cards left as they are, which is
## how the rewind card itself avoids being undone along with everything else.
func restore_snapshot(state: Dictionary, keep_uids: Array[int] = []) -> void:
	if state.is_empty():
		return
	var card_states := state["cards"] as Dictionary

	# Objects created after the snapshot (tokens, stacked abilities) never
	# existed in the restored world, so drop them.
	for uid in cards.keys():
		if not card_states.has(uid) and int(uid) not in keep_uids:
			cards.erase(uid)

	for uid in card_states:
		var c: CardInstance = cards.get(uid, null)
		if c == null or int(uid) in keep_uids:
			continue
		c.restore(card_states[uid] as Dictionary)

	var player_states := state["players"] as Array
	for i in players.size():
		if i < player_states.size():
			players[i].restore(player_states[i] as Dictionary)

	stack = _int_array(state["stack"])
	wreck = _int_array(state["wreck"])
	tide = state["tide"]
	spells_cast_this_turn = (state["spells"] as Dictionary).duplicate()
	life_lost_this_turn = (state["life_lost"] as Dictionary).duplicate()

	# Anything kept out of the restore must not linger in a zone it no longer
	# belongs to.
	for uid in keep_uids:
		stack.erase(uid)

	refresh_continuous()
	check_state_based_actions()
	log_event("rewind", {"turn": turn_number})
	_notify()


static func _int_array(value: Variant) -> Array[int]:
	var out: Array[int] = []
	for v in value as Array:
		out.append(int(v))
	return out


func turn_snapshot() -> Dictionary:
	return _turn_snapshot


## --- Information ---------------------------------------------------------

func reveal_hand(player_index: int, revealed_to: int) -> void:
	revealed_hands[player_index] = revealed_to
	log_event("reveal_hand", {"player": player_index, "to": revealed_to})

func hand_is_revealed_to(owner_index: int, viewer_index: int) -> bool:
	return owner_index == viewer_index or int(revealed_hands.get(owner_index, -1)) == viewer_index


## --- Depth bands ---------------------------------------------------------

## Moves a creature to a band, clamped to the three that exist. [param forced]
## skips the Anchored check, which is how Kraken's Grasp and the like drag
## creatures around against their will.
func set_depth(card: CardInstance, band: int, forced: bool = false) -> bool:
	if not card.is_creature() or card.zone != GameEnums.Zone.BATTLEFIELD:
		return false
	if not forced and not card.can_change_depth():
		return false
	var clamped: int = clampi(band, int(GameEnums.Depth.SURFACE), int(GameEnums.Depth.ABYSS))
	if clamped == int(card.depth):
		return false
	var from := card.depth
	card.depth = clamped as GameEnums.Depth
	log_event("depth_change", {
		"uid": card.uid, "from": from, "to": card.depth,
		"name": GameEnums.depth_name(card.depth), "forced": forced,
	})
	refresh_continuous()
	return true


## Creatures a player could still move this turn, with the bands they may
## move to: {uid: [delta, ...]}.
func possible_depth_moves(player_index: int) -> Dictionary:
	var out: Dictionary = {}
	var p := get_player(player_index)
	for uid in p.battlefield:
		var c := get_card(uid)
		if c == null or not c.is_creature() or not c.can_change_depth():
			continue
		var is_diver := c.has_keyword(GameEnums.KW_DIVER)
		# The budget is one creature per turn; Diver moves on top of it.
		if not is_diver and not p.can_move_depth():
			continue
		var reach := 2 if is_diver else 1
		var deltas: Array[int] = []
		for delta in range(-reach, reach + 1):
			if delta == 0:
				continue
			var band := int(c.depth) + delta
			if band >= int(GameEnums.Depth.SURFACE) and band <= int(GameEnums.Depth.ABYSS):
				deltas.append(delta)
		if not deltas.is_empty():
			out[uid] = deltas
	return out


## --- Card flow -----------------------------------------------------------

func draw_cards(player_index: int, count: int) -> void:
	var p := get_player(player_index)
	for _i in count:
		if p.library.is_empty():
			p.tried_to_draw_from_empty = true
			log_event("draw_from_empty", {"player": player_index})
			return
		var uid: int = p.library.pop_front()
		var card := get_card(uid)
		card.zone = GameEnums.Zone.HAND
		p.hand.append(uid)
		log_event("draw", {"player": player_index, "uid": uid})

## Used during setup and mulligans, where running out is impossible.
func _draw_without_loss(player_index: int, count: int) -> void:
	var p := get_player(player_index)
	for _i in count:
		if p.library.is_empty():
			return
		var uid: int = p.library.pop_front()
		get_card(uid).zone = GameEnums.Zone.HAND
		p.hand.append(uid)


func discard_cards(player_index: int, count: int, mode: String = "random") -> void:
	var p := get_player(player_index)
	for _i in count:
		if p.hand.is_empty():
			return
		var uid: int
		if mode == "random":
			uid = p.hand[rng.randi_range(0, p.hand.size() - 1)]
		else:
			# "choice" falls back to the last card drawn; a real prompt can be
			# added here once the UI supports mid-resolution choices.
			uid = p.hand[p.hand.size() - 1]
		var card := get_card(uid)
		move_to_zone(card, GameEnums.Zone.GRAVEYARD, "discarded")
		log_event("discard", {"player": player_index, "uid": uid})


func mill_cards(player_index: int, count: int) -> void:
	var p := get_player(player_index)
	for _i in count:
		if p.library.is_empty():
			p.tried_to_draw_from_empty = true
			return
		var uid: int = p.library.pop_front()
		var card := get_card(uid)
		card.zone = GameEnums.Zone.LIBRARY
		move_to_zone(card, GameEnums.Zone.GRAVEYARD, "milled")


func search_library_for_basic(player_index: int, to_battlefield: bool, enters_tapped: bool) -> void:
	var p := get_player(player_index)
	for uid in p.library:
		var c := get_card(uid)
		if c != null and c.data.is_basic_land():
			p.library.erase(uid)
			c.zone = GameEnums.Zone.LIBRARY
			if to_battlefield:
				put_on_battlefield(c, player_index, enters_tapped)
			else:
				c.zone = GameEnums.Zone.HAND
				p.hand.append(uid)
				log_event("tutor", {"player": player_index, "uid": uid})
			_shuffle_library(player_index)
			return
	_shuffle_library(player_index)


## Looks at the top [param count] cards and puts the worst on the bottom.
## Resolved automatically: a land is kept when the player has few, otherwise
## the cheapest spell is kept.
func scry(player_index: int, count: int) -> void:
	var p := get_player(player_index)
	var land_count := 0
	for uid in p.battlefield:
		if get_card(uid).is_land():
			land_count += 1
	var bottomed: Array[int] = []
	for _i in count:
		if p.library.is_empty():
			break
		var uid: int = p.library[0]
		var c := get_card(uid)
		var keep := true
		if c.data.is_land() and land_count >= 5:
			keep = false
		elif not c.data.is_land() and c.data.mana_value() > land_count + 2:
			keep = false
		if keep:
			break
		p.library.pop_front()
		bottomed.append(uid)
	for uid in bottomed:
		p.library.append(uid)
	if not bottomed.is_empty():
		log_event("scry", {"player": player_index, "bottomed": bottomed.size()})


## Moves a permanent to another player's side of the board.
func change_control(card: CardInstance, new_controller: int) -> bool:
	if card.zone != GameEnums.Zone.BATTLEFIELD or card.controller_index == new_controller:
		return false
	get_player(card.controller_index).battlefield.erase(card.uid)
	card.controller_index = new_controller
	get_player(new_controller).battlefield.append(card.uid)
	# A permanent that changes sides is freshly arrived for its new owner.
	card.summoning_sick = true
	card.reset_combat_state()
	refresh_continuous()
	log_event("control_change", {"uid": card.uid, "to": new_controller})
	return true


## Puts a copy of any card definition onto the battlefield as a token.
func create_copy(data: CardData, controller_index: int, stars: int = GameEnums.MIN_STARS) -> CardInstance:
	var inst := CardInstance.create(_next_uid, data, controller_index, stars)
	_next_uid += 1
	inst.is_token = true
	cards[inst.uid] = inst
	put_on_battlefield(inst, controller_index)
	log_event("copy_created", {"uid": inst.uid, "name": data.name})
	return inst


## Takes the top [param count] cards of another player's library into
## [param thief]'s hand. Stealing from the deck itself, not the hand.
func steal_from_library(thief: int, victim: int, count: int) -> int:
	var source := get_player(victim)
	var taken := 0
	for _i in count:
		if source.library.is_empty():
			source.tried_to_draw_from_empty = true
			break
		var uid: int = source.library.pop_front()
		var card := get_card(uid)
		card.zone = GameEnums.Zone.HAND
		get_player(thief).hand.append(uid)
		taken += 1
		log_event("steal_library", {"thief": thief, "victim": victim, "uid": uid})
	return taken


## Takes a card out of another player's hand. Picks the most expensive one,
## which is what a player would choose when allowed to look.
func steal_from_hand(thief: int, victim: int, count: int) -> int:
	var source := get_player(victim)
	var taken := 0
	for _i in count:
		if source.hand.is_empty():
			break
		var best: int = source.hand[0]
		var best_value := -1
		for uid in source.hand:
			var c := get_card(uid)
			if c != null and c.data.mana_value() > best_value:
				best_value = c.data.mana_value()
				best = uid
		source.hand.erase(best)
		get_card(best).zone = GameEnums.Zone.HAND
		get_player(thief).hand.append(best)
		taken += 1
		log_event("steal_hand", {"thief": thief, "victim": victim, "uid": best})
	return taken


## Empties a hand into the wreck.
func discard_entire_hand(player_index: int) -> int:
	var p := get_player(player_index)
	var n := p.hand.size()
	for uid in p.hand.duplicate():
		var card := get_card(uid)
		if card != null:
			move_to_zone(card, GameEnums.Zone.GRAVEYARD, "discarded")
	log_event("discard_hand", {"player": player_index, "count": n})
	return n


## Swaps two players' hands outright.
func swap_hands(a_index: int, b_index: int) -> void:
	var a := get_player(a_index)
	var b := get_player(b_index)
	var a_hand := a.hand.duplicate()
	var b_hand := b.hand.duplicate()
	a.hand = b_hand
	b.hand = a_hand
	# Cards keep their owner; only who is holding them changes, and both piles
	# are already in the hand zone.
	log_event("swap_hands", {"a": a_index, "b": b_index,
			"sizes": [a.hand.size(), b.hand.size()]})


## Pulls a card out of the shared wreck, including cards the opponent owns.
func recover_from_wreck(player_index: int, filter: Dictionary, to_battlefield: bool) -> CardInstance:
	# Newest wrecks first: the thing that just died is usually what you want.
	for i in range(wreck.size() - 1, -1, -1):
		var card := get_card(wreck[i])
		if card == null:
			continue
		if not Targeting.matches_filter(self, filter, card):
			continue
		card.controller_index = player_index
		if to_battlefield:
			# It arrives under the recovering player's control.
			card.owner_index = player_index
			move_to_zone(card, GameEnums.Zone.BATTLEFIELD, "recovered")
		else:
			card.owner_index = player_index
			move_to_zone(card, GameEnums.Zone.HAND, "recovered")
		log_event("recover", {"player": player_index, "uid": card.uid})
		return card
	return null


## Fetches from the player's own Abyssal Vault.
func fetch_from_vault(player_index: int, filter: Dictionary, to_battlefield: bool) -> CardInstance:
	var p := get_player(player_index)
	for uid in p.vault.duplicate():
		var card := get_card(uid)
		if card == null:
			continue
		if not filter.is_empty() and not Targeting.matches_filter(self, filter, card):
			continue
		p.vault.erase(uid)
		card.zone = GameEnums.Zone.VAULT
		if to_battlefield:
			put_on_battlefield(card, player_index)
		else:
			card.zone = GameEnums.Zone.HAND
			p.hand.append(uid)
		log_event("vault_fetch", {"player": player_index, "uid": uid,
				"name": card.data.name})
		return card
	return null


func create_token(token_id: String, controller_index: int) -> CardInstance:
	var data: CardData = Cards.get_card(token_id)
	if data == null:
		push_warning("Unknown token: %s" % token_id)
		return null
	var inst := CardInstance.create(_next_uid, data, controller_index)
	_next_uid += 1
	inst.is_token = true
	cards[inst.uid] = inst
	put_on_battlefield(inst, controller_index)
	log_event("token_created", {"uid": inst.uid, "name": data.name})
	return inst


## --- Life and damage -----------------------------------------------------

func gain_life(player_index: int, amount: int) -> void:
	if amount <= 0:
		return
	get_player(player_index).gain_life(amount)
	log_event("life", {"player": player_index, "delta": amount})
	emit_trigger_event("life_gained", {"player": player_index, "amount": amount})


func lose_life(player_index: int, amount: int, source: CardInstance = null) -> void:
	if amount <= 0:
		return
	get_player(player_index).lose_life(amount)
	life_lost_this_turn[player_index] = int(life_lost_this_turn.get(player_index, 0)) + amount
	log_event("life", {"player": player_index, "delta": -amount})


func deal_damage_to_player(player_index: int, amount: int, source: CardInstance = null, is_combat: bool = false) -> void:
	if amount <= 0:
		return
	lose_life(player_index, amount, source)
	log_event("damage_player", {"player": player_index, "amount": amount,
			"source": source.uid if source != null else 0})
	if source != null:
		_apply_lifelink(source, amount)
		if is_combat:
			emit_trigger_event("combat_damage_to_player", {
				"uid": source.uid, "player": player_index, "amount": amount,
			})


func deal_damage_to_permanent(card: CardInstance, amount: int, source: CardInstance = null, is_combat: bool = false) -> void:
	if amount <= 0 or card.zone != GameEnums.Zone.BATTLEFIELD:
		return

	# A Champion loses Fathom rather than taking damage; running out is what
	# kills it.
	if card.is_champion():
		card.add_counters(GameEnums.COUNTER_FATHOM, -amount)
		log_event("champion_damage", {"uid": card.uid, "amount": amount,
				"fathom": card.fathom_count()})
		if source != null:
			_apply_lifelink(source, amount)
		return

	card.damage += amount
	log_event("damage", {"uid": card.uid, "amount": amount,
			"source": source.uid if source != null else 0})
	if source != null:
		_apply_lifelink(source, amount)
		# Any nonzero damage from a deathtouch source destroys the creature.
		if card.is_creature() and (source.has_keyword(GameEnums.KW_VENOMOUS) or source.temp_deathtouch):
			if not card.has_keyword(GameEnums.KW_UNSINKABLE):
				card.damage = max(card.damage, card.eff_toughness)


func _apply_lifelink(source: CardInstance, amount: int) -> void:
	if source.has_keyword(GameEnums.KW_SIPHON):
		gain_life(source.controller_index, amount)


func destroy_permanent(card: CardInstance, source: CardInstance = null) -> void:
	if card.zone != GameEnums.Zone.BATTLEFIELD:
		return
	if card.has_keyword(GameEnums.KW_UNSINKABLE):
		log_event("destroy_failed", {"uid": card.uid, "reason": "indestructible"})
		return
	_send_to_graveyard(card, "destroyed")


func sacrifice_permanent(card: CardInstance) -> void:
	if card.zone != GameEnums.Zone.BATTLEFIELD:
		return
	_send_to_graveyard(card, "sacrificed")


func _send_to_graveyard(card: CardInstance, reason: String) -> void:
	# The dies trigger must see the permanent as it was, so fire it before the
	# card is reset by the zone change.
	var was_creature := card.is_creature()
	var controller := card.controller_index
	emit_trigger_event("dies", {"uid": card.uid, "player": controller, "was_creature": was_creature})
	move_to_zone(card, GameEnums.Zone.GRAVEYARD, reason)
	log_event("dies", {"uid": card.uid, "reason": reason})


## --- Triggers and the stack ----------------------------------------------

## Queues every triggered ability that fires for this event. Queued triggers
## go on the stack the next time a player would receive priority.
func emit_trigger_event(event_name: String, data: Dictionary) -> void:
	for entry in Triggers.collect(self, event_name, data):
		pending_triggers.append(entry)


## Puts queued triggers on the stack in APNAP order: the active player's
## triggers first, so the non-active player's resolve earlier.
func _put_triggers_on_stack() -> bool:
	if pending_triggers.is_empty():
		return false
	var queued := pending_triggers
	pending_triggers = []

	var ordered: Array = []
	for entry in queued:
		if (entry["source"] as CardInstance).controller_index == active_player_index:
			ordered.append(entry)
	for entry in queued:
		if (entry["source"] as CardInstance).controller_index != active_player_index:
			ordered.append(entry)

	for entry in ordered:
		var src: CardInstance = entry["source"]
		var ability := entry["ability"] as Dictionary
		var specs := ability.get("targets", []) as Array
		var chosen := auto_choose_targets(specs, src.controller_index, src)
		if specs.size() > 0 and chosen.size() < specs.size():
			# No legal target: the trigger is simply removed from the stack.
			log_event("trigger_fizzled", {"uid": src.uid})
			continue
		_push_ability(src, ability, chosen, 0, "triggered")
	return true


## Creates the stack object for an activated or triggered ability.
func _push_ability(source: CardInstance, ability: Dictionary, targets: Array,
		x_value: int, kind_label: String) -> CardInstance:
	var inst := CardInstance.create(_next_uid, source.data, source.controller_index)
	_next_uid += 1
	inst.controller_index = source.controller_index
	inst.stack_kind = "ability"
	inst.stack_ability = ability
	inst.source_uid = source.uid
	inst.targets = targets.duplicate(true)
	inst.chosen_x = x_value
	inst.zone = GameEnums.Zone.STACK
	cards[inst.uid] = inst
	stack.append(inst.uid)
	log_event("ability_on_stack", {
		"uid": inst.uid, "source": source.uid, "name": source.data.name,
		"trigger": kind_label,
	})
	return inst


## Picks targets for an ability whose controller is not being prompted, which
## covers triggered abilities and the AI. Prefers the opponent's best creature
## for harmful effects and the controller's best for helpful ones.
func auto_choose_targets(specs: Array, controller: int, source: CardInstance) -> Array:
	var chosen: Array = []
	for spec_variant in specs:
		var spec := spec_variant as Dictionary
		var options := Targeting.legal_targets(self, spec, controller, source)
		if options.is_empty():
			if bool(spec.get("optional", false)):
				chosen.append({})
				continue
			return chosen
		chosen.append(_best_target(options, spec, controller))
	return chosen


func _best_target(options: Array, spec: Dictionary, controller: int) -> Dictionary:
	var prefer_enemy := str(spec.get("controller", "any")) != "you"
	var best: Dictionary = options[0]
	var best_score := -9999
	for opt in options:
		var o := opt as Dictionary
		var score := 0
		if str(o.get("type", "")) == "player":
			score = 5 if int(o.get("index", -1)) != controller else -5
		else:
			var c := get_card(int(o.get("uid", 0)))
			if c == null:
				continue
			var value := c.eff_power + c.eff_toughness + c.data.mana_value()
			var enemy := c.controller_index != controller
			if prefer_enemy:
				score = value if enemy else -value
			else:
				score = value if not enemy else -value
		if score > best_score:
			best_score = score
			best = o
	return best


## Resolves the top object on the stack.
func _resolve_top() -> void:
	if stack.is_empty():
		return
	var uid: int = stack[stack.size() - 1]
	var obj := get_card(uid)
	if obj == null:
		stack.pop_back()
		return

	var specs: Array = []
	var effect_list: Array = []
	var source_for_effects := obj

	if obj.stack_kind == "ability":
		specs = obj.stack_ability.get("targets", []) as Array
		effect_list = obj.stack_ability.get("effects", []) as Array
		var origin := get_card(obj.source_uid)
		if origin != null:
			source_for_effects = origin
	else:
		var spell_abilities := obj.data.abilities_of_kind("spell")
		if not spell_abilities.is_empty():
			var sa := spell_abilities[0] as Dictionary
			specs = sa.get("targets", []) as Array
			effect_list = sa.get("effects", []) as Array

	# A spell or ability whose targets have all become illegal does not
	# resolve at all.
	if specs.size() > 0 and not _any_target_still_legal(specs, obj):
		log_event("fizzle", {"uid": uid, "name": obj.data.name})
		stack.pop_back()
		_finish_resolution(obj, true)
		return

	stack.pop_back()
	_resolving_source = source_for_effects

	var ctx := {
		"controller": obj.controller_index,
		"source": source_for_effects,
		"targets": obj.targets,
		"target_specs": specs,
		"x": obj.chosen_x,
		"star": obj.star_level,
		"stack_uid": obj.uid,
	}

	if obj.stack_kind == "ability":
		log_event("resolve_ability", {"uid": uid, "name": obj.data.name})
		Effects.execute(self, effect_list, ctx)
		cards.erase(uid)
	elif obj.data.is_permanent():
		log_event("resolve_spell", {"uid": uid, "name": obj.data.name})
		obj.zone = GameEnums.Zone.STACK
		put_on_battlefield(obj, obj.controller_index)
		# A permanent spell can also carry an on-resolution effect.
		if not effect_list.is_empty():
			ctx["source"] = obj
			Effects.execute(self, effect_list, ctx)
	else:
		log_event("resolve_spell", {"uid": uid, "name": obj.data.name})
		Effects.execute(self, effect_list, ctx)
		move_to_zone(obj, GameEnums.Zone.GRAVEYARD, "resolved")

	_resolving_source = null
	refresh_continuous()
	check_state_based_actions()


func _any_target_still_legal(specs: Array, obj: CardInstance) -> bool:
	var found_any := false
	for i in specs.size():
		if i >= obj.targets.size():
			continue
		var t := obj.targets[i] as Dictionary
		if t.is_empty():
			continue
		if Targeting.is_still_legal(self, specs[i] as Dictionary, t, obj.controller_index, obj):
			found_any = true
	return found_any


func _finish_resolution(obj: CardInstance, fizzled: bool) -> void:
	if obj.stack_kind == "ability":
		cards.erase(obj.uid)
	else:
		move_to_zone(obj, GameEnums.Zone.GRAVEYARD, "fizzled" if fizzled else "resolved")


## Removes a spell from the stack and puts it in its owner's graveyard.
func counter_spell(spell: CardInstance) -> void:
	if not spell.uid in stack:
		return
	stack.erase(spell.uid)
	log_event("countered", {"uid": spell.uid, "name": spell.data.name})
	if spell.stack_kind == "ability":
		cards.erase(spell.uid)
	else:
		move_to_zone(spell, GameEnums.Zone.GRAVEYARD, "countered")


## --- Turn structure ------------------------------------------------------

func _enter_step(step: GameEnums.Step) -> void:
	current_step = step
	combat_damage_substep = 0
	_empty_mana_pools()
	log_event("step", {"step": step, "active": active_player_index,
			"name": GameEnums.step_name(step)})

	match step:
		GameEnums.Step.UNTAP:
			_untap_step()
			_advance_step()

		GameEnums.Step.UPKEEP:
			emit_trigger_event("upkeep", {"player": active_player_index})
			_open_priority(active_player_index)

		GameEnums.Step.DRAW:
			# The player who goes first skips their first draw.
			if not (turn_number == 1 and active_player_index == 0):
				draw_cards(active_player_index, 1)
			emit_trigger_event("draw_step", {"player": active_player_index})
			_open_priority(active_player_index)

		GameEnums.Step.DECLARE_ATTACKERS:
			if _possible_attackers(active_player_index).is_empty():
				log_event("no_attackers", {})
				_skip_to_step(GameEnums.Step.END_COMBAT)
				return
			awaiting = "attackers"
			awaiting_index = active_player_index
			_notify()

		GameEnums.Step.DECLARE_BLOCKERS:
			if _attacking_uids().is_empty():
				_skip_to_step(GameEnums.Step.END_COMBAT)
				return
			# Every attacked player declares blocks, one after another.
			_blocker_queue = defending_players()
			_ask_next_defender()

		GameEnums.Step.COMBAT_DAMAGE:
			if _attacking_uids().is_empty():
				_skip_to_step(GameEnums.Step.END_COMBAT)
				return
			if Combat.needs_first_strike_step(self):
				combat_damage_substep = 0
				Combat.deal_combat_damage(self, true)
			else:
				combat_damage_substep = 1
				Combat.deal_combat_damage(self, false)
			check_state_based_actions()
			if game_over:
				return
			_open_priority(active_player_index)

		GameEnums.Step.END_COMBAT:
			Combat.end_combat(self)
			_open_priority(active_player_index)

		GameEnums.Step.END_STEP:
			emit_trigger_event("end_step", {"player": active_player_index})
			_open_priority(active_player_index)

		GameEnums.Step.CLEANUP:
			_cleanup_step()

		_:
			_open_priority(active_player_index)


func _untap_step() -> void:
	var p := get_player(active_player_index)
	for uid in p.battlefield:
		var c := get_card(uid)
		if c == null:
			continue
		c.tapped = false
		c.summoning_sick = false
	p.begin_turn()
	life_lost_this_turn[active_player_index] = 0
	log_event("untap", {"player": active_player_index})


func _cleanup_step() -> void:
	var p := get_player(active_player_index)
	# Discard down to the maximum hand size.
	while p.hand.size() > rules.max_hand_size:
		discard_cards(active_player_index, 1, "choice")

	for uid in cards.keys():
		var c: CardInstance = cards[uid]
		if c != null and c.zone == GameEnums.Zone.BATTLEFIELD:
			c.reset_turn_state()

	# Clock effects that lasted a single turn wear off here.
	for key in turn_time_overrides_temporary.keys():
		if bool(turn_time_overrides_temporary[key]):
			turn_time_overrides.erase(key)
			turn_time_overrides_temporary.erase(key)
	refresh_continuous()
	check_state_based_actions()
	if game_over:
		return

	# Triggers that fired during cleanup get a round of priority; otherwise
	# the turn simply ends.
	if not pending_triggers.is_empty():
		_open_priority(active_player_index)
		return
	_begin_next_turn()


func _begin_next_turn() -> void:
	# An extra turn granted this turn is taken before passing the turn on.
	if not extra_turns.is_empty():
		var who: int = extra_turns.pop_front()
		active_player_index = who
		log_event("extra_turn_taken", {"player": who})
	else:
		active_player_index = opponent_of(active_player_index)
		# Skipped turns are consumed one at a time; the turn passes straight
		# back to the other player.
		var guard := 0
		while int(skipped_turns.get(active_player_index, 0)) > 0 and guard < 4:
			guard += 1
			skipped_turns[active_player_index] = int(skipped_turns[active_player_index]) - 1
			log_event("turn_skipped", {"player": active_player_index})
			active_player_index = opponent_of(active_player_index)

	turn_number += 1
	for p in players:
		spells_cast_this_turn[p.index] = 0
	_update_tide()
	if rules.uses_match_clock() and rules.increment_seconds > 0.0:
		match_clock[active_player_index] = \
			float(match_clock.get(active_player_index, 0.0)) + rules.increment_seconds
	log_event("turn_start", {"turn": turn_number, "active": active_player_index,
			"time_limit": turn_time_limit(active_player_index)})
	_turn_snapshot = capture_snapshot()
	_enter_step(GameEnums.Step.UNTAP)


func _advance_step() -> void:
	# A second combat damage step for creatures without first strike.
	if current_step == GameEnums.Step.COMBAT_DAMAGE and combat_damage_substep == 0:
		combat_damage_substep = 1
		Combat.deal_combat_damage(self, false)
		check_state_based_actions()
		if game_over:
			return
		_open_priority(active_player_index)
		return

	var index := GameEnums.TURN_SEQUENCE.find(current_step)
	if index < 0 or index >= GameEnums.TURN_SEQUENCE.size() - 1:
		_begin_next_turn()
		return
	_enter_step(GameEnums.TURN_SEQUENCE[index + 1])


func _skip_to_step(step: GameEnums.Step) -> void:
	log_event("skip_to", {"step": step, "name": GameEnums.step_name(step)})
	_enter_step(step)


func _empty_mana_pools() -> void:
	for p in players:
		p.mana_pool.clear()


## --- Priority ------------------------------------------------------------

func _open_priority(player_index: int) -> void:
	# Triggers waiting to go on the stack do so before anyone acts.
	_put_triggers_on_stack()
	check_state_based_actions()
	if game_over:
		return
	# State-based actions can put more triggers on the queue (a dying creature
	# with a dies trigger, say), so drain them.
	while _put_triggers_on_stack():
		check_state_based_actions()
		if game_over:
			return

	awaiting = "priority"
	awaiting_index = player_index
	priority_player_index = player_index
	passes_in_succession = 0
	_notify()


## Called after any action that keeps priority with its controller.
func _retain_priority() -> void:
	passes_in_succession = 0
	_open_priority(priority_player_index)


func _pass_priority() -> void:
	passes_in_succession += 1
	if passes_in_succession < living_players().size():
		priority_player_index = next_in_turn_order(priority_player_index)
		awaiting_index = priority_player_index
		_notify()
		return

	# Everyone passed in succession.
	passes_in_succession = 0
	if not stack.is_empty():
		_resolve_top()
		if game_over:
			return
		_open_priority(active_player_index)
	else:
		_advance_step()


## --- State-based actions -------------------------------------------------

## Runs repeatedly until nothing more changes, exactly as the rules require.
func check_state_based_actions() -> bool:
	var any_change := false
	var guard := 0
	while guard < 50:
		guard += 1
		var changed := false

		for p in players:
			if p.has_lost:
				continue
			if p.life <= 0:
				_player_loses(p.index, "life")
				changed = true
			elif p.tried_to_draw_from_empty:
				_player_loses(p.index, "decked")
				changed = true

		for p in players:
			for uid in p.battlefield.duplicate():
				var c := get_card(uid)
				if c == null:
					continue
				if c.is_champion() and c.fathom_count() <= 0:
					_send_to_graveyard(c, "out of fathom")
					changed = true
					continue
				if not c.is_creature():
					continue
				if c.has_zero_toughness():
					# Zero toughness is not destruction: indestructible does
					# not save it.
					_send_to_graveyard(c, "zero toughness")
					changed = true
				elif c.is_lethally_damaged() and not c.has_keyword(GameEnums.KW_UNSINKABLE):
					# Molt sheds the wound instead of dying, once per turn.
					if c.has_keyword(GameEnums.KW_MOLT) and not c.molt_spent:
						c.molt_spent = true
						c.damage = 0
						log_event("molt", {"uid": c.uid, "name": c.data.name})
					else:
						_send_to_graveyard(c, "lethal damage")
					changed = true

		if _enforce_uniqueness():
			changed = true

		if changed:
			any_change = true
			refresh_continuous()
			_check_for_winner()
			if game_over:
				return true
		else:
			break

	if any_change:
		_check_for_winner()
	return any_change


## A player may control only one copy of a given Relic or Champion. The
## newest arrival stays and the rest are put in the wreck.
func _enforce_uniqueness() -> bool:
	var changed := false
	for p in players:
		var seen: Dictionary = {}
		for uid in p.battlefield.duplicate():
			var c := get_card(uid)
			if c == null:
				continue
			if not (c.data.is_unique() or c.is_champion()):
				continue
			var key := str(c.data.id)
			if seen.has(key):
				var older: int = int(seen[key])
				var loser := older if older < uid else uid
				seen[key] = older if older > uid else uid
				var doomed := get_card(loser)
				if doomed != null and doomed.zone == GameEnums.Zone.BATTLEFIELD:
					_send_to_graveyard(doomed, "uniqueness rule")
					changed = true
			else:
				seen[key] = uid
	return changed


func _player_loses(player_index: int, reason: String) -> void:
	var p := get_player(player_index)
	if p.has_lost:
		return
	p.has_lost = true
	p.loss_reason = reason
	log_event("player_lost", {"player": player_index, "reason": reason})
	_check_for_winner()


func _check_for_winner() -> void:
	if game_over:
		return
	var alive := living_players()
	var teams: Array[int] = []
	for index in alive:
		var team := get_player(index).team
		if team not in teams:
			teams.append(team)

	# The game ends when one team is left standing, however many players that
	# team has.
	if teams.size() <= 1:
		game_over = true
		winning_team = teams[0] if teams.size() == 1 else -1
		winner_index = alive[0] if alive.size() == 1 else -1
		awaiting = ""
		log_event("game_over", {"winner": winner_index, "team": winning_team,
				"survivors": alive})
		game_ended.emit(winner_index)
		_notify()


## --- Mana ----------------------------------------------------------------

## Every symbol an untapped permanent could produce right now.
func mana_source_symbols(card: CardInstance) -> Array[String]:
	var out: Array[String] = []
	for ability in card.data.abilities_of_kind("mana"):
		var a := ability as Dictionary
		var ability_cost := a.get("cost", {}) as Dictionary
		if bool(ability_cost.get("tap", true)) and not card.can_tap_for_cost():
			continue
		for sym in a.get("produces", []) as Array:
			if str(sym) not in out:
				out.append(str(sym))
	return out


## Untapped permanents that can still produce mana, as
## [{"uid": n, "symbols": [...]}].
func available_mana_sources(player_index: int) -> Array:
	var out: Array = []
	for uid in get_player(player_index).battlefield:
		var c := get_card(uid)
		if c == null or c.tapped:
			continue
		var symbols := mana_source_symbols(c)
		if not symbols.is_empty():
			out.append({"uid": uid, "symbols": symbols})
	return out


## Builds the combined list of payment options: mana already floating in the
## pool first, then untapped sources.
func _payment_options(player_index: int) -> Array:
	var options: Array = []
	var pool := get_player(player_index).mana_pool
	for sym in GameEnums.MANA_SYMBOLS:
		for _i in pool.get_amount(sym):
			options.append({"uid": -1, "symbols": [sym] as Array})
	options.append_array(available_mana_sources(player_index))
	return options


func can_pay_cost(player_index: int, cost: Mana.Cost, x_value: int = 0) -> bool:
	if cost.total_required(x_value) == 0:
		return true
	var options := _payment_options(player_index)
	var symbol_lists: Array = []
	for o in options:
		symbol_lists.append((o as Dictionary)["symbols"])
	return not Mana.plan_payment(symbol_lists, cost, x_value).is_empty()


## The largest X this player could pay for, given a base cost.
func max_affordable_x(player_index: int, cost: Mana.Cost) -> int:
	if cost.x_count == 0:
		return 0
	var budget := _payment_options(player_index).size()
	var fixed := cost.mana_value(0)
	if budget <= fixed:
		return 0
	return int(float(budget - fixed) / float(cost.x_count))


## Taps whatever is needed and spends the cost. Returns false and changes
## nothing when it cannot be paid.
func pay_cost(player_index: int, cost: Mana.Cost, x_value: int = 0) -> bool:
	if cost.total_required(x_value) == 0:
		return true
	var options := _payment_options(player_index)
	var symbol_lists: Array = []
	for o in options:
		symbol_lists.append((o as Dictionary)["symbols"])

	var plan := Mana.plan_payment(symbol_lists, cost, x_value)
	if plan.is_empty():
		return false

	var pool := get_player(player_index).mana_pool
	for entry_variant in plan:
		var entry := entry_variant as Dictionary
		var option := options[int(entry["index"])] as Dictionary
		var uid := int(option["uid"])
		if uid == -1:
			continue  # Already floating in the pool.
		var source := get_card(uid)
		if source == null:
			return false
		source.tapped = true
		pool.add(str(entry["symbol"]), 1)
		log_event("tap_for_mana", {"uid": uid, "symbol": str(entry["symbol"])})

	if not pool.pay(cost, x_value):
		return false
	log_event("paid", {"player": player_index, "cost": str(cost), "x": x_value})
	return true


## --- Legal actions -------------------------------------------------------

## Actions available while [param player_index] holds priority. Attack and
## block declarations are not listed here: they are built from
## [method possible_attackers] and [method possible_blocks], because the
## number of combinations makes enumerating them pointless.
func get_legal_actions(player_index: int) -> Array[GameAction]:
	var out: Array[GameAction] = []
	if game_over:
		return out

	if awaiting == "mulligan" and awaiting_index == player_index:
		out.append(GameAction.keep_hand(player_index))
		if get_player(player_index).mulligans < 3:
			out.append(GameAction.mulligan(player_index))
		return out

	if awaiting != "priority" or priority_player_index != player_index:
		return out

	out.append(GameAction.pass_priority(player_index))

	var p := get_player(player_index)
	var sorcery_speed := can_act_at_sorcery_speed(player_index)

	for uid in p.hand:
		var card := get_card(uid)
		if card == null:
			continue
		if card.data.is_land():
			if sorcery_speed and p.can_play_land():
				var a := GameAction.play_land(player_index, uid)
				a.description = "Play %s" % card.data.name
				out.append(a)
			continue
		if not _timing_allows(card.data, sorcery_speed):
			continue
		out.append_array(_cast_actions(player_index, card))

	for uid in p.battlefield:
		var card := get_card(uid)
		if card == null:
			continue
		out.append_array(_activation_actions(player_index, card, sorcery_speed))

	# Riding the current is a sorcery-speed action, so blockers are declared
	# against a board the attacker could already see.
	if sorcery_speed:
		var moves := possible_depth_moves(player_index)
		for uid in moves:
			var card := get_card(int(uid))
			for delta in moves[uid] as Array:
				var move := GameAction.move_depth(player_index, int(uid), int(delta))
				var band := int(card.depth) + int(delta)
				move.description = "%s -> %s" % [
					card.display_name(), GameEnums.depth_name(band as GameEnums.Depth)]
				out.append(move)

	return out


## Instants can be cast any time you hold priority; everything else needs a
## main phase with an empty stack.
func _timing_allows(data: CardData, sorcery_speed: bool) -> bool:
	if data.is_instant_speed():
		return true
	if data.has_keyword("Flash"):
		return true
	return sorcery_speed


## Additional Salvage cost printed on a card, e.g. "salvage": 2.
func _salvage_cost_of(data: CardData) -> int:
	return data.salvage_cost


func _cast_actions(player_index: int, card: CardInstance) -> Array[GameAction]:
	var out: Array[GameAction] = []
	var salvage_cost := _salvage_cost_of(card.data)
	if salvage_cost > 0 and not can_salvage(salvage_cost):
		return out
	var cost := _effective_cost(card, player_index)

	var x_values: Array[int] = [0]
	if cost.x_count > 0:
		var max_x := max_affordable_x(player_index, cost)
		x_values = []
		for x in range(1, max_x + 1):
			x_values.append(x)
		if x_values.is_empty():
			return out

	for x in x_values:
		if not can_pay_cost(player_index, cost, x):
			continue
		var specs := _spell_target_specs(card)
		for targets in _target_combinations(specs, player_index, card):
			var a := GameAction.cast_spell(player_index, card.uid, targets, x)
			a.description = _describe_cast(card, targets, x)
			out.append(a)
	return out


func _spell_target_specs(card: CardInstance) -> Array:
	var spell_abilities := card.data.abilities_of_kind("spell")
	if spell_abilities.is_empty():
		return []
	return (spell_abilities[0] as Dictionary).get("targets", []) as Array


## Enumerates target choices, expanding the first slot fully and choosing the
## rest automatically so the list stays small enough for a UI and an AI.
func _target_combinations(specs: Array, player_index: int, source: CardInstance) -> Array:
	if specs.is_empty():
		return [[]]

	var first_spec := specs[0] as Dictionary
	var first_options := Targeting.legal_targets(self, first_spec, player_index, source)
	if first_options.is_empty():
		if bool(first_spec.get("optional", false)):
			first_options = [{}]
		else:
			return []  # A spell with no legal target cannot be cast.

	var out: Array = []
	for opt in first_options:
		var combo: Array = [opt]
		var ok := true
		for i in range(1, specs.size()):
			var spec := specs[i] as Dictionary
			var options := Targeting.legal_targets(self, spec, player_index, source)
			# Do not reuse the same object for two slots.
			var filtered: Array = []
			for o in options:
				if not _same_target(o as Dictionary, opt as Dictionary):
					filtered.append(o)
			if filtered.is_empty():
				if bool(spec.get("optional", false)):
					combo.append({})
					continue
				ok = false
				break
			combo.append(_best_target(filtered, spec, player_index))
		if ok:
			out.append(combo)
	return out


func _same_target(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if str(a.get("type", "")) != str(b.get("type", "")):
		return false
	if str(a.get("type", "")) == "player":
		return int(a.get("index", -1)) == int(b.get("index", -2))
	return int(a.get("uid", -1)) == int(b.get("uid", -2))


func _activation_actions(player_index: int, card: CardInstance, sorcery_speed: bool) -> Array[GameAction]:
	var out: Array[GameAction] = []
	if card.controller_index != player_index:
		return out

	var abilities := card.data.abilities
	for i in abilities.size():
		var a := abilities[i] as Dictionary
		var kind := str(a.get("kind", ""))
		if kind == "champion":
			if _can_use_champion_ability(card, a):
				var specs_c := a.get("targets", []) as Array
				for targets in _target_combinations(specs_c, player_index, card):
					var champ_action := GameAction.activate(player_index, card.uid, i, targets, 0)
					var delta := int(a.get("cost", 0))
					champ_action.description = "%s [%s%d]: %s" % [
						card.display_name(), "+" if delta >= 0 else "", delta,
						str(a.get("text", "ability")),
					]
					out.append(champ_action)
			continue
		if kind != "activated":
			continue
		if str(a.get("timing", "instant")) == "sorcery" and not sorcery_speed:
			continue
		if not _can_pay_activation(player_index, card, a):
			continue
		var specs := a.get("targets", []) as Array
		for targets in _target_combinations(specs, player_index, card):
			var action := GameAction.activate(player_index, card.uid, i, targets, 0)
			action.description = "%s: %s" % [card.data.name, str(a.get("text", "ability"))]
			out.append(action)
	return out


## A Champion ability costs Fathom, is sorcery speed, and only one may be
## used per turn per Champion.
func _can_use_champion_ability(card: CardInstance, ability: Dictionary) -> bool:
	if not card.is_champion() or card.zone != GameEnums.Zone.BATTLEFIELD:
		return false
	if card.champion_ability_used:
		return false
	if not can_act_at_sorcery_speed(card.controller_index):
		return false
	var delta := int(ability.get("cost", 0))
	if delta < 0 and card.fathom_count() < -delta:
		return false
	return true


func _can_pay_activation(player_index: int, card: CardInstance, ability: Dictionary) -> bool:
	var ability_cost := ability.get("cost", {}) as Dictionary
	if bool(ability_cost.get("tap", false)) and not card.can_tap_for_cost():
		return false
	if bool(ability_cost.get("sacrifice", false)) and card.zone != GameEnums.Zone.BATTLEFIELD:
		return false
	var mana_text := str(ability_cost.get("mana", "0"))
	return can_pay_cost(player_index, Mana.Cost.parse(mana_text))


## Cost after any cost reduction effects, never below the colored part.
func _effective_cost(card: CardInstance, player_index: int) -> Mana.Cost:
	var reduction := ContinuousEffects.cost_reduction_for(self, card, player_index)
	if reduction <= 0:
		return card.data.cost
	var cost := card.data.cost.duplicate_cost()
	cost.generic = max(0, cost.generic - reduction)
	return cost


func _describe_cast(card: CardInstance, targets: Array, x: int) -> String:
	var text := "Cast %s" % card.data.name
	if x > 0:
		text += " (X=%d)" % x
	if not targets.is_empty():
		var names: Array[String] = []
		for t in targets:
			names.append(describe_target(t as Dictionary))
		text += " -> " + ", ".join(names)
	return text


func describe_target(target: Dictionary) -> String:
	if target.is_empty():
		return "nothing"
	if str(target.get("type", "")) == "player":
		var p := get_player(int(target.get("index", 0)))
		return p.name if p != null else "player"
	var c := get_card(int(target.get("uid", 0)))
	return c.display_name() if c != null else "?"


## --- Combat declaration helpers ------------------------------------------

func _possible_attackers(player_index: int) -> Array[int]:
	var out: Array[int] = []
	for uid in get_player(player_index).battlefield:
		var c := get_card(uid)
		if c != null and c.can_attack():
			out.append(uid)
	return out

func possible_attackers(player_index: int) -> Array[int]:
	return _possible_attackers(player_index)

func _attacking_uids() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		for uid in p.battlefield:
			var c := get_card(uid)
			if c != null and c.attacking:
				out.append(uid)
	return out

func attacking_uids() -> Array[int]:
	return _attacking_uids()

## For each creature the defender could block with, which attackers it may be
## assigned to: {blocker_uid: [attacker_uid, ...]}.
## For each creature this player could block with, the attackers aimed at
## them it may be assigned to: {blocker_uid: [attacker_uid, ...]}.
func possible_blocks(player_index: int) -> Dictionary:
	var out: Dictionary = {}
	var attackers: Array[int] = []
	for uid in _attacking_uids():
		var a := get_card(uid)
		if a != null and a.attack_target == player_index:
			attackers.append(uid)
	if attackers.is_empty():
		return out
	for uid in get_player(player_index).battlefield:
		var blocker := get_card(uid)
		if blocker == null or not blocker.can_block():
			continue
		var options: Array[int] = []
		for attacker_uid in attackers:
			var attacker := get_card(attacker_uid)
			if attacker != null and Combat.can_block_attacker(blocker, attacker):
				options.append(attacker_uid)
		if not options.is_empty():
			out[uid] = options
	return out


## --- Performing actions --------------------------------------------------

## Applies an action. Returns false when the action is not legal right now,
## in which case nothing changes.
func perform(action: GameAction) -> bool:
	if game_over:
		return false

	match action.kind:
		GameAction.Kind.MULLIGAN, GameAction.Kind.KEEP_HAND:
			return _perform_mulligan_decision(action)
		GameAction.Kind.DECLARE_ATTACKERS:
			return _perform_declare_attackers(action)
		GameAction.Kind.DECLARE_BLOCKERS:
			return _perform_declare_blockers(action)
		GameAction.Kind.CONCEDE:
			_player_loses(action.player_index, "conceded")
			return true

	if awaiting != "priority" or priority_player_index != action.player_index:
		return false

	match action.kind:
		GameAction.Kind.PASS_PRIORITY:
			_pass_priority()
			return true
		GameAction.Kind.PLAY_LAND:
			return _perform_play_land(action)
		GameAction.Kind.CAST_SPELL:
			return _perform_cast(action)
		GameAction.Kind.ACTIVATE_ABILITY:
			return _perform_activate(action)
		GameAction.Kind.MOVE_DEPTH:
			return _perform_move_depth(action)

	return false


func _perform_mulligan_decision(action: GameAction) -> bool:
	if awaiting != "mulligan" or awaiting_index != action.player_index:
		return false
	var p := get_player(action.player_index)

	if action.kind == GameAction.Kind.MULLIGAN:
		if p.mulligans >= 3:
			return false
		for uid in p.hand.duplicate():
			var c := get_card(uid)
			c.zone = GameEnums.Zone.LIBRARY
			p.library.append(uid)
		p.hand.clear()
		_shuffle_library(p.index)
		p.mulligans += 1
		_draw_without_loss(p.index, rules.starting_hand)
		log_event("mulligan", {"player": p.index, "count": p.mulligans})
		_notify()
		return true

	# Keeping: a London mulligan puts one card per mulligan on the bottom.
	for _i in p.mulligans:
		if p.hand.is_empty():
			break
		var worst := _worst_card_in_hand(p)
		p.hand.erase(worst)
		get_card(worst).zone = GameEnums.Zone.LIBRARY
		p.library.append(worst)
	log_event("keep_hand", {"player": p.index, "mulligans": p.mulligans})
	_mulligan_queue.erase(p.index)
	_begin_mulligan_decision()
	return true


## The card the engine bottoms on a kept mulligan: the most expensive spell,
## or a land when the hand is flooded.
func _worst_card_in_hand(p: PlayerState) -> int:
	var lands := 0
	for uid in p.hand:
		if get_card(uid).data.is_land():
			lands += 1
	var worst: int = p.hand[0]
	var worst_score := -1
	for uid in p.hand:
		var c := get_card(uid)
		var score := c.data.mana_value()
		if c.data.is_land():
			score = 8 if lands > 3 else -1
		if score > worst_score:
			worst_score = score
			worst = uid
	return worst


func _perform_play_land(action: GameAction) -> bool:
	var p := get_player(action.player_index)
	var card := get_card(action.card_uid)
	if card == null or card.zone != GameEnums.Zone.HAND or not card.data.is_land():
		return false
	if not can_act_at_sorcery_speed(action.player_index) or not p.can_play_land():
		return false

	p.lands_played_this_turn += 1
	var enters_tapped := _enters_tapped(card)
	put_on_battlefield(card, action.player_index, enters_tapped)
	log_event("land_played", {"player": action.player_index, "uid": card.uid,
			"name": card.data.name})
	check_state_based_actions()
	_retain_priority()
	return true


func _enters_tapped(card: CardInstance) -> bool:
	for ability in card.data.abilities_of_kind("static"):
		var eff := (ability as Dictionary).get("effect", {}) as Dictionary
		if str(eff.get("type", "")) == "enters_tapped":
			return true
	return false


func _perform_cast(action: GameAction) -> bool:
	var p := get_player(action.player_index)
	var card := get_card(action.card_uid)
	if card == null or card.zone != GameEnums.Zone.HAND:
		return false
	if card.data.is_land():
		return false

	var sorcery_speed := can_act_at_sorcery_speed(action.player_index)
	if not _timing_allows(card.data, sorcery_speed):
		return false

	var specs := _spell_target_specs(card)
	if not _targets_are_legal(specs, action.targets, action.player_index, card):
		return false

	var salvage_cost := _salvage_cost_of(card.data)
	if salvage_cost > 0 and not can_salvage(salvage_cost):
		return false

	var cost := _effective_cost(card, action.player_index)
	if not pay_cost(action.player_index, cost, action.x_value):
		return false
	if salvage_cost > 0:
		pay_salvage(action.player_index, salvage_cost)

	spells_cast_this_turn[action.player_index] = \
		int(spells_cast_this_turn.get(action.player_index, 0)) + 1
	refresh_continuous()

	card.targets = action.targets.duplicate(true)
	card.chosen_x = action.x_value
	card.stack_kind = "spell"
	card.controller_index = action.player_index
	move_to_zone(card, GameEnums.Zone.STACK, "cast")
	log_event("cast", {"player": action.player_index, "uid": card.uid,
			"name": card.data.name, "x": action.x_value})
	emit_trigger_event("spell_cast", {"uid": card.uid, "player": action.player_index})

	_retain_priority()
	return true


func _perform_activate(action: GameAction) -> bool:
	var card := get_card(action.card_uid)
	if card == null or card.controller_index != action.player_index:
		return false
	if action.ability_index < 0 or action.ability_index >= card.data.abilities.size():
		return false
	var ability := card.data.abilities[action.ability_index] as Dictionary
	var ability_kind := str(ability.get("kind", ""))

	if ability_kind == "champion":
		if not _can_use_champion_ability(card, ability):
			return false
		var champ_specs := ability.get("targets", []) as Array
		if not _targets_are_legal(champ_specs, action.targets, action.player_index, card):
			return false
		card.add_counters(GameEnums.COUNTER_FATHOM, int(ability.get("cost", 0)))
		card.champion_ability_used = true
		log_event("champion_ability", {"uid": card.uid, "name": card.data.name,
				"cost": int(ability.get("cost", 0)), "fathom": card.fathom_count()})
		_push_ability(card, ability, action.targets, 0, "champion")
		_retain_priority()
		return true

	if ability_kind != "activated":
		return false

	var sorcery_speed := can_act_at_sorcery_speed(action.player_index)
	if str(ability.get("timing", "instant")) == "sorcery" and not sorcery_speed:
		return false

	var specs := ability.get("targets", []) as Array
	if not _targets_are_legal(specs, action.targets, action.player_index, card):
		return false
	if not _can_pay_activation(action.player_index, card, ability):
		return false

	# Pay the cost: mana first, so a failed payment leaves the permanent
	# untapped and unsacrificed.
	var ability_cost := ability.get("cost", {}) as Dictionary
	if not pay_cost(action.player_index, Mana.Cost.parse(str(ability_cost.get("mana", "0")))):
		return false
	if bool(ability_cost.get("tap", false)):
		card.tapped = true
	if bool(ability_cost.get("discard", false)):
		discard_cards(action.player_index, 1, "choice")
	if bool(ability_cost.get("sacrifice", false)):
		sacrifice_permanent(card)

	log_event("activate", {"player": action.player_index, "uid": card.uid,
			"name": card.data.name})
	_push_ability(card, ability, action.targets, 0, "activated")
	_retain_priority()
	return true


func _perform_move_depth(action: GameAction) -> bool:
	if not can_act_at_sorcery_speed(action.player_index):
		return false
	var card := get_card(action.card_uid)
	if card == null or card.controller_index != action.player_index:
		return false
	if not card.is_creature() or not card.can_change_depth():
		return false

	var p := get_player(action.player_index)
	var is_diver := card.has_keyword(GameEnums.KW_DIVER)
	if not is_diver and not p.can_move_depth():
		return false
	var reach := 2 if is_diver else 1
	if action.depth_delta == 0 or abs(action.depth_delta) > reach:
		return false

	if not set_depth(card, int(card.depth) + action.depth_delta):
		return false
	if not is_diver:
		p.depth_moves_this_turn += 1
	_retain_priority()
	return true


func _targets_are_legal(specs: Array, targets: Array, player_index: int, source: CardInstance) -> bool:
	if specs.is_empty():
		return true
	if targets.size() < specs.size():
		return false
	for i in specs.size():
		var spec := specs[i] as Dictionary
		var t := targets[i] as Dictionary
		if t.is_empty():
			if bool(spec.get("optional", false)):
				continue
			return false
		if not Targeting.is_still_legal(self, spec, t, player_index, source):
			return false
	return true


func _perform_declare_attackers(action: GameAction) -> bool:
	if awaiting != "attackers" or awaiting_index != action.player_index:
		return false
	var legal := _possible_attackers(action.player_index)
	var enemies := opponents_of(action.player_index)
	for uid_key in action.attacks:
		if int(uid_key) not in legal:
			return false
		# You cannot attack yourself or an ally.
		if int(action.attacks[uid_key]) not in enemies:
			return false

	Combat.declare_attackers(self, action.attacks, action.champion_attacks)
	check_state_based_actions()
	if game_over:
		return true
	if action.attacks.is_empty():
		_skip_to_step(GameEnums.Step.END_COMBAT)
		return true
	_open_priority(active_player_index)
	return true


func _perform_declare_blockers(action: GameAction) -> bool:
	if awaiting != "blockers" or awaiting_index != action.player_index:
		return false
	var error := Combat.validate_blocks(self, action.blocks, action.player_index)
	if not error.is_empty():
		log_event("illegal_block", {"reason": error})
		return false
	Combat.declare_blockers(self, action.blocks)
	check_state_based_actions()
	if game_over:
		return true
	_blocker_queue.erase(action.player_index)
	_ask_next_defender()
	return true


## Hands the block declaration to the next attacked player, or moves on to
## damage when everyone has declared.
func _ask_next_defender() -> void:
	while not _blocker_queue.is_empty():
		var who: int = _blocker_queue[0]
		if get_player(who).has_lost:
			_blocker_queue.pop_front()
			continue
		awaiting = "blockers"
		awaiting_index = who
		_notify()
		return
	_open_priority(active_player_index)


## --- Debug ---------------------------------------------------------------

func describe_state() -> String:
	var lines: Array[String] = []
	lines.append("Turn %d, %s, %s, active: %s, awaiting: %s (p%d)" % [
		turn_number, GameEnums.step_name(current_step), GameEnums.tide_name(tide),
		players[active_player_index].name, awaiting, awaiting_index,
	])
	for p in players:
		var bands: Array[String] = []
		for band in GameEnums.DEPTH_ORDER:
			var here: Array[String] = []
			for uid in p.battlefield:
				var c := get_card(uid)
				if c == null:
					continue
				if c.is_creature() and c.depth != band:
					continue
				if not c.is_creature() and band != GameEnums.Depth.MIDWATER:
					continue
				var tag := c.display_name()
				if c.is_creature():
					tag += " %s" % c.power_toughness_text()
				if c.tapped:
					tag += "(T)"
				here.append(tag)
			if not here.is_empty():
				bands.append("%s[%s]" % [GameEnums.depth_name(band), ", ".join(here)])
		lines.append("  %s: %d life | hand %d | lib %d | %s" % [
			p.name, p.life, p.hand.size(), p.library.size(), " ".join(bands),
		])
	lines.append("  wreck: %d" % wreck.size())
	if not stack.is_empty():
		var names: Array[String] = []
		for uid in stack:
			names.append(get_card(uid).data.name)
		lines.append("  stack: " + " | ".join(names))
	return "\n".join(lines)
