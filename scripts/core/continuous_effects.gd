## Applies static abilities of permanents on the battlefield.
##
## Recomputed from scratch every time the board changes, which avoids the whole
## class of bugs where a buff is applied twice or never removed. Real Magic
## resolves these in seven numbered layers; this engine handles the two that
## the card set uses: power/toughness changes and granted keywords.
##
## A static ability looks like:
##   {"kind": "static", "effect": {
##      "type": "pt_boost", "power": 1, "toughness": 1,
##      "affects": {"kind": "creature", "controller": "you",
##                  "filter": {"subtypes": ["Fish"]}},
##      "include_self": false}}
class_name ContinuousEffects
extends RefCounted


static func apply_all(game) -> void:
	# Layer 0: reset to printed values plus counters and until-EOT effects.
	for uid in game.cards:
		var c: CardInstance = game.cards[uid]
		c.refresh_base_characteristics()

	# Gather every static ability currently on the battlefield.
	var statics: Array = []
	for p in game.players:
		for uid in p.battlefield:
			var src: CardInstance = game.get_card(uid)
			if src == null:
				continue
			for ability in src.data.abilities_of_kind("static"):
				statics.append({"source": src, "effect": (ability as Dictionary).get("effect", {})})

	# Global rules come before card-specific ones: the tide and a creature's
	# own depth keywords are part of what a static ability then modifies.
	_apply_tide_and_depth(game)

	# Keywords next, so that a filter looking for "creatures with Breach"
	# sees keywords granted by another permanent.
	for entry in statics:
		var eff := entry["effect"] as Dictionary
		if str(eff.get("type", "")) == "grant_keyword":
			_apply_to_affected(game, entry["source"], eff, func(card: CardInstance) -> void:
				card.grant_keyword(str(eff.get("keyword", ""))))

	for entry in statics:
		var eff := entry["effect"] as Dictionary
		if str(eff.get("type", "")) == "pt_boost":
			var dp := int(eff.get("power", 0))
			var dt := int(eff.get("toughness", 0))
			_apply_to_affected(game, entry["source"], eff, func(card: CardInstance) -> void:
				card.eff_power += dp
				card.eff_toughness += dt)


## The tide, Pressure, Swarm and Frenzy: rules that apply to every creature
## without any permanent needing to grant them.
static func _apply_tide_and_depth(game) -> void:
	var favoured := GameEnums.favoured_band(game.tide)

	for p in game.players:
		var spells_cast := int(game.spells_cast_this_turn.get(p.index, 0))
		# Count creatures per band once, so Swarm is O(n) rather than O(n^2).
		var band_counts := {}
		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c != null and c.is_creature():
				band_counts[c.depth] = int(band_counts.get(c.depth, 0)) + 1

		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c == null or not c.is_creature():
				continue

			# The tide lifts one band for both players alike.
			if int(c.depth) == favoured:
				c.eff_power += 1

			if c.has_keyword(GameEnums.KW_PRESSURE):
				if c.depth == GameEnums.Depth.ABYSS:
					c.eff_power += 2
					c.eff_toughness += 2
				elif c.depth == GameEnums.Depth.SURFACE:
					c.eff_power -= 1
					c.eff_toughness -= 1

			if c.has_keyword(GameEnums.KW_SWARM):
				var others := int(band_counts.get(c.depth, 1)) - 1
				c.eff_power += max(0, others)

			if c.has_keyword(GameEnums.KW_FRENZY) and spells_cast > 0:
				c.eff_power += spells_cast
				c.eff_toughness += spells_cast


static func _apply_to_affected(game, source: CardInstance, effect: Dictionary, fn: Callable) -> void:
	var affects := effect.get("affects", {}) as Dictionary
	var include_self := bool(effect.get("include_self", true))
	var kind := str(affects.get("kind", "creature"))
	var scope := str(affects.get("controller", "you"))
	var f := affects.get("filter", {}) as Dictionary

	for p in game.players:
		if scope == "you" and p.index != source.controller_index:
			continue
		if scope == "opponent" and p.index == source.controller_index:
			continue
		for uid in p.battlefield:
			if uid == source.uid and not include_self:
				continue
			var c: CardInstance = game.get_card(uid)
			if c == null:
				continue
			if kind == "creature" and not c.is_creature():
				continue
			if kind == "land" and not c.is_land():
				continue
			if not Targeting.matches_filter(game, f, c):
				continue
			fn.call(c)


## Total mana cost reduction that applies to casting [param card].
static func cost_reduction_for(game, card: CardInstance, controller: int) -> int:
	var total := 0
	for p in game.players:
		if p.index != controller:
			continue
		for uid in p.battlefield:
			var src: CardInstance = game.get_card(uid)
			if src == null:
				continue
			for ability in src.data.abilities_of_kind("static"):
				var eff := (ability as Dictionary).get("effect", {}) as Dictionary
				if str(eff.get("type", "")) != "cost_reduction":
					continue
				if Targeting.matches_filter(game, eff.get("filter", {}) as Dictionary, card):
					total += int(eff.get("amount", 0))
	return total
