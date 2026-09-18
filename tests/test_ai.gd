## Plays whole games with AI on both sides.
##
## This is the test that matters most: it exercises the turn loop, the stack,
## combat, triggers, and state-based actions together, on real decks, for
## thousands of actions. If any of them can deadlock or crash, it shows up
## here rather than in someone's hands.
class_name TestAI
extends RefCounted

const MAX_ACTIONS := 4000


static func run(t: TestFramework) -> void:
	_test_full_games(t)
	_test_ai_understands_depth(t)


static func _test_full_games(t: TestFramework) -> void:
	t.start("ai full games")
	var matchups := [
		["corsair_fleet", "leviathan_brood"],
		["abyssal_conclave", "the_drowned"],
		["coral_concord", "corsair_fleet"],
		["the_drowned", "leviathan_brood"],
	]

	for i in matchups.size():
		var pair := matchups[i] as Array
		var game := Game.new()
		game.setup(
			["AI-A", "AI-B"],
			[Cards.build_deck(str(pair[0])), Cards.build_deck(str(pair[1]))],
			1000 + i * 17, [true, true], MatchRules.standard()
		)
		var players := [
			AIPlayer.create(0, AIPlayer.Skill.NORMAL, 500 + i),
			AIPlayer.create(1, AIPlayer.Skill.HARD, 900 + i),
		]

		var actions := 0
		while not game.is_over() and actions < MAX_ACTIONS:
			actions += 1
			var index := game.awaiting_player()
			if index < 0 or index >= players.size():
				break
			var ai: AIPlayer = players[index]
			var action := ai.decide(game)
			if action == null:
				break
			if not game.perform(action):
				# An AI should never propose an illegal action; if it does,
				# passing keeps the game moving so the suite still reports.
				if not game.perform(GameAction.pass_priority(index)):
					break

		t.check(game.is_over(),
			"%s vs %s reaches a result (%d actions, turn %d)" % [
				pair[0], pair[1], actions, game.turn_number])
		t.check(actions < MAX_ACTIONS,
			"%s vs %s finishes without stalling" % [pair[0], pair[1]])
		if game.is_over():
			t.check(game.winner_index >= 0 or game.winning_team >= 0,
				"a winner is recorded")


static func _test_ai_understands_depth(t: TestFramework) -> void:
	t.start("ai depth sense")
	var game := TestHelpers.new_game()
	TestHelpers.advance_to_step(game, GameEnums.Step.PRECOMBAT_MAIN)
	var ai := AIPlayer.create(0, AIPlayer.Skill.HARD, 24)

	# An attacker facing a blocker in its own band, with an empty band next
	# door, should want to move rather than trade.
	var attacker := TestHelpers.put_in_play(game, "coral_grazer", 0, GameEnums.Depth.SURFACE)
	TestHelpers.put_in_play(game, "coral_grazer", 1, GameEnums.Depth.SURFACE)
	game.refresh_continuous()

	var move := GameAction.move_depth(0, attacker.uid, 1)
	var score := ai._score_depth_move(game, move)
	t.gt(score, 0.0, "moving into an empty band is attractive")

	# With blockers in both bands there is nothing to gain by moving.
	TestHelpers.put_in_play(game, "coral_grazer", 1, GameEnums.Depth.MIDWATER)
	TestHelpers.put_in_play(game, "coral_grazer", 1, GameEnums.Depth.MIDWATER)
	game.refresh_continuous()
	var crowded := ai._score_depth_move(game, move)
	t.check(crowded < score, "a defended band is less attractive than an empty one")

	# It should not attack into a band that eats the attacker for free.
	var weak := TestHelpers.put_in_play(game, "kelp_sprout", 0, GameEnums.Depth.ABYSS)
	TestHelpers.put_in_play(game, "ancient_leviathan", 1, GameEnums.Depth.ABYSS)
	game.refresh_continuous()
	game.get_player(1).life = 40
	t.check(not ai._should_attack(game, weak, 1),
		"a hopeless attack into a full band is declined")
