## Executes the data-driven effects on a card.
##
## An effect is a dictionary with an "op" and whatever that op needs, e.g.
##   {"op": "damage", "amount": 3, "to": "t1"}
##   {"op": "draw", "amount": 2, "to": "controller"}
##   {"op": "pump", "power": 2, "toughness": 2, "to": "self"}
## See docs/card_schema.md for the full list.
##
## "to" is either a target id declared by the ability ("t1"), a shorthand
## selector ("self", "controller", "each_opponent", "creatures_you_control"),
## or a dictionary group selector with a filter.
class_name Effects
extends RefCounted


## Runs a list of effects. [param ctx] carries:
##   controller: int, source: CardInstance, targets: Array,
##   target_specs: Array, x: int
static func execute(game, effect_list: Array, ctx: Dictionary) -> void:
	for e in effect_list:
		if e is Dictionary:
			execute_one(game, e as Dictionary, ctx)
			if game.is_over():
				return


static func execute_one(game, effect: Dictionary, ctx: Dictionary) -> void:
	var op := str(effect.get("op", ""))
	var controller := int(ctx.get("controller", 0))
	var source: CardInstance = ctx.get("source")

	# An effect can be gated on a condition, e.g. only if you control a Fish.
	if effect.has("condition") and not check_condition(game, effect["condition"] as Dictionary, ctx):
		return

	match op:
		"damage":
			var amount := resolve_amount(game, effect.get("amount", 0), ctx) + star_bonus(effect, ctx)
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				_apply_damage(game, ref, amount, source, ctx)

		"destroy":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null:
					game.destroy_permanent(c, source)

		"exile":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null:
					game.move_to_zone(c, GameEnums.Zone.EXILE, "exiled")

		"bounce":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null:
					game.move_to_zone(c, GameEnums.Zone.HAND, "returned to hand")

		"sacrifice":
			for ref in resolve_refs(game, effect.get("to", "self"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null:
					game.sacrifice_permanent(c)

		"draw":
			var n := resolve_amount(game, effect.get("amount", 1), ctx) + star_bonus(effect, ctx)
			for ref in resolve_refs(game, effect.get("to", "controller"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.draw_cards(pi, n)

		"discard":
			var n := resolve_amount(game, effect.get("amount", 1), ctx)
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.discard_cards(pi, n, str(effect.get("choice", "random")))

		"mill":
			var n := resolve_amount(game, effect.get("amount", 1), ctx)
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.mill_cards(pi, n)

		"gain_life":
			var n := resolve_amount(game, effect.get("amount", 1), ctx) + star_bonus(effect, ctx)
			for ref in resolve_refs(game, effect.get("to", "controller"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.gain_life(pi, n)

		"lose_life":
			var n := resolve_amount(game, effect.get("amount", 1), ctx) + star_bonus(effect, ctx)
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.lose_life(pi, n, source)

		"pump":
			var bonus := star_bonus(effect, ctx)
			var dp := resolve_amount(game, effect.get("power", 0), ctx) + bonus
			var dt := resolve_amount(game, effect.get("toughness", 0), ctx) + bonus
			var kws := effect.get("keywords", []) as Array
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c == null:
					continue
				c.temp_power += dp
				c.temp_toughness += dt
				for kw in kws:
					if str(kw) not in c.temp_keywords:
						c.temp_keywords.append(str(kw))
				game.log_event("pump", {"uid": c.uid, "power": dp, "toughness": dt})
			game.refresh_continuous()

		"counters":
			var kind := str(effect.get("kind", "+1/+1"))
			var n := resolve_amount(game, effect.get("amount", 1), ctx)
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null:
					c.add_counters(kind, n)
					game.log_event("counters", {"uid": c.uid, "kind": kind, "amount": n})
			game.refresh_continuous()

		"tap":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null and not c.tapped:
					c.tapped = true
					game.log_event("tap", {"uid": c.uid})

		"untap":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null and c.tapped:
					c.tapped = false
					game.log_event("untap", {"uid": c.uid})

		"counter_spell":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null:
					game.counter_spell(c)

		"token":
			var n := resolve_amount(game, effect.get("amount", 1), ctx) + star_bonus(effect, ctx)
			var token_id := str(effect.get("token", ""))
			for _i in n:
				game.create_token(token_id, controller)

		"add_mana":
			var symbols := effect.get("mana", []) as Array
			var player := game.get_player(controller)
			for sym in symbols:
				player.mana_pool.add(str(sym), 1)
			game.log_event("mana", {"player": controller, "pool": str(player.mana_pool)})

		"return_from_graveyard":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null and c.zone == GameEnums.Zone.GRAVEYARD:
					var dest: GameEnums.Zone = GameEnums.Zone.HAND
					if str(effect.get("zone", "hand")) == "battlefield":
						dest = GameEnums.Zone.BATTLEFIELD
					game.move_to_zone(c, dest, "returned from graveyard")

		"search_basic_land":
			# Simplified tutor: puts a basic land from the library into play or
			# hand, which is all the current card set needs.
			var to_battlefield := str(effect.get("zone", "hand")) == "battlefield"
			game.search_library_for_basic(controller, to_battlefield, bool(effect.get("tapped", true)))

		"scry":
			var n := resolve_amount(game, effect.get("amount", 1), ctx)
			game.scry(controller, n)

		"move_depth":
			# Drags creatures between bands, which is how the board gets
			# rearranged mid-combat.
			var delta := int(effect.get("delta", 1))
			var to_band := str(effect.get("band", ""))
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c == null or not c.is_creature():
					continue
				if c.has_keyword(GameEnums.KW_ANCHORED) and not bool(effect.get("forced", true)):
					continue
				var target_band: int
				if to_band.is_empty():
					target_band = int(c.depth) + delta
				else:
					target_band = int(GameEnums.parse_depth(to_band))
				game.set_depth(c, target_band, true)
			game.refresh_continuous()

		"salvage":
			var n := resolve_amount(game, effect.get("amount", 1), ctx)
			game.pay_salvage(controller, n)

		"roll":
			_execute_roll(game, effect, ctx)

		"skip_turn":
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.skip_next_turn(pi)

		"extra_turn":
			for ref in resolve_refs(game, effect.get("to", "controller"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.grant_extra_turn(pi)

		"set_timer":
			var seconds := float(effect.get("seconds", 10))
			var temporary := bool(effect.get("temporary", false))
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.set_turn_time_limit(pi, seconds, temporary)

		"scale_timer":
			var factor := float(effect.get("factor", 0.5))
			var temporary := bool(effect.get("temporary", true))
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.scale_turn_time_limit(pi, factor, temporary)

		"timeout_penalty":
			var life := resolve_amount(game, effect.get("amount", 1), ctx)
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.add_timeout_penalty(pi, life)

		"rewind":
			# Undo the turn. The card doing the rewinding is exempt, otherwise
			# it would come back to hand and could be cast again forever.
			var keep: Array[int] = []
			if source != null:
				keep.append(source.uid)
			var stack_uid := int(ctx.get("stack_uid", 0))
			if stack_uid > 0 and stack_uid != (source.uid if source != null else 0):
				keep.append(stack_uid)
			game.restore_snapshot(game.turn_snapshot(), keep)
			if source != null and source.zone != GameEnums.Zone.BATTLEFIELD:
				game.move_to_zone(source, GameEnums.Zone.EXILE, "spent on the rewind")

		"reveal_hand":
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.reveal_hand(pi, controller)

		"steal_hand":
			var n := resolve_amount(game, effect.get("amount", 1), ctx) + star_bonus(effect, ctx)
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.steal_from_hand(controller, pi, n)

		"steal_library":
			var n := resolve_amount(game, effect.get("amount", 1), ctx) + star_bonus(effect, ctx)
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.steal_from_library(controller, pi, n)

		"discard_hand":
			for ref in resolve_refs(game, effect.get("to", "each_opponent"), ctx):
				var pi := _player_from_ref(game, ref)
				if pi >= 0:
					game.discard_entire_hand(pi)

		"swap_hands":
			var others := resolve_refs(game, effect.get("to", "each_opponent"), ctx)
			if not others.is_empty():
				var pi := _player_from_ref(game, others[0] as Dictionary)
				if pi >= 0:
					game.swap_hands(controller, pi)

		"gain_control":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null:
					game.change_control(c, controller)

		"swap_control":
			# Trade a permanent of yours for one of theirs.
			var mine := resolve_refs(game, effect.get("mine", "t1"), ctx)
			var theirs := resolve_refs(game, effect.get("theirs", "t2"), ctx)
			if not mine.is_empty() and not theirs.is_empty():
				var a := _card_from_ref(game, mine[0] as Dictionary)
				var b := _card_from_ref(game, theirs[0] as Dictionary)
				if a != null and b != null:
					var a_owner := a.controller_index
					var b_owner := b.controller_index
					game.change_control(a, b_owner)
					game.change_control(b, a_owner)

		"clone":
			for ref in resolve_refs(game, effect.get("to", "t1"), ctx):
				var c := _card_from_ref(game, ref)
				if c != null:
					game.create_copy(c.data, controller, c.star_level)

		"recover":
			var n := resolve_amount(game, effect.get("amount", 1), ctx)
			var to_battlefield := str(effect.get("zone", "hand")) == "battlefield"
			for _i in n:
				game.recover_from_wreck(controller, effect.get("filter", {}) as Dictionary,
						to_battlefield)

		"vault_fetch":
			var n := resolve_amount(game, effect.get("amount", 1), ctx)
			var to_battlefield := str(effect.get("zone", "hand")) == "battlefield"
			for _i in n:
				game.fetch_from_vault(controller, effect.get("filter", {}) as Dictionary,
						to_battlefield)

		"extra_turn_note", "noop":
			pass

		_:
			push_warning("Unknown effect op: %s" % op)


## Rolls dice and runs the first matching outcome. Outcomes are checked from
## the top, so list the best result first:
##   {"op": "roll", "sides": 6, "outcomes": [
##      {"min": 5, "effects": [...]},
##      {"min": 3, "effects": [...]},
##      {"min": 1, "effects": [...]}]}
static func _execute_roll(game, effect: Dictionary, ctx: Dictionary) -> void:
	var controller := int(ctx.get("controller", 0))
	var sides := int(effect.get("sides", 6))
	var count := int(effect.get("count", 1))
	var total := game.roll_dice(controller, sides, count)
	# Upgrading a gambling card tilts the odds in your favour.
	total += star_bonus(effect, ctx)

	for outcome_variant in effect.get("outcomes", []) as Array:
		var outcome := outcome_variant as Dictionary
		var low := int(outcome.get("min", 1))
		var high := int(outcome.get("max", 9999))
		if total >= low and total <= high:
			game.log_event("roll_outcome", {
				"total": total, "label": str(outcome.get("label", "")),
			})
			execute(game, outcome.get("effects", []) as Array, ctx)
			return
	game.log_event("roll_outcome", {"total": total, "label": "no effect"})


## --- Amounts -------------------------------------------------------------

## An amount is a plain integer, or a dictionary such as
##   {"dynamic": "x"}                       the chosen value of X
##   {"dynamic": "count", "filter": {...}}  number of matching permanents
##   {"dynamic": "cards_in_hand"}
## Extra magnitude a card gains from being upgraded: "per_star": 1 means
## +1 for every star above the first.
static func star_bonus(effect: Dictionary, ctx: Dictionary) -> int:
	var per_star := int(effect.get("per_star", 0))
	if per_star == 0:
		return 0
	return per_star * (int(ctx.get("star", GameEnums.MIN_STARS)) - GameEnums.MIN_STARS)


static func resolve_amount(game, value: Variant, ctx: Dictionary) -> int:
	if value is int or value is float:
		return int(value)
	if not (value is Dictionary):
		return 0
	var d := value as Dictionary
	var controller := int(ctx.get("controller", 0))
	match str(d.get("dynamic", "")):
		"x":
			return int(ctx.get("x", 0))
		"count":
			var f := d.get("filter", {}) as Dictionary
			var scope := str(d.get("controller", "you"))
			return _count_permanents(game, f, controller, scope)
		"half_life":
			# Rounded down, as printed on Queen's Bargain.
			return int(game.get_player(controller).life / 2)
		"cards_in_hand":
			return game.get_player(controller).hand.size()
		"spells_cast_this_turn":
			return int(game.spells_cast_this_turn.get(controller, 0))
		"wreck_size":
			return game.wreck_size()
		"creatures_in_band":
			var band := GameEnums.parse_depth(str(d.get("band", "abyss")))
			var n := 0
			for uid in game.get_player(controller).battlefield:
				var c: CardInstance = game.get_card(uid)
				if c != null and c.is_creature() and c.depth == band:
					n += 1
			return n
		"cards_in_graveyard":
			return game.get_player(controller).graveyard.size()
		"life_lost_this_turn":
			return int(game.life_lost_this_turn.get(controller, 0))
		"source_power":
			var src: CardInstance = ctx.get("source")
			return src.eff_power if src != null else 0
		_:
			return int(d.get("value", 0))


## Whether a scope word ("you", "ally", "opponent", "any") covers a player.
static func _scope_includes(game, scope: String, controller: int, subject: int) -> bool:
	match scope:
		"you":
			return subject == controller
		"ally", "team":
			return game.are_allies(controller, subject)
		"opponent":
			return not game.are_allies(controller, subject)
		_:
			return true


static func _count_permanents(game, f: Dictionary, controller: int, scope: String) -> int:
	var n := 0
	for p in game.players:
		if not _scope_includes(game, scope, controller, p.index):
			continue
		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c != null and Targeting.matches_filter(game, f, c):
				n += 1
	return n


## --- Selectors -----------------------------------------------------------

## Turns a "to" value into concrete target references.
static func resolve_refs(game, selector: Variant, ctx: Dictionary) -> Array:
	var controller := int(ctx.get("controller", 0))
	var source: CardInstance = ctx.get("source")

	if selector is Dictionary:
		return _resolve_group(game, selector as Dictionary, ctx)

	var key := str(selector)

	# A declared target slot, e.g. "t1".
	var specs: Array = ctx.get("target_specs", []) as Array
	var chosen: Array = ctx.get("targets", []) as Array
	for i in specs.size():
		var spec := specs[i] as Dictionary
		if str(spec.get("id", "t%d" % (i + 1))) == key:
			if i < chosen.size() and chosen[i] is Dictionary and not (chosen[i] as Dictionary).is_empty():
				return [chosen[i]]
			return []

	match key:
		"self", "source":
			return [GameAction.card_target(source.uid)] if source != null else []
		"controller", "you":
			return [GameAction.player_target(controller)]
		"each_opponent", "opponent":
			var out: Array = []
			for index in game.opponents_of(controller):
				out.append(GameAction.player_target(index))
			return out
		"each_ally", "team":
			var out: Array = [GameAction.player_target(controller)]
			for index in game.teammates_of(controller):
				out.append(GameAction.player_target(index))
			return out
		"teammates":
			var out: Array = []
			for index in game.teammates_of(controller):
				out.append(GameAction.player_target(index))
			return out
		"each_player":
			var out: Array = []
			for p in game.players:
				if not p.has_lost:
					out.append(GameAction.player_target(p.index))
			return out
		"all_creatures":
			return _resolve_group(game, {"kind": "creature", "controller": "any"}, ctx)
		"creatures_you_control":
			return _resolve_group(game, {"kind": "creature", "controller": "you"}, ctx)
		"creatures_opponent_controls":
			return _resolve_group(game, {"kind": "creature", "controller": "opponent"}, ctx)
		"other_creatures_you_control":
			var refs := _resolve_group(game, {"kind": "creature", "controller": "you"}, ctx)
			var out: Array = []
			for r in refs:
				if source == null or int((r as Dictionary).get("uid", -1)) != source.uid:
					out.append(r)
			return out
		"creatures_in_my_band", "your_band":
			var src_band: int = int(source.depth) if source != null else int(GameEnums.Depth.MIDWATER)
			return _band_refs(game, src_band, "any", ctx)
		"opponent_creatures_in_my_band":
			var band: int = int(source.depth) if source != null else int(GameEnums.Depth.MIDWATER)
			return _band_refs(game, band, "opponent", ctx)
		"surface_creatures":
			return _band_refs(game, int(GameEnums.Depth.SURFACE), "any", ctx)
		"abyss_creatures":
			return _band_refs(game, int(GameEnums.Depth.ABYSS), "any", ctx)
		"attacking_creatures":
			return _resolve_group(game, {"kind": "creature", "controller": "any", "filter": {"attacking": true}}, ctx)
		_:
			return []


## Every creature in one depth band, optionally limited by controller.
static func _band_refs(game, band: int, scope: String, ctx: Dictionary) -> Array:
	var controller := int(ctx.get("controller", 0))
	var out: Array = []
	for p in game.players:
		if not _scope_includes(game, scope, controller, p.index):
			continue
		for uid in p.battlefield:
			var c: CardInstance = game.get_card(uid)
			if c != null and c.is_creature() and int(c.depth) == band:
				out.append(GameAction.card_target(uid))
	return out


static func _resolve_group(game, group: Dictionary, ctx: Dictionary) -> Array:
	var controller := int(ctx.get("controller", 0))
	var out: Array = []
	var kind := str(group.get("kind", "permanent"))
	var scope := str(group.get("controller", "any"))
	var f := group.get("filter", {}) as Dictionary

	for p in game.players:
		if not _scope_includes(game, scope, controller, p.index):
			continue
		for uid in p.battlefield.duplicate():
			var c: CardInstance = game.get_card(uid)
			if c == null:
				continue
			if kind == "creature" and not c.is_creature():
				continue
			if kind == "land" and not c.is_land():
				continue
			if kind == "artifact" and not c.is_type(GameEnums.TYPE_ARTIFACT):
				continue
			if kind == "enchantment" and not c.is_type(GameEnums.TYPE_ENCHANTMENT):
				continue
			if not Targeting.matches_filter(game, f, c):
				continue
			out.append(GameAction.card_target(uid))
	return out


## --- Conditions ----------------------------------------------------------

## Conditions gate triggers and effects:
##   {"type": "controls", "filter": {"subtypes": ["Fish"]}, "at_least": 1}
##   {"type": "life_at_most", "value": 10}
##   {"type": "source_is_attacking"}
static func check_condition(game, cond: Dictionary, ctx: Dictionary) -> bool:
	var controller := int(ctx.get("controller", 0))
	var source: CardInstance = ctx.get("source")
	match str(cond.get("type", "")):
		"controls":
			var n := _count_permanents(game, cond.get("filter", {}) as Dictionary, controller,
					str(cond.get("controller", "you")))
			return n >= int(cond.get("at_least", 1))
		"life_at_most":
			return game.get_player(controller).life <= int(cond.get("value", 0))
		"life_at_least":
			return game.get_player(controller).life >= int(cond.get("value", 0))
		"opponent_life_at_most":
			for p in game.players:
				if p.index != controller and p.life <= int(cond.get("value", 0)):
					return true
			return false
		"source_is_attacking":
			return source != null and source.attacking
		"cards_in_hand_at_most":
			return game.get_player(controller).hand.size() <= int(cond.get("value", 0))
		"tide":
			var want := str(cond.get("value", "high")).to_lower()
			var is_high := game.tide == GameEnums.Tide.HIGH
			return is_high if want == "high" else not is_high
		"source_in_band":
			if source == null:
				return false
			return source.depth == GameEnums.parse_depth(str(cond.get("band", "abyss")))
		"spells_cast_at_least":
			return int(game.spells_cast_this_turn.get(controller, 0)) >= int(cond.get("value", 1))
		"wreck_at_least":
			return game.wreck_size() >= int(cond.get("value", 1))
		"always", "":
			return true
		_:
			return true


## --- Damage --------------------------------------------------------------

static func _apply_damage(game, ref: Dictionary, amount: int, source: CardInstance, ctx: Dictionary) -> void:
	if amount <= 0:
		return
	if str(ref.get("type", "")) == "player":
		game.deal_damage_to_player(int(ref.get("index", 0)), amount, source)
	else:
		var c := _card_from_ref(game, ref)
		if c != null:
			game.deal_damage_to_permanent(c, amount, source)


static func _card_from_ref(game, ref: Dictionary) -> CardInstance:
	if str(ref.get("type", "")) != "card":
		return null
	return game.get_card(int(ref.get("uid", 0)))


static func _player_from_ref(game, ref: Dictionary) -> int:
	if str(ref.get("type", "")) == "player":
		return int(ref.get("index", -1))
	# A card reference resolves to its controller, so "draw" can be aimed at a
	# permanent's controller.
	var c := _card_from_ref(game, ref)
	return c.controller_index if c != null else -1
