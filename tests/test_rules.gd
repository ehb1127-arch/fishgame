## Rules engine tests: mana, depth bands, the tide, keywords, the wreck,
## the stack, combat, Champions, dice, rewind, and the clock.
class_name TestRules
extends RefCounted


static func run(t: TestFramework) -> void:
	_test_mana(t)
	_test_card_database(t)
	_test_setup_and_turns(t)
	_test_depth_blocking(t)
	_test_tide(t)
	_test_keywords(t)
	_test_wreck_and_salvage(t)
	_test_stack(t)
	_test_combat_damage(t)
	_test_champion(t)
	_test_dice(t)
	_test_rewind(t)
	_test_clock(t)
	_test_multiplayer(t)


static func _test_mana(t: TestFramework) -> void:
	t.start("mana")
	var cost := Mana.Cost.parse("2UU")
	t.eq(cost.generic, 2, "generic portion parsed")
	t.eq(int(cost.symbols.get("U", 0)), 2, "coloured portion parsed")
	t.eq(cost.mana_value(), 4, "mana value")

	var x_cost := Mana.Cost.parse("X1R")
	t.eq(x_cost.x_count, 1, "X counted")
	t.eq(x_cost.mana_value(3), 5, "X contributes to mana value")

	var pool := Mana.Pool.new()
	pool.add("U", 2)
	pool.add("C", 2)
	t.check(pool.can_pay(cost), "pool covers 2UU")
	t.check(pool.pay(cost), "pool pays 2UU")
	t.eq(pool.total(), 0, "pool emptied exactly")

	# Payment planning must not spend a coloured source the cost needs.
	var sources := [["U"], ["U"], ["R"], ["R"]]
	var plan := Mana.plan_payment(sources, Mana.Cost.parse("2UU"))
	t.eq(plan.size(), 4, "planner taps four sources for 2UU")
	var blue_used := 0
	for entry in plan:
		if str((entry as Dictionary)["symbol"]) == "U":
			blue_used += 1
	t.eq(blue_used, 2, "planner assigns exactly two blue")

	t.check(Mana.plan_payment([["R"], ["R"]], Mana.Cost.parse("UU")).is_empty(),
		"planner refuses a cost it cannot cover")


static func _test_card_database(t: TestFramework) -> void:
	t.start("card database")
	t.gt(float(Cards.all_cards().size()), 50.0, "cards loaded")
	t.gt(float(Cards.deck_ids().size()), 4.0, "decks loaded")
	t.gt(float(Cards.story_ids().size()), 4.0, "story arcs loaded")

	for deck_id in Cards.deck_ids():
		var built := Cards.build_deck(str(deck_id))
		t.eq((built["main"] as Array).size(), 40, "%s has 40 cards" % deck_id)

	# Every ability must name an op the engine knows, or cards fail silently.
	var known_kinds := ["spell", "triggered", "activated", "static", "mana", "champion"]
	for card in Cards.all_cards():
		var c := card as CardData
		for ability in c.abilities:
			var kind := str((ability as Dictionary).get("kind", ""))
			t.check(kind in known_kinds, "%s has valid ability kind (%s)" % [c.name, kind])


static func _test_setup_and_turns(t: TestFramework) -> void:
	t.start("setup and turns")
	var game := TestHelpers.new_game()
	t.eq(game.players.size(), 2, "two players")
	t.eq(game.get_player(0).hand.size(), 7, "opening hand of seven")
	t.eq(game.turn_number, 1, "starts on turn one")
	t.eq(game.get_player(0).library.size(), 33, "library is deck minus hand")

	# The player on the play skips their first draw.
	t.check(TestHelpers.advance_to_step(game, GameEnums.Step.PRECOMBAT_MAIN),
		"reaches the first main phase")
	t.eq(game.get_player(0).hand.size(), 7, "player on the play does not draw first turn")

	# Land drops are once per turn and sorcery speed.
	var land_uid := -1
	for uid in game.get_player(0).hand:
		if game.get_card(uid).data.is_land():
			land_uid = uid
			break
	if land_uid >= 0:
		t.check(game.perform(GameAction.play_land(0, land_uid)), "first land drop allowed")
		var second := -1
		for uid in game.get_player(0).hand:
			if game.get_card(uid).data.is_land():
				second = uid
				break
		if second >= 0:
			t.check(not game.perform(GameAction.play_land(0, second)),
				"second land drop refused")


static func _test_depth_blocking(t: TestFramework) -> void:
	t.start("depth bands")
	var game := TestHelpers.new_game()
	TestHelpers.advance_to_step(game, GameEnums.Step.PRECOMBAT_MAIN)

	var attacker := TestHelpers.put_in_play(game, "coral_grazer", 0, GameEnums.Depth.SURFACE)
	var same_band := TestHelpers.put_in_play(game, "coral_grazer", 1, GameEnums.Depth.SURFACE)
	var other_band := TestHelpers.put_in_play(game, "coral_grazer", 1, GameEnums.Depth.ABYSS)
	attacker.attacking = true

	t.check(Combat.can_block_attacker(same_band, attacker), "same band can block")
	t.check(not Combat.can_block_attacker(other_band, attacker), "other band cannot block")

	# Amphibious reaches one band either way, but not two.
	var amphibious := TestHelpers.put_in_play(game, "abyssal_drifter", 1, GameEnums.Depth.MIDWATER)
	t.check(Combat.can_block_attacker(amphibious, attacker), "amphibious blocks one band away")
	game.set_depth(amphibious, int(GameEnums.Depth.ABYSS), true)
	t.check(not Combat.can_block_attacker(amphibious, attacker), "amphibious cannot reach two bands")

	# One creature may ride the current per turn; Diver ignores the budget.
	game.get_player(0).depth_moves_this_turn = 0
	var moves := game.possible_depth_moves(0)
	t.check(moves.has(attacker.uid), "a creature can move while the budget is unspent")
	game.get_player(0).depth_moves_this_turn = GameEnums.DEPTH_MOVES_PER_TURN
	t.check(not game.possible_depth_moves(0).has(attacker.uid),
		"budget spent stops further moves")

	# Anchored never moves.
	var anchored := TestHelpers.put_in_play(game, "titan_barnacle", 0, GameEnums.Depth.ABYSS)
	game.get_player(0).depth_moves_this_turn = 0
	t.check(not game.possible_depth_moves(0).has(anchored.uid), "anchored cannot change band")


static func _test_tide(t: TestFramework) -> void:
	t.start("tide")
	t.eq(GameEnums.tide_for_turn(1), GameEnums.Tide.HIGH, "turn 1 is high tide")
	t.eq(GameEnums.tide_for_turn(2), GameEnums.Tide.HIGH, "turn 2 is still high")
	t.eq(GameEnums.tide_for_turn(3), GameEnums.Tide.LOW, "turn 3 flips to low")
	t.eq(GameEnums.tide_for_turn(4), GameEnums.Tide.LOW, "turn 4 stays low")
	t.eq(GameEnums.tide_for_turn(5), GameEnums.Tide.HIGH, "turn 5 flips back")

	var game := TestHelpers.new_game()
	game.tide = GameEnums.Tide.HIGH
	var surface := TestHelpers.put_in_play(game, "coral_grazer", 0, GameEnums.Depth.SURFACE)
	var abyss := TestHelpers.put_in_play(game, "coral_grazer", 0, GameEnums.Depth.ABYSS)
	game.refresh_continuous()
	t.eq(surface.eff_power, 4, "high tide lifts the surface")
	t.eq(abyss.eff_power, 3, "high tide leaves the abyss alone")

	game.tide = GameEnums.Tide.LOW
	game.refresh_continuous()
	t.eq(surface.eff_power, 3, "low tide drops the surface back")
	t.eq(abyss.eff_power, 4, "low tide lifts the abyss")


static func _test_keywords(t: TestFramework) -> void:
	t.start("keywords")
	var game := TestHelpers.new_game()
	game.tide = GameEnums.Tide.HIGH

	# Pressure: a bonus in the Abyss, a penalty at the Surface.
	var crawler := TestHelpers.put_in_play(game, "vent_crawler", 0, GameEnums.Depth.ABYSS)
	game.refresh_continuous()
	t.eq(crawler.eff_power, 3, "pressure pays off in the abyss")
	game.set_depth(crawler, int(GameEnums.Depth.SURFACE), true)
	game.refresh_continuous()
	t.eq(crawler.eff_power, 1, "pressure hurts at the surface (with the tide)")

	# Swarm counts friends in the same band.
	var marshal := TestHelpers.put_in_play(game, "shoal_marshal", 1, GameEnums.Depth.SURFACE)
	game.refresh_continuous()
	var alone := marshal.eff_power
	TestHelpers.put_in_play(game, "coral_guardian", 1, GameEnums.Depth.SURFACE)
	TestHelpers.put_in_play(game, "coral_guardian", 1, GameEnums.Depth.SURFACE)
	game.refresh_continuous()
	t.eq(marshal.eff_power, alone + 2, "swarm counts two companions")

	# Molt absorbs one lethal blow per turn.
	var molter := TestHelpers.put_in_play(game, "vent_crawler", 0, GameEnums.Depth.ABYSS)
	game.refresh_continuous()
	game.deal_damage_to_permanent(molter, 99)
	game.check_state_based_actions()
	t.eq(molter.zone, GameEnums.Zone.BATTLEFIELD, "molt survives the first lethal hit")
	t.check(molter.molt_spent, "molt is spent")
	game.deal_damage_to_permanent(molter, 99)
	game.check_state_based_actions()
	t.eq(molter.zone, GameEnums.Zone.GRAVEYARD, "molt does not save it twice")

	# Frenzy grows with every spell cast this turn.
	var shark := TestHelpers.put_in_play(game, "frenzied_shark", 0, GameEnums.Depth.MIDWATER)
	game.spells_cast_this_turn[0] = 3
	game.refresh_continuous()
	t.eq(shark.eff_power, shark.data.power + 3, "frenzy counts spells cast")


static func _test_wreck_and_salvage(t: TestFramework) -> void:
	t.start("wreck")
	var game := TestHelpers.new_game()
	t.eq(game.wreck_size(), 0, "wreck starts empty")

	var mine := TestHelpers.put_in_play(game, "coral_grazer", 0)
	var theirs := TestHelpers.put_in_play(game, "coral_grazer", 1)
	game.destroy_permanent(mine)
	game.destroy_permanent(theirs)
	t.eq(game.wreck_size(), 2, "both players' dead share one wreck")

	# Salvage spends from the shared pile, whoever owned the cards.
	t.check(game.can_salvage(2), "salvage is affordable")
	t.check(game.pay_salvage(0, 2), "salvage paid")
	t.eq(game.wreck_size(), 0, "salvage exiled the cards")
	t.check(not game.can_salvage(1), "an empty wreck pays nothing")


static func _test_stack(t: TestFramework) -> void:
	t.start("stack and priority")
	var game := TestHelpers.new_game("abyssal_conclave", "corsair_fleet")
	TestHelpers.advance_to_step(game, GameEnums.Step.PRECOMBAT_MAIN)

	TestHelpers.give_lands(game, 0, "sunless_trench", 6)
	var target := TestHelpers.put_in_play(game, "coral_grazer", 1)
	var spell := TestHelpers.put_in_hand(game, "whirlpool", 0)

	var actions := game.get_legal_actions(0)
	var cast_action: GameAction = null
	for action in actions:
		if action.kind == GameAction.Kind.CAST_SPELL and action.card_uid == spell.uid:
			cast_action = action
			break
	t.check(cast_action != null, "whirlpool is castable with lands untapped")
	if cast_action != null:
		t.check(game.perform(cast_action), "spell cast")
		t.eq(game.stack.size(), 1, "spell waits on the stack")
		t.eq(game.priority_player_index, 0, "caster keeps priority")
		TestHelpers.resolve_stack(game)
		t.eq(target.zone, GameEnums.Zone.HAND, "whirlpool returned the creature")

	# A spell whose only target is gone does not resolve.
	var doomed := TestHelpers.put_in_play(game, "coral_grazer", 1)
	var second := TestHelpers.put_in_hand(game, "whirlpool", 0)
	var fizzle_action := GameAction.cast_spell(0, second.uid, [GameAction.card_target(doomed.uid)])
	if game.perform(fizzle_action):
		game.move_to_zone(doomed, GameEnums.Zone.GRAVEYARD, "test removal")
		TestHelpers.resolve_stack(game)
		t.eq(second.zone, GameEnums.Zone.GRAVEYARD, "fizzled spell goes to the wreck")


static func _test_combat_damage(t: TestFramework) -> void:
	t.start("combat")
	var game := TestHelpers.new_game()

	# Venomous makes any damage lethal.
	var venomous := TestHelpers.put_in_play(game, "barnacle_horror", 0, GameEnums.Depth.ABYSS)
	var big := TestHelpers.put_in_play(game, "ancient_leviathan", 1, GameEnums.Depth.ABYSS)
	game.refresh_continuous()
	game.deal_damage_to_permanent(big, 1, venomous, true)
	game.check_state_based_actions()
	t.eq(big.zone, GameEnums.Zone.GRAVEYARD, "venomous kills whatever it touches")

	# Siphon gains its controller life.
	var before := game.get_player(1).life
	var siphon := TestHelpers.put_in_play(game, "reef_warden", 1, GameEnums.Depth.SURFACE)
	game.deal_damage_to_player(0, 3, siphon, true)
	t.eq(game.get_player(1).life, before + 3, "siphon gains life equal to damage")

	# Breach spills past a blocker; without it the damage stops.
	var trampler := TestHelpers.put_in_play(game, "boarding_party", 0, GameEnums.Depth.SURFACE)
	var chump := TestHelpers.put_in_play(game, "coral_guardian", 1, GameEnums.Depth.SURFACE)
	game.refresh_continuous()
	trampler.attacking = true
	trampler.attack_target = 1
	trampler.blocked_by = [chump.uid] as Array[int]
	trampler.was_blocked = true
	chump.blocking = [trampler.uid] as Array[int]
	var life_before := game.get_player(1).life
	Combat.deal_combat_damage(game, false)
	t.check(game.get_player(1).life < life_before, "breach carries damage through")


static func _test_champion(t: TestFramework) -> void:
	t.start("champions")
	var game := TestHelpers.new_game()
	var champion := TestHelpers.put_in_play(game, "captain_kai_the_last_sailor", 0)
	t.check(champion != null, "champion enters play")
	if champion == null:
		return
	t.eq(champion.fathom_count(), champion.data.fathom, "champion arrives with fathom")

	# Damage comes off the fathom counters rather than marking damage.
	game.deal_damage_to_permanent(champion, 2)
	t.eq(champion.fathom_count(), champion.data.fathom - 2, "damage removes fathom")
	game.deal_damage_to_permanent(champion, 99)
	game.check_state_based_actions()
	t.eq(champion.zone, GameEnums.Zone.GRAVEYARD, "a spent champion dies")

	# Only one copy of a Champion stays on the battlefield.
	var first := TestHelpers.put_in_play(game, "orca_warden_of_the_heart", 1)
	var second := TestHelpers.put_in_play(game, "orca_warden_of_the_heart", 1)
	game.check_state_based_actions()
	var survivors := 0
	for uid in game.get_player(1).battlefield:
		var c := game.get_card(uid)
		if c != null and c.data.id == &"orca_warden_of_the_heart":
			survivors += 1
	t.eq(survivors, 1, "uniqueness rule keeps one copy")


static func _test_dice(t: TestFramework) -> void:
	t.start("dice")
	var game := TestHelpers.new_game()
	for _i in 30:
		var roll := game.roll_dice(0, 6)
		t.check(roll >= 1 and roll <= 6, "d6 stays in range")

	# Dice bonuses from permanents stack onto every roll.
	TestHelpers.put_in_play(game, "loaded_dice", 0)
	t.eq(game.dice_bonus_for(0), 2, "loaded dice adds its bonus")
	var boosted := game.roll_dice(0, 6)
	t.check(boosted >= 3 and boosted <= 8, "bonus applies to the roll")


static func _test_rewind(t: TestFramework) -> void:
	t.start("rewind")
	var game := TestHelpers.new_game()
	TestHelpers.advance_to_step(game, GameEnums.Step.PRECOMBAT_MAIN)

	var snapshot := game.capture_snapshot()
	var life_before := game.get_player(1).life
	var hand_before := game.get_player(0).hand.size()

	game.lose_life(1, 5)
	game.draw_cards(0, 2)
	var summoned := TestHelpers.put_in_play(game, "coral_grazer", 0)
	t.ne(game.get_player(1).life, life_before, "state changed before the rewind")

	game.restore_snapshot(snapshot)
	t.eq(game.get_player(1).life, life_before, "rewind restores life")
	t.eq(game.get_player(0).hand.size(), hand_before, "rewind restores the hand")
	t.check(not game.cards.has(summoned.uid), "rewind removes objects created afterwards")


static func _test_clock(t: TestFramework) -> void:
	t.start("clock")
	var blitz := TestHelpers.new_game("corsair_fleet", "leviathan_brood", 99, MatchRules.blitz())
	t.eq(blitz.turn_time_limit(0), 20.0, "blitz gives twenty seconds")

	# A permanent can squeeze the opponent's clock, and releases it when it
	# leaves the battlefield.
	var deadline := TestHelpers.put_in_play(blitz, "crushing_deadline", 0)
	t.eq(blitz.turn_time_limit(1), 8.0, "crushing deadline shortens their turns")
	t.eq(blitz.turn_time_limit(0), 20.0, "and leaves yours alone")
	blitz.move_to_zone(deadline, GameEnums.Zone.GRAVEYARD, "test")
	t.eq(blitz.turn_time_limit(1), 20.0, "removing it restores the clock")

	# Running out of time in Riptide costs life.
	var riptide := TestHelpers.new_game("corsair_fleet", "leviathan_brood", 99, MatchRules.riptide())
	TestHelpers.advance_to_step(riptide, GameEnums.Step.PRECOMBAT_MAIN)
	var life_before := riptide.get_player(0).life
	riptide.handle_timeout(0)
	t.check(riptide.get_player(0).life < life_before, "riptide timeout costs life")

	# In Castaway an empty clock loses the game outright.
	var castaway := TestHelpers.new_game("corsair_fleet", "leviathan_brood", 99, MatchRules.castaway())
	castaway.handle_timeout(1)
	t.check(castaway.get_player(1).has_lost, "castaway timeout loses the game")


static func _test_multiplayer(t: TestFramework) -> void:
	t.start("multiplayer")
	var game := Game.new()
	game.setup(
		["A", "B", "C", "D"],
		[Cards.build_deck("corsair_fleet"), Cards.build_deck("coral_concord"),
		 Cards.build_deck("the_drowned"), Cards.build_deck("abyssal_conclave")],
		777, [false, false, false, false], MatchRules.standard(), [],
		[0, 1, 0, 1]  # Two teams of two.
	)
	while game.awaiting == "mulligan":
		game.perform(GameAction.keep_hand(game.awaiting_player()))

	t.eq(game.players.size(), 4, "four players seated")
	t.check(game.are_allies(0, 2), "teammates recognised")
	t.check(not game.are_allies(0, 1), "opponents recognised")
	t.eq(game.opponents_of(0).size(), 2, "two opponents across the table")
	t.eq(game.teammates_of(0).size(), 1, "one ally")

	# A team only loses once both members are out.
	game._player_loses(1, "test")
	t.check(not game.is_over(), "game continues while one team member lives")
	game._player_loses(3, "test")
	t.check(game.is_over(), "game ends when a whole team is out")
	t.eq(game.winning_team, 0, "the surviving team wins")
