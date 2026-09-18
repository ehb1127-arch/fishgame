## The computer opponent.
##
## The AI only ever talks to the engine through legal actions, the same way
## the UI does, so it can never do anything a player could not. It is a
## scoring heuristic rather than a search: fast enough to answer instantly on
## a phone, and good enough to punish a bad attack.
##
## What it understands beyond ordinary card play:
## - depth bands, and that an attacker in an empty band is unblockable
## - the tide, and that a band it is about to favour is worth moving into
## - the wreck, and that killing things hands the opponent Salvage fuel
class_name AIPlayer
extends RefCounted

enum Skill {
	EASY,
	NORMAL,
	HARD,
	BOSS,
}

var skill: Skill = Skill.NORMAL
var player_index: int = 1
var rng := RandomNumberGenerator.new()


static func create(index: int, level: Skill = Skill.NORMAL, seed_value: int = 0) -> AIPlayer:
	var ai := AIPlayer.new()
	ai.player_index = index
	ai.skill = level
	ai.rng.seed = seed_value if seed_value != 0 else randi()
	return ai


static func skill_from_name(name: String) -> Skill:
	match name.to_lower():
		"easy": return Skill.EASY
		"hard": return Skill.HARD
		"boss": return Skill.BOSS
		_: return Skill.NORMAL


## --- Entry point ---------------------------------------------------------

## Produces the action the engine is currently waiting on from this player,
## or null when it is not this player's decision.
func decide(game) -> GameAction:
	if game.is_over() or game.awaiting_player() != player_index:
		return null
	match game.awaiting:
		"mulligan":
			return _decide_mulligan(game)
		"attackers":
			return _decide_attackers(game)
		"blockers":
			return _decide_blocks(game)
		"priority":
			return _decide_priority(game)
	return null


## --- Mulligan ------------------------------------------------------------

func _decide_mulligan(game) -> GameAction:
	var hand: Array[int] = game.get_player(player_index).hand
	var lands := 0
	for uid in hand:
		if game.get_card(uid).data.is_land():
			lands += 1
	# Two to five lands in seven is keepable; anything else is a gamble.
	var keepable := lands >= 2 and lands <= 5
	if keepable or game.get_player(player_index).mulligans >= 2:
		return GameAction.keep_hand(player_index)
	return GameAction.mulligan(player_index)


## --- Priority ------------------------------------------------------------

func _decide_priority(game) -> GameAction:
	var actions: Array[GameAction] = game.get_legal_actions(player_index)
	if actions.is_empty():
		return GameAction.pass_priority(player_index)

	# On the opponent's turn, only act when holding priority is pointless:
	# respond to something on the stack, or hold instants for combat.
	var best: GameAction = null
	var best_score := 0.0
	for action in actions:
		var score := _score_action(game, action)
		if score > best_score:
			best_score = score
			best = action

	if best == null or best_score <= 0.0:
		return GameAction.pass_priority(player_index)

	# Weaker opponents sometimes take the second-best line.
	if skill == Skill.EASY and rng.randf() < 0.35:
		var pool: Array[GameAction] = []
		for action in actions:
			if action.kind != GameAction.Kind.PASS_PRIORITY and _score_action(game, action) > 0.0:
				pool.append(action)
		if not pool.is_empty():
			return pool[rng.randi_range(0, pool.size() - 1)]

	return best


func _score_action(game, action: GameAction) -> float:
	match action.kind:
		GameAction.Kind.PASS_PRIORITY:
			return 0.0
		GameAction.Kind.PLAY_LAND:
			return 1000.0  # Always play a land first.
		GameAction.Kind.CAST_SPELL:
			return _score_cast(game, action)
		GameAction.Kind.ACTIVATE_ABILITY:
			return _score_activation(game, action)
		GameAction.Kind.MOVE_DEPTH:
			return _score_depth_move(game, action)
	return 0.0


func _score_cast(game, action: GameAction) -> float:
	var card: CardInstance = game.get_card(action.card_uid)
	if card == null:
		return 0.0
	var data := card.data
	var sorcery_speed: bool = game.can_act_at_sorcery_speed(player_index)

	# Creatures and permanents: play them on your own turn, biggest first.
	if data.is_permanent():
		if not sorcery_speed:
			return 0.0
		var body := float(data.power + data.toughness)
		var score := 40.0 + body * 4.0
		for kw in data.keywords:
			score += 6.0
		if data.is_champion():
			score += 60.0
		return score

	# Removal and burn: worth it when it kills something that matters.
	var value := _spell_value(game, action, data)
	if value <= 0.0:
		return 0.0

	# Instants are held until the opponent's turn unless they are about to be
	# wasted, which is most of what separates HARD from NORMAL.
	if data.is_instant_speed() and skill >= Skill.HARD:
		var opponent_turn: bool = game.active_player_index != player_index
		var in_combat: bool = game.current_step == GameEnums.Step.DECLARE_BLOCKERS \
			or game.current_step == GameEnums.Step.DECLARE_ATTACKERS
		if not opponent_turn and not in_combat:
			return value * 0.35
	return value


## How much a non-permanent spell is worth right now.
func _spell_value(game, action: GameAction, data: CardData) -> float:
	var score := 20.0

	for target in action.targets:
		var t := target as Dictionary
		if t.is_empty():
			continue
		if str(t.get("type", "")) == "player":
			var pi := int(t.get("index", -1))
			# Burning the opponent is good; burning yourself is not.
			score += 25.0 if pi != player_index else -80.0
			continue
		var c: CardInstance = game.get_card(int(t.get("uid", 0)))
		if c == null:
			continue
		var threat := float(c.eff_power * 2 + c.eff_toughness + c.data.mana_value())
		if c.controller_index == player_index:
			# A buff on your own creature, or a mistake.
			score += threat * 0.4
		else:
			score += threat * 1.2
			# Killing something fills the shared wreck, which the opponent can
			# spend. Discount removal slightly when they are a Salvage deck.
			if game.wreck_size() >= 8:
				score -= 4.0

	# Board wipes and mass effects are judged by who loses more.
	for ability in data.abilities_of_kind("spell"):
		for effect in (ability as Dictionary).get("effects", []) as Array:
			score += _score_mass_effect(game, effect as Dictionary)
	return score


func _score_mass_effect(game, effect: Dictionary) -> float:
	var selector: Variant = effect.get("to", "")
	if not (selector is String):
		return 0.0
	var op := str(effect.get("op", ""))
	var mine := 0
	var theirs := 0
	for p in game.players:
		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c == null or not c.is_creature():
				continue
			if c.controller_index == player_index:
				mine += 1
			else:
				theirs += 1

	match str(selector):
		"all_creatures":
			if op in ["destroy", "damage", "pump"]:
				return float(theirs - mine) * 12.0
		"creatures_opponent_controls":
			return float(theirs) * 14.0
		"creatures_you_control":
			return float(mine) * (10.0 if op == "pump" else -14.0)
	return 0.0


func _score_activation(game, action: GameAction) -> float:
	var card: CardInstance = game.get_card(action.card_uid)
	if card == null:
		return 0.0
	# Champion abilities are almost always worth using, since they are free
	# and refresh every turn.
	if card.is_champion():
		return 500.0 + float(action.ability_index)
	return 15.0


## --- Depth movement ------------------------------------------------------

## Moving is the decision that separates this game from an ordinary card
## game, so it gets a real evaluation: is the band I am moving into empty of
## blockers, and is the tide about to favour it?
func _score_depth_move(game, action: GameAction) -> float:
	if skill == Skill.EASY:
		return 0.0  # The easy opponent never rides the current.
	var card: CardInstance = game.get_card(action.card_uid)
	if card == null or not card.is_creature():
		return 0.0

	var from_band := int(card.depth)
	var to_band := clampi(from_band + action.depth_delta, 0, 2)
	if to_band == from_band:
		return 0.0

	var defenders_now := _enemy_blockers_in(game, from_band)
	var defenders_after := _enemy_blockers_in(game, to_band)

	var score := 0.0
	# Walking into an empty band means an unblockable attacker next combat.
	if defenders_after == 0 and defenders_now > 0:
		score += 30.0 + float(card.eff_power) * 4.0
	elif defenders_after < defenders_now:
		score += 10.0

	# The tide lifts one band each round; be standing in it when it turns.
	var next_tide: GameEnums.Tide = GameEnums.tide_for_turn(game.turn_number + 1)
	if to_band == GameEnums.favoured_band(next_tide):
		score += 8.0
	if from_band == GameEnums.favoured_band(game.tide):
		score -= 6.0  # Do not step out of a band already buffing you.

	# Pressure creatures belong in the Abyss and nowhere else.
	if card.has_keyword(GameEnums.KW_PRESSURE):
		score += 18.0 if to_band == int(GameEnums.Depth.ABYSS) else -18.0

	# Swarm wants company.
	if card.has_keyword(GameEnums.KW_SWARM):
		score += float(_friendly_creatures_in(game, to_band)) * 5.0

	# When behind on board, move toward whatever is threatening you.
	if _is_behind(game) and defenders_after > 0:
		score += 6.0

	return score


func _enemy_blockers_in(game, band: int) -> int:
	var n := 0
	for index in game.opponents_of(player_index):
		for uid in game.get_player(index).battlefield:
			var c: CardInstance = game.get_card(uid)
			if c != null and c.is_creature() and int(c.depth) == band and c.can_block():
				n += 1
	return n


func _friendly_creatures_in(game, band: int) -> int:
	var n := 0
	for uid in game.get_player(player_index).battlefield:
		var c: CardInstance = game.get_card(uid)
		if c != null and c.is_creature() and int(c.depth) == band:
			n += 1
	return n


func _is_behind(game) -> bool:
	var mine := 0
	var theirs := 0
	for uid in game.get_player(player_index).battlefield:
		var c: CardInstance = game.get_card(uid)
		if c != null and c.is_creature():
			mine += c.eff_power + c.eff_toughness
	for index in game.opponents_of(player_index):
		for uid in game.get_player(index).battlefield:
			var c: CardInstance = game.get_card(uid)
			if c != null and c.is_creature():
				theirs += c.eff_power + c.eff_toughness
	return mine < theirs


## --- Attacking -----------------------------------------------------------

func _decide_attackers(game) -> GameAction:
	var candidates: Array[int] = game.possible_attackers(player_index)
	var enemies: Array[int] = game.opponents_of(player_index)
	if candidates.is_empty() or enemies.is_empty():
		return GameAction.declare_attackers(player_index, {})

	# Attack whoever is closest to dying.
	var defender: int = enemies[0]
	for index in enemies:
		if game.get_player(index).life < game.get_player(defender).life:
			defender = index

	var assignment := {}
	for uid in candidates:
		var attacker: CardInstance = game.get_card(uid)
		if attacker == null:
			continue
		if _should_attack(game, attacker, defender):
			assignment[uid] = defender
	return GameAction.declare_attackers(player_index, assignment)


func _should_attack(game, attacker: CardInstance, defender: int) -> bool:
	if attacker.eff_power <= 0:
		return false

	var blockers := _blockers_that_could_stop(game, attacker, defender)

	# Nothing in the band can block it: free damage.
	if blockers.is_empty():
		return true

	if skill == Skill.EASY:
		return rng.randf() < 0.7

	# Would the best available block kill it without dying?
	var worst_case_bad := false
	var any_good_trade := false
	for blocker in blockers:
		var kills_blocker := attacker.eff_power >= blocker.eff_toughness \
			or attacker.has_keyword(GameEnums.KW_VENOMOUS)
		var dies := blocker.eff_power >= attacker.eff_toughness \
			or blocker.has_keyword(GameEnums.KW_VENOMOUS)
		if attacker.has_keyword(GameEnums.KW_MOLT) and not attacker.molt_spent:
			dies = false
		if attacker.has_keyword(GameEnums.KW_INK):
			dies = false  # Its blockers deal no damage back.
		if dies and not kills_blocker:
			worst_case_bad = true
		if kills_blocker and not dies:
			any_good_trade = true

	# Schooling needs two blockers, so a lone defender cannot stop it.
	if attacker.has_keyword(GameEnums.KW_SCHOOLING) and blockers.size() < 2:
		return true

	if any_good_trade:
		return true
	if worst_case_bad:
		# Race anyway when the opponent is nearly dead.
		return game.get_player(defender).life <= attacker.eff_power * 2
	return true


func _blockers_that_could_stop(game, attacker: CardInstance, defender: int) -> Array[CardInstance]:
	var out: Array[CardInstance] = []
	for uid in game.get_player(defender).battlefield:
		var c: CardInstance = game.get_card(uid)
		if c == null or not c.can_block():
			continue
		var gap: int = abs(int(c.depth) - int(attacker.depth))
		if gap == 0 or (gap == 1 and c.has_keyword(GameEnums.KW_AMPHIBIOUS)):
			out.append(c)
	return out


## --- Blocking ------------------------------------------------------------

func _decide_blocks(game) -> GameAction:
	var options: Dictionary = game.possible_blocks(player_index)
	var assignment := {}
	if options.is_empty():
		return GameAction.declare_blockers(player_index, assignment)

	var life: int = game.get_player(player_index).life
	var incoming := 0
	for uid in game.attacking_uids():
		var a: CardInstance = game.get_card(uid)
		if a != null and a.attack_target == player_index:
			incoming += a.eff_power
	var must_block: bool = incoming >= life

	# Lure attackers have to be blocked if anything can, so handle them first.
	var claimed := {}
	for blocker_uid in options:
		for attacker_uid in options[blocker_uid] as Array:
			var attacker: CardInstance = game.get_card(int(attacker_uid))
			if attacker != null and attacker.has_keyword(GameEnums.KW_LURE) \
					and not claimed.has(attacker_uid):
				assignment[blocker_uid] = attacker_uid
				claimed[attacker_uid] = true
				break

	for blocker_uid in options:
		if assignment.has(blocker_uid):
			continue
		var blocker: CardInstance = game.get_card(int(blocker_uid))
		if blocker == null:
			continue
		var best_attacker := -1
		var best_score := 0.0
		for attacker_uid in options[blocker_uid] as Array:
			var attacker: CardInstance = game.get_card(int(attacker_uid))
			if attacker == null:
				continue
			# Schooling cannot be blocked by one creature; skip unless we can
			# gang up, which this simple assigner does not attempt.
			if attacker.has_keyword(GameEnums.KW_SCHOOLING):
				continue
			var score := _block_value(blocker, attacker, must_block)
			if score > best_score:
				best_score = score
				best_attacker = int(attacker_uid)
		if best_attacker >= 0:
			assignment[blocker_uid] = best_attacker

	return GameAction.declare_blockers(player_index, assignment)


func _block_value(blocker: CardInstance, attacker: CardInstance, must_block: bool) -> float:
	var kills_attacker := blocker.eff_power >= attacker.eff_toughness \
		or blocker.has_keyword(GameEnums.KW_VENOMOUS)
	var blocker_dies := attacker.eff_power >= blocker.eff_toughness \
		or attacker.has_keyword(GameEnums.KW_VENOMOUS)
	if attacker.has_keyword(GameEnums.KW_INK):
		kills_attacker = false  # The blocker deals no damage.
	if blocker.has_keyword(GameEnums.KW_MOLT) and not blocker.molt_spent:
		blocker_dies = false
	if blocker.has_keyword(GameEnums.KW_UNSINKABLE):
		blocker_dies = false

	var damage_stopped := float(attacker.eff_power)
	var score := damage_stopped * 2.0

	if kills_attacker and not blocker_dies:
		score += 40.0
	elif kills_attacker and blocker_dies:
		# An even trade is good when their creature is worth more.
		score += 15.0 + float(attacker.data.mana_value() - blocker.data.mana_value()) * 4.0
	elif blocker_dies:
		score -= 25.0
		if must_block:
			score += 60.0  # Chump block rather than lose.

	if must_block:
		score += damage_stopped * 3.0
	return score
