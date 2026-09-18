## Works out what a spell or ability is allowed to target.
##
## A target spec is a dictionary on a card ability, for example:
##   {"id": "t1", "kind": "creature", "controller": "opponent",
##    "filter": {"max_power": 3}, "optional": false}
##
## "kind" is one of: creature, permanent, land, artifact, enchantment, player,
## any (creature or player), spell, card_in_graveyard.
## The game object is passed untyped to avoid a cyclic class dependency.
class_name Targeting
extends RefCounted


## Every target this spec could legally choose right now.
static func legal_targets(game, spec: Dictionary, controller: int, source: CardInstance) -> Array:
	var out: Array = []
	var kind := str(spec.get("kind", "any"))

	if kind == "player":
		for p in game.players:
			if _controller_matches(spec, controller, p.index) and not p.has_lost:
				out.append(GameAction.player_target(p.index))
		return out

	if kind == "spell":
		for uid in game.stack:
			var c: CardInstance = game.get_card(uid)
			if c == null or c.stack_kind != "spell":
				continue
			if _controller_matches(spec, controller, c.controller_index) \
					and _passes_filter(game, spec, c):
				out.append(GameAction.card_target(uid))
		return out

	if kind == "card_in_graveyard":
		for p in game.players:
			if not _controller_matches(spec, controller, p.index):
				continue
			for uid in p.graveyard:
				var c: CardInstance = game.get_card(uid)
				if c != null and _passes_filter(game, spec, c):
					out.append(GameAction.card_target(uid))
		return out

	# Permanents on the battlefield, plus players for "any".
	for p in game.players:
		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c == null:
				continue
			if not _kind_matches(kind, c):
				continue
			if not _controller_matches(spec, controller, c.controller_index):
				continue
			if not _passes_filter(game, spec, c):
				continue
			if not can_be_targeted_by(c, controller):
				continue
			out.append(GameAction.card_target(uid))

	if kind == "any":
		for p in game.players:
			if _controller_matches(spec, controller, p.index) and not p.has_lost:
				out.append(GameAction.player_target(p.index))

	return out


## Re-checks a chosen target when the spell resolves. A spell whose targets
## have all become illegal does not resolve at all.
static func is_still_legal(game, spec: Dictionary, target: Dictionary, controller: int, source: CardInstance) -> bool:
	var kind := str(spec.get("kind", "any"))
	if str(target.get("type", "")) == "player":
		var pi := int(target.get("index", -1))
		if pi < 0 or pi >= game.players.size():
			return false
		if game.players[pi].has_lost:
			return false
		return kind == "player" or kind == "any"

	var c: CardInstance = game.get_card(int(target.get("uid", 0)))
	if c == null:
		return false
	if kind == "spell":
		return c.stack_kind == "spell" and int(target.get("uid", 0)) in game.stack
	if kind == "card_in_graveyard":
		return c.zone == GameEnums.Zone.GRAVEYARD and _passes_filter(game, spec, c)
	if c.zone != GameEnums.Zone.BATTLEFIELD:
		return false
	if not _kind_matches(kind, c):
		return false
	if not _controller_matches(spec, controller, c.controller_index):
		return false
	if not _passes_filter(game, spec, c):
		return false
	return can_be_targeted_by(c, controller)


## Hexproof stops opponents, not the permanent's own controller.
static func can_be_targeted_by(card: CardInstance, chooser_index: int) -> bool:
	if card.has_keyword(GameEnums.KW_SLIPPERY) and card.controller_index != chooser_index:
		return false
	return true


static func _kind_matches(kind: String, card: CardInstance) -> bool:
	match kind:
		"creature", "any":
			return card.is_creature()
		"permanent":
			return card.is_permanent()
		"land":
			return card.is_land()
		"artifact":
			return card.is_type(GameEnums.TYPE_ARTIFACT)
		"enchantment":
			return card.is_type(GameEnums.TYPE_ENCHANTMENT)
		_:
			return true


static func _controller_matches(spec: Dictionary, chooser: int, subject: int) -> bool:
	match str(spec.get("controller", "any")):
		"you":
			return subject == chooser
		"opponent":
			return subject != chooser
		_:
			return true


## Shared predicate for target specs and for effects that hit "each creature
## with flying" and the like.
static func _passes_filter(game, spec: Dictionary, card: CardInstance) -> bool:
	var f: Dictionary = spec.get("filter", {}) as Dictionary
	return matches_filter(game, f, card)


static func matches_filter(game, f: Dictionary, card: CardInstance) -> bool:
	if f.is_empty():
		return true

	if f.has("types"):
		for t in f["types"]:
			if not card.is_type(str(t)):
				return false
	if f.has("not_types"):
		for t in f["not_types"]:
			if card.is_type(str(t)):
				return false
	if f.has("subtypes"):
		var any_subtype := false
		for s in f["subtypes"]:
			if card.is_subtype(str(s)):
				any_subtype = true
				break
		if not any_subtype:
			return false
	if f.has("colors"):
		var any_color := false
		for c in f["colors"]:
			if str(c) in card.eff_colors:
				any_color = true
				break
		if not any_color:
			return false
	if f.has("keywords"):
		for k in f["keywords"]:
			if not card.has_keyword(str(k)):
				return false
	if f.has("without_keywords"):
		for k in f["without_keywords"]:
			if card.has_keyword(str(k)):
				return false
	if f.has("max_power") and card.eff_power > int(f["max_power"]):
		return false
	if f.has("min_power") and card.eff_power < int(f["min_power"]):
		return false
	if f.has("max_toughness") and card.eff_toughness > int(f["max_toughness"]):
		return false
	if f.has("max_mana_value") and card.data.mana_value() > int(f["max_mana_value"]):
		return false
	if f.has("min_mana_value") and card.data.mana_value() < int(f["min_mana_value"]):
		return false
	if f.has("tapped") and card.tapped != bool(f["tapped"]):
		return false
	if f.has("attacking") and card.attacking != bool(f["attacking"]):
		return false
	if f.has("blocking") and (not card.blocking.is_empty()) != bool(f["blocking"]):
		return false
	if f.has("is_token") and card.is_token != bool(f["is_token"]):
		return false
	return true


## Convenience for effects that need every permanent matching a filter.
static func collect_permanents(game, f: Dictionary, chooser: int) -> Array[int]:
	var out: Array[int] = []
	for p in game.players:
		if not _controller_matches(f, chooser, p.index):
			continue
		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c != null and matches_filter(game, f.get("filter", f) as Dictionary, c):
				out.append(uid)
	return out
