## Shared helpers for building games in a known state.
class_name TestHelpers
extends RefCounted

## A game between two decks with a fixed seed, past the mulligan step.
static func new_game(deck_a: String = "corsair_fleet", deck_b: String = "leviathan_brood",
		seed_value: int = 12345, rules: MatchRules = null) -> Game:
	var game := Game.new()
	game.setup(
		["A", "B"],
		[Cards.build_deck(deck_a), Cards.build_deck(deck_b)],
		seed_value,
		[false, false],
		rules if rules != null else MatchRules.standard()
	)
	# Both players keep, so play starts immediately.
	while game.awaiting == "mulligan":
		game.perform(GameAction.keep_hand(game.awaiting_player()))
	return game


## Puts a card straight onto the battlefield, skipping casting.
static func put_in_play(game: Game, card_id: String, controller: int,
		band: GameEnums.Depth = GameEnums.Depth.MIDWATER) -> CardInstance:
	var data: CardData = Cards.get_card(card_id)
	if data == null:
		return null
	var card := game.create_copy(data, controller)
	if card != null:
		card.is_token = false
		card.summoning_sick = false
		game.set_depth(card, int(band), true)
		game.refresh_continuous()
	return card


## Puts a card into a hand so it can be cast normally.
static func put_in_hand(game: Game, card_id: String, owner: int) -> CardInstance:
	var data: CardData = Cards.get_card(card_id)
	if data == null:
		return null
	var card := CardInstance.create(game._next_uid, data, owner)
	game._next_uid += 1
	game.cards[card.uid] = card
	card.zone = GameEnums.Zone.HAND
	game.get_player(owner).hand.append(card.uid)
	return card


## Gives a player enough untapped basics to cast anything in the test.
static func give_lands(game: Game, player_index: int, land_id: String, count: int) -> void:
	for _i in count:
		var land := put_in_play(game, land_id, player_index)
		if land != null:
			land.tapped = false


## Advances to a step in the active player's turn by passing priority.
static func advance_to_step(game: Game, step: GameEnums.Step, guard: int = 400) -> bool:
	var steps := 0
	while game.current_step != step and not game.is_over() and steps < guard:
		steps += 1
		match game.awaiting:
			"priority":
				game.perform(GameAction.pass_priority(game.awaiting_player()))
			"attackers":
				game.perform(GameAction.declare_attackers(game.awaiting_player(), {}))
			"blockers":
				game.perform(GameAction.declare_blockers(game.awaiting_player(), {}))
			"mulligan":
				game.perform(GameAction.keep_hand(game.awaiting_player()))
			_:
				return false
	return game.current_step == step


## Passes priority until the stack is empty again.
static func resolve_stack(game: Game, guard: int = 40) -> void:
	var steps := 0
	while not game.stack.is_empty() and not game.is_over() and steps < guard:
		steps += 1
		if game.awaiting == "priority":
			game.perform(GameAction.pass_priority(game.awaiting_player()))
		else:
			return
