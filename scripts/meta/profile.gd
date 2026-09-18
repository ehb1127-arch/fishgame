## Autoload singleton "Player": the save file and everything in it.
##
## Holds currencies, the collection, rating, pity counters, Codex progress,
## and the current Voyage. Saves to user:// as JSON.
extends Node

signal currency_changed()
signal collection_changed()
signal codex_unlocked(arc_id: String, chapter: int)

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 1

var display_name: String = "Diver"
var coins: int = 500
var dust: int = 0
var gems: int = 0

var collection: Collection = null
var pity: Dictionary = {}

var rating: int = Rating.STARTING_RATING
var games_played: int = 0
var wins: int = 0
var losses: int = 0

## arc id -> highest chapter unlocked.
var codex: Dictionary = {}
## Saved Voyage in progress, empty when not on one.
var voyage_state: Dictionary = {}
## Deck lists the player has built: name -> {"cards": [...], "vault": [...]}.
var decks: Dictionary = {}
var last_daily_win_day: int = -1

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	collection = Collection.new()
	pity = PackOdds.new_pity()
	if not load_profile():
		_grant_starter()


## --- Currencies ----------------------------------------------------------

func add_coins(amount: int) -> void:
	coins = maxi(0, coins + amount)
	currency_changed.emit()

func add_dust(amount: int) -> void:
	dust = maxi(0, dust + amount)
	currency_changed.emit()

func add_gems(amount: int) -> void:
	gems = maxi(0, gems + amount)
	currency_changed.emit()

func can_afford(currency: Currency.Kind, amount: int) -> bool:
	match currency:
		Currency.Kind.PEARL_COIN:
			return coins >= amount
		Currency.Kind.NACRE_DUST:
			return dust >= amount
		Currency.Kind.ABYSS_GEM:
			return gems >= amount
	return false

func spend(currency: Currency.Kind, amount: int) -> bool:
	if not can_afford(currency, amount):
		return false
	match currency:
		Currency.Kind.PEARL_COIN:
			coins -= amount
		Currency.Kind.NACRE_DUST:
			dust -= amount
		Currency.Kind.ABYSS_GEM:
			gems -= amount
	currency_changed.emit()
	return true


## --- Packs ---------------------------------------------------------------

## Opens one pack and files the results. Returns the cards drawn, each as
## {"card": CardData, "inscribed": bool, "new": bool, "dust": int}, which is
## exactly what the reveal screen needs.
func open_pack(set_id: String = "last_tide") -> Array:
	var pool_by_rarity := {}
	for card in Cards.collectible_cards():
		var c := card as CardData
		if not set_id.is_empty() and c.set_code != set_id:
			continue
		var bucket := pool_by_rarity.get(c.rarity, []) as Array
		bucket.append(c)
		pool_by_rarity[c.rarity] = bucket

	var results: Array = []
	for roll in PackOdds.roll_pack(rng, pity):
		var entry := roll as Dictionary
		var rarity: GameEnums.Rarity = entry["rarity"]
		var pool := pool_by_rarity.get(rarity, []) as Array
		# A rarity with nothing printed in it falls back to the tier below.
		var guard := 0
		while pool.is_empty() and rarity > GameEnums.Rarity.DRIFTWOOD and guard < 6:
			guard += 1
			rarity = (int(rarity) - 1) as GameEnums.Rarity
			pool = pool_by_rarity.get(rarity, []) as Array
		if pool.is_empty():
			continue
		var card: CardData = pool[rng.randi_range(0, pool.size() - 1)]
		var outcome := collection.add_card(card, bool(entry["inscribed"]))
		if int(outcome["dust"]) > 0:
			add_dust(int(outcome["dust"]))
		results.append({
			"card": card,
			"inscribed": bool(entry["inscribed"]),
			"new": bool(outcome["new"]),
			"dust": int(outcome["dust"]),
			"rarity": rarity,
		})
	collection_changed.emit()
	save_profile()
	return results


## --- Shop ----------------------------------------------------------------

## Buys a catalogue item. Returns {"ok": bool, "reason": String, "result": ...}.
func purchase(item_id: String, currency: Currency.Kind) -> Dictionary:
	var item := Shop.find_item(item_id)
	if item.is_empty():
		return {"ok": false, "reason": "No such item"}
	if not Shop.is_purchasable_with(item, currency):
		return {"ok": false, "reason": "Not sold in that currency"}
	var price := Shop.price_in(item, currency)
	if not spend(currency, price):
		return {"ok": false, "reason": "Not enough " + Currency.label(currency, true)}

	match int(item["category"]):
		Shop.Category.PACK:
			var opened: Array = []
			for _i in int(item.get("quantity", 1)):
				opened.append_array(open_pack(str(item.get("set", "last_tide"))))
			return {"ok": true, "result": opened}

		Shop.Category.DECK:
			var built := Cards.build_deck(str(item["deck"]))
			for card in (built["main"] as Array) + (built["vault"] as Array):
				var outcome := collection.add_card(card as CardData)
				if int(outcome["dust"]) > 0:
					add_dust(int(outcome["dust"]))
			decks[str(item["deck"])] = _deck_list_from(built)
			collection_changed.emit()
			save_profile()
			return {"ok": true, "result": str(item["deck"])}

		Shop.Category.COSMETIC:
			collection.grant_cosmetic(item_id)
			collection_changed.emit()
			save_profile()
			return {"ok": true, "result": item_id}

		_:
			save_profile()
			return {"ok": true, "result": item_id}


func _deck_list_from(built: Dictionary) -> Dictionary:
	var main: Array[String] = []
	for card in built["main"] as Array:
		main.append(str((card as CardData).id))
	var vault: Array[String] = []
	for card in built["vault"] as Array:
		vault.append(str((card as CardData).id))
	return {"cards": main, "vault": vault}


## --- Upgrading -----------------------------------------------------------

func upgrade_card(card_id: String) -> bool:
	var card: CardData = Cards.get_card(card_id)
	if card == null:
		return false
	var cost := collection.upgrade(card, dust)
	if cost < 0:
		return false
	add_dust(-cost)
	collection_changed.emit()
	save_profile()
	return true


## --- Match results -------------------------------------------------------

## Records a finished ranked match and pays out.
func record_match(won: bool, opponent_rating: int) -> Dictionary:
	var before := rating
	rating = Rating.updated(rating, opponent_rating, 1.0 if won else 0.0, games_played)
	games_played += 1
	if won:
		wins += 1
	else:
		losses += 1

	var today := int(Time.get_unix_time_from_system() / 86400.0)
	var first_win := won and today != last_daily_win_day
	if first_win:
		last_daily_win_day = today
	var coins_earned := Shop.match_reward(won, first_win)
	add_coins(coins_earned)
	save_profile()
	return {
		"rating_before": before, "rating_after": rating,
		"coins": coins_earned, "first_win": first_win,
		"tier": Rating.tier_name(rating, true),
	}


## --- Codex ---------------------------------------------------------------

func codex_chapter(arc_id: String) -> int:
	return int(codex.get(arc_id, 0))

func unlock_codex(arc_id: String, chapter: int) -> bool:
	if codex_chapter(arc_id) >= chapter:
		return false
	codex[arc_id] = chapter
	codex_unlocked.emit(arc_id, chapter)
	save_profile()
	return true


## --- Starter ------------------------------------------------------------

## A new player gets one full deck so they can play immediately.
func _grant_starter() -> void:
	var starter := "corsair_fleet"
	var built := Cards.build_deck(starter)
	for card in (built["main"] as Array) + (built["vault"] as Array):
		collection.add_card(card as CardData)
	decks[starter] = _deck_list_from(built)
	collection_changed.emit()
	save_profile()


## --- Save and load -------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"name": display_name,
		"coins": coins, "dust": dust, "gems": gems,
		"collection": collection.to_dict(),
		"pity": pity,
		"rating": rating, "games": games_played, "wins": wins, "losses": losses,
		"codex": codex,
		"voyage": voyage_state,
		"decks": decks,
		"daily": last_daily_win_day,
	}


func save_profile() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(to_dict(), "  "))
	file.close()


func load_profile() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("Corrupt profile, starting fresh")
		return false
	var d := parsed as Dictionary

	display_name = str(d.get("name", display_name))
	coins = int(d.get("coins", coins))
	dust = int(d.get("dust", dust))
	gems = int(d.get("gems", gems))
	collection = Collection.from_dict(d.get("collection", {}) as Dictionary)
	pity = (d.get("pity", {}) as Dictionary).duplicate()
	if pity.is_empty():
		pity = PackOdds.new_pity()
	rating = int(d.get("rating", rating))
	games_played = int(d.get("games", 0))
	wins = int(d.get("wins", 0))
	losses = int(d.get("losses", 0))
	codex = (d.get("codex", {}) as Dictionary).duplicate()
	voyage_state = (d.get("voyage", {}) as Dictionary).duplicate(true)
	decks = (d.get("decks", {}) as Dictionary).duplicate(true)
	last_daily_win_day = int(d.get("daily", -1))
	return true


## Wipes the save. Used by the settings screen and by tests.
func reset_profile() -> void:
	display_name = "Diver"
	coins = 500
	dust = 0
	gems = 0
	collection = Collection.new()
	pity = PackOdds.new_pity()
	rating = Rating.STARTING_RATING
	games_played = 0
	wins = 0
	losses = 0
	codex = {}
	voyage_state = {}
	decks = {}
	last_daily_win_day = -1
	_grant_starter()
	currency_changed.emit()
	collection_changed.emit()
