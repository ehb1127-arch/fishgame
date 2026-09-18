## Meta layer tests: pack odds, collection, upgrades, rating, shop, Voyage.
class_name TestMeta
extends RefCounted


static func run(t: TestFramework) -> void:
	_test_odds(t)
	_test_collection(t)
	_test_rating(t)
	_test_shop(t)
	_test_voyage(t)


static func _test_odds(t: TestFramework) -> void:
	t.start("pack odds")
	t.check(PackOdds.tables_are_valid(), "every slot table sums to one")
	t.check(Voyage.odds_are_valid(), "every voyage reward row sums to one")

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pity := PackOdds.new_pity()
	var counts := {}
	var packs := 4000
	for _i in packs:
		for entry in PackOdds.roll_pack(rng, pity):
			var rarity: GameEnums.Rarity = (entry as Dictionary)["rarity"]
			counts[rarity] = int(counts.get(rarity, 0)) + 1

	t.eq(int(counts.get(GameEnums.Rarity.DRIFTWOOD, 0)) > 0, true, "driftwood appears")

	# The rare slot is one card per pack, so Gold should land near its rate.
	var gold_rate := float(counts.get(GameEnums.Rarity.GOLD, 0)) / float(packs)
	t.approx(gold_rate, PackOdds.SLOT_RARE[GameEnums.Rarity.GOLD], 0.03,
		"gold rate matches the published odds")

	# Pity has to guarantee something, so Leviathan cannot be absent over a
	# run this long.
	t.gt(float(counts.get(GameEnums.Rarity.LEVIATHAN, 0)), 0.0,
		"leviathan shows up within the pity window")

	# The disclosure table must describe the same numbers the roller used.
	var rows := PackOdds.disclosure_rows()
	t.gt(float(rows.size()), 5.0, "disclosure covers every rarity")
	for row in rows:
		var chance := float((row as Dictionary)["per_pack"])
		t.check(chance >= 0.0 and chance <= 1.0, "disclosed chance is a probability")


static func _test_collection(t: TestFramework) -> void:
	t.start("collection")
	var collection := Collection.new()
	var card: CardData = Cards.get_card("powder_monkey")
	t.check(card != null, "test card exists")
	if card == null:
		return

	var first := collection.add_card(card)
	t.check(bool(first["new"]), "first copy is new")
	t.eq(collection.copies_of("powder_monkey"), 1, "one copy held")
	t.eq(collection.stars_of("powder_monkey"), GameEnums.MIN_STARS, "starts at one star")

	# Copies past the useful cap turn into dust instead of piling up.
	var dust_seen := 0
	for _i in 40:
		var outcome := collection.add_card(card)
		dust_seen += int(outcome["dust"])
	t.gt(float(dust_seen), 0.0, "excess copies become dust")

	# Upgrading spends duplicates and dust, and stops at five stars.
	var upgrades := 0
	for _i in 10:
		if not collection.can_upgrade(card, 100000):
			break
		collection.upgrade(card, 100000)
		upgrades += 1
	t.eq(collection.stars_of("powder_monkey"), GameEnums.MAX_STARS, "reaches five stars")
	t.check(not collection.can_upgrade(card, 100000), "cannot upgrade past the cap")

	# A five-star creature is stronger than a fresh one.
	var plain := CardInstance.create(1, card, 0, 1)
	var upgraded := CardInstance.create(2, card, 0, 5)
	t.gt(float(upgraded.eff_power + upgraded.eff_toughness),
		float(plain.eff_power + plain.eff_toughness), "stars add stats")

	# Milestone keywords arrive at the printed star level.
	var shark: CardData = Cards.get_card("frenzied_shark")
	if shark != null:
		var early := CardInstance.create(3, shark, 0, 1)
		var late := CardInstance.create(4, shark, 0, 5)
		t.check(not early.has_keyword(GameEnums.KW_SURGING), "no milestone keyword at one star")
		t.check(late.has_keyword(GameEnums.KW_SURGING), "milestone keyword at five stars")

	# Deck legality respects rarity limits and what you actually own.
	var fresh := Collection.new()
	var relic: CardData = Cards.get_card("the_hundredth_life")
	if relic != null:
		fresh.add_card(relic)
		var problems := fresh.validate_deck([str(relic.id), str(relic.id)], 2)
		t.gt(float(problems.size()), 0.0, "two copies of a relic is illegal")


static func _test_rating(t: TestFramework) -> void:
	t.start("rating")
	t.approx(Rating.expected_score(1200, 1200), 0.5, 0.001, "even match is a coin flip")
	t.gt(Rating.expected_score(1600, 1200), 0.8, "the favourite is favoured")

	var winner := Rating.updated(1200, 1200, 1.0, 100)
	var loser := Rating.updated(1200, 1200, 0.0, 100)
	t.gt(float(winner), 1200.0, "winning gains rating")
	t.check(loser < 1200, "losing costs rating")
	t.eq(winner - 1200, 1200 - loser, "an even match is symmetric")

	# Placement games move faster.
	var placement := Rating.updated(1200, 1200, 1.0, 0)
	t.gt(float(placement - 1200), float(winner - 1200), "placement games swing harder")

	# Beating someone far below you is worth very little.
	var upset := Rating.updated(1800, 1000, 1.0, 100)
	t.check(upset - 1800 <= 2, "beating a much weaker player barely moves you")

	t.eq(Rating.tier_name(1200), "Diver", "tier lookup")
	t.eq(Rating.tier_name(1850), "Leviathan", "top tier")
	t.eq(Rating.to_next_tier(1850), 0, "no tier beyond the top")


static func _test_shop(t: TestFramework) -> void:
	t.start("shop")
	var items := Shop.catalogue()
	t.gt(float(items.size()), 5.0, "catalogue has items")

	# The design rule: gems never buy a card that coins cannot.
	for item in items:
		var entry := item as Dictionary
		var category := int(entry["category"])
		if category == Shop.Category.DECK:
			t.check(Shop.is_purchasable_with(entry, Currency.Kind.PEARL_COIN),
				"%s is buyable with coins" % entry["id"])
		if category == Shop.Category.PACK:
			t.check(Shop.is_purchasable_with(entry, Currency.Kind.PEARL_COIN),
				"packs are buyable with coins")
		if category == Shop.Category.COSMETIC:
			t.check(not Shop.is_purchasable_with(entry, Currency.Kind.PEARL_COIN),
				"cosmetics are the gem-only side")

	t.gt(float(Shop.match_reward(true, true)), float(Shop.match_reward(true, false)),
		"the first win of the day pays extra")
	t.gt(float(Shop.match_reward(true, false)), float(Shop.match_reward(false, false)),
		"winning pays more than losing")


static func _test_voyage(t: TestFramework) -> void:
	t.start("voyage")
	var run := Voyage.start("corsair_fleet", 31337)
	t.eq(run.deck_ids.size(), 40, "run starts with the chosen deck")
	t.gt(float(run.total_stages()), 5.0, "the descent has stages")

	var stage := run.current_stage()
	t.check(not stage.is_empty(), "first stage exists")
	t.eq(int(stage["depth"]), 0, "starts in the first region")

	# Winning offers rewards and moves you on; the deck grows.
	var before := run.deck_ids.size()
	var result := run.finish_stage(true, 20)
	t.check(bool(result["won"]), "stage recorded as a win")
	t.eq((result["rewards"] as Array).size(), Voyage.REWARD_CHOICES, "three cards offered")
	run.take_reward(0)
	t.eq(run.deck_ids.size(), before + 1, "the reward joined the deck")
	t.eq(run.stages_cleared, 1, "progress recorded")

	# Life carries over and heals only partly.
	t.check(run.life <= run.max_life, "healing is capped")
	t.gt(float(run.life), 20.0, "some healing happened")

	# Losing ends the run.
	var loss := run.finish_stage(false, 0)
	t.check(bool(loss["run_complete"]), "a loss ends the run")
	t.check(run.finished, "run marked finished")

	# A run survives being saved and reloaded.
	var restored := Voyage.from_dict(run.to_dict())
	t.eq(restored.deck_ids.size(), run.deck_ids.size(), "deck survives the round trip")
	t.eq(restored.stages_cleared, run.stages_cleared, "progress survives the round trip")
