## Attack and block declaration, and combat damage.
##
## Damage is dealt in up to two steps: a first-strike step when any creature in
## combat has first or double strike, then the regular step.
class_name Combat
extends RefCounted


## --- Blocking legality ---------------------------------------------------

## Can [param blocker] legally block [param attacker], ignoring how many other
## creatures are already blocking it?
##
## This is the heart of the depth system: you block what is at your depth.
## Amphibious creatures reach one band either way.
static func can_block_attacker(blocker: CardInstance, attacker: CardInstance) -> bool:
	if not blocker.can_block() or not attacker.attacking:
		return false
	var gap: int = abs(int(blocker.depth) - int(attacker.depth))
	if gap == 0:
		return true
	if gap == 1 and blocker.has_keyword(GameEnums.KW_AMPHIBIOUS):
		return true
	return false


## Validates a whole block assignment (blocker uid -> attacker uid).
## Returns an empty string when legal, or the reason it is not.
static func validate_blocks(game, blocks: Dictionary, defender_index: int) -> String:
	var per_attacker: Dictionary = {}
	for blocker_uid in blocks:
		var blocker: CardInstance = game.get_card(int(blocker_uid))
		var attacker: CardInstance = game.get_card(int(blocks[blocker_uid]))
		if blocker == null or attacker == null:
			return "Unknown creature in block assignment"
		if blocker.controller_index != defender_index:
			return "%s is not yours to block with" % blocker.display_name()
		if blocker.zone != GameEnums.Zone.BATTLEFIELD:
			return "%s is not on the battlefield" % blocker.display_name()
		if not can_block_attacker(blocker, attacker):
			return "%s cannot block %s" % [blocker.display_name(), attacker.display_name()]
		per_attacker[attacker.uid] = int(per_attacker.get(attacker.uid, 0)) + 1

	# Schooling needs two or more blockers or none at all.
	for attacker_uid in per_attacker:
		var attacker: CardInstance = game.get_card(int(attacker_uid))
		if attacker != null and attacker.has_keyword(GameEnums.KW_SCHOOLING):
			if int(per_attacker[attacker_uid]) == 1:
				return "%s can't be blocked by exactly one creature" % attacker.display_name()

	# Lure: if anything could block the lure, at least one creature must.
	for attacker_uid in game.attacking_uids():
		var lure: CardInstance = game.get_card(attacker_uid)
		if lure == null or not lure.has_keyword(GameEnums.KW_LURE):
			continue
		var can_be_blocked := false
		for uid in game.get_player(defender_index).battlefield:
			var c: CardInstance = game.get_card(uid)
			if c != null and can_block_attacker(c, lure):
				can_be_blocked = true
				break
		if not can_be_blocked:
			continue
		var is_blocked := false
		for blocker_uid in blocks:
			if int(blocks[blocker_uid]) == lure.uid:
				is_blocked = true
				break
		if not is_blocked:
			return "%s must be blocked if able" % lure.display_name()
	return ""


## --- Declaration ---------------------------------------------------------

## [param attacks] maps each attacking creature to the player it attacks.
static func declare_attackers(game, attacks: Dictionary, champion_attacks: Dictionary = {}) -> void:
	for uid_key in attacks:
		var uid := int(uid_key)
		var c: CardInstance = game.get_card(uid)
		if c == null or not c.can_attack():
			continue
		var defender := int(attacks[uid_key])
		c.attacking = true
		c.attack_target = defender
		c.attack_target_uid = int(champion_attacks.get(uid_key, 0))
		if not c.has_keyword(GameEnums.KW_SLEEPLESS):
			c.tapped = true
		game.log_event("attacks", {"uid": uid, "player": c.controller_index,
				"defender": defender})
		game.emit_trigger_event("attacks", {"uid": uid, "player": c.controller_index,
				"defender": defender})
	game.log_event("attackers_declared", {"count": attacks.size()})


static func declare_blockers(game, blocks: Dictionary) -> void:
	for blocker_uid in blocks:
		var blocker: CardInstance = game.get_card(int(blocker_uid))
		var attacker: CardInstance = game.get_card(int(blocks[blocker_uid]))
		if blocker == null or attacker == null:
			continue
		blocker.blocking.append(attacker.uid)
		attacker.blocked_by.append(blocker.uid)
		attacker.was_blocked = true
		game.log_event("blocks", {"uid": blocker.uid, "attacker": attacker.uid})
		game.emit_trigger_event("blocks", {"uid": blocker.uid, "attacker": attacker.uid})
	game.log_event("blockers_declared", {"count": blocks.size()})


## --- Damage --------------------------------------------------------------

## True when a separate first-strike damage step is needed.
static func needs_first_strike_step(game) -> bool:
	for c in _creatures_in_combat(game):
		if c.has_keyword(GameEnums.KW_RIPTIDE) or c.has_keyword(GameEnums.KW_MAELSTROM):
			return true
	return false


## Deals one step of combat damage. In the first-strike step only creatures
## with first or double strike deal damage; in the regular step everyone else
## does, plus double strikers a second time.
static func deal_combat_damage(game, first_strike_step: bool) -> void:
	var participants := _creatures_in_combat(game)
	var pending: Array = []

	for c in participants:
		if not _deals_damage_this_step(c, first_strike_step):
			continue
		if c.eff_power <= 0:
			continue
		if c.attacking:
			pending.append_array(_attacker_assignments(game, c))
		elif not c.blocking.is_empty():
			pending.append_array(_blocker_assignments(game, c))

	# All combat damage is dealt at once, so a creature that dies still deals
	# its damage.
	for entry in pending:
		var source: CardInstance = entry["source"]
		var amount := int(entry["amount"])
		if amount <= 0:
			continue
		if entry.has("player_index"):
			game.deal_damage_to_player(int(entry["player_index"]), amount, source, true)
		else:
			var target: CardInstance = entry["target"]
			if target != null and target.zone == GameEnums.Zone.BATTLEFIELD:
				game.deal_damage_to_permanent(target, amount, source, true)

		if first_strike_step:
			source.dealt_first_strike_damage = true

	game.log_event("combat_damage", {"first_strike": first_strike_step, "hits": pending.size()})


static func _deals_damage_this_step(c: CardInstance, first_strike_step: bool) -> bool:
	var first := c.has_keyword(GameEnums.KW_RIPTIDE)
	var double := c.has_keyword(GameEnums.KW_MAELSTROM)
	if first_strike_step:
		return first or double
	# Regular step: everyone who is not a pure first striker, and double
	# strikers again.
	return double or not first


## How an attacker splits its power among its blockers, with trample spilling
## over to the defending player.
static func _attacker_assignments(game, attacker: CardInstance) -> Array:
	var out: Array = []
	var defender_index := attacker.attack_target
	if defender_index < 0:
		defender_index = game.defending_player_index()

	var blockers: Array[CardInstance] = []
	for uid in attacker.blocked_by:
		var b: CardInstance = game.get_card(uid)
		if b != null and b.zone == GameEnums.Zone.BATTLEFIELD:
			blockers.append(b)

	if blockers.is_empty():
		# Blocked but every blocker left combat: an unblocked-by-removal
		# attacker deals no damage unless it has Breach.
		if attacker.was_blocked and not attacker.has_keyword(GameEnums.KW_BREACH):
			return out
		var champion: CardInstance = game.get_card(attacker.attack_target_uid) if attacker.attack_target_uid > 0 else null
		if champion != null and champion.zone == GameEnums.Zone.BATTLEFIELD:
			out.append({"source": attacker, "target": champion, "amount": attacker.eff_power})
		else:
			out.append({"source": attacker, "player_index": defender_index,
					"amount": attacker.eff_power})
		return out

	var remaining := attacker.eff_power
	var deathtouch := attacker.has_keyword(GameEnums.KW_VENOMOUS)
	for b in blockers:
		if remaining <= 0:
			break
		# One damage is lethal with deathtouch; otherwise assign what is left
		# of the blocker's toughness.
		var lethal: int = 1 if deathtouch else maxi(1, b.eff_toughness - b.damage)
		var assign: int = min(remaining, lethal)
		out.append({"source": attacker, "target": b, "amount": assign})
		remaining -= assign

	if remaining > 0:
		if attacker.has_keyword(GameEnums.KW_BREACH):
			var champion: CardInstance = game.get_card(attacker.attack_target_uid) if attacker.attack_target_uid > 0 else null
			if champion != null and champion.zone == GameEnums.Zone.BATTLEFIELD:
				out.append({"source": attacker, "target": champion, "amount": remaining})
			else:
				out.append({"source": attacker, "player_index": defender_index,
						"amount": remaining})
		else:
			# Excess damage is simply piled onto the last blocker.
			var last := out[out.size() - 1] as Dictionary
			last["amount"] = int(last["amount"]) + remaining
	return out


static func _blocker_assignments(game, blocker: CardInstance) -> Array:
	var out: Array = []
	var share := blocker.eff_power
	for uid in blocker.blocking:
		var a: CardInstance = game.get_card(uid)
		if a == null or a.zone != GameEnums.Zone.BATTLEFIELD:
			continue
		# Ink blinds the blockers: they take damage but deal none back.
		if a.has_keyword(GameEnums.KW_INK):
			game.log_event("inked", {"uid": blocker.uid, "attacker": a.uid})
			return out
		out.append({"source": blocker, "target": a, "amount": share})
		break  # A blocker blocking one attacker deals all its damage there.
	return out


static func _creatures_in_combat(game) -> Array[CardInstance]:
	var out: Array[CardInstance] = []
	for p in game.players:
		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c == null or not c.is_creature():
				continue
			if c.attacking or not c.blocking.is_empty():
				out.append(c)
	return out


## Clears attacking and blocking state at end of combat.
static func end_combat(game) -> void:
	for p in game.players:
		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c != null:
				c.reset_combat_state()
	game.log_event("combat_ended", {})
