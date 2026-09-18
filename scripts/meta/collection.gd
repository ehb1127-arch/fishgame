## What the player owns: copies of each card, star levels, and cosmetics.
##
## Held as plain dictionaries so the whole thing serializes to JSON without a
## conversion step.
class_name Collection
extends RefCounted

## card id -> {"copies": int, "stars": int, "inscribed": int}
var cards: Dictionary = {}
## Cosmetic ids the player owns: card backs, board skins, avatars, emotes.
var cosmetics: Array[String] = []
## Which cosmetic is currently equipped, by slot.
var equipped: Dictionary = {"card_back": "default", "board": "default", "avatar": "default"}


func has_card(card_id: String) -> bool:
	return cards.has(card_id)

func copies_of(card_id: String) -> int:
	return int((cards.get(card_id, {}) as Dictionary).get("copies", 0))

func stars_of(card_id: String) -> int:
	return int((cards.get(card_id, {}) as Dictionary).get("stars", GameEnums.MIN_STARS))

func inscribed_copies(card_id: String) -> int:
	return int((cards.get(card_id, {}) as Dictionary).get("inscribed", 0))


## Adds a card. Copies beyond the deck limit are dust instead, which is
## returned so the caller can show "+45 dust" on the reward screen.
func add_card(card: CardData, inscribed: bool = false) -> Dictionary:
	var id := str(card.id)
	if not cards.has(id):
		cards[id] = {"copies": 0, "stars": GameEnums.MIN_STARS, "inscribed": 0}
	var entry := cards[id] as Dictionary

	if inscribed:
		entry["inscribed"] = int(entry["inscribed"]) + 1

	# Copies you can still use for upgrades are kept; the rest become dust.
	var useful_cap := _useful_copy_cap(card.rarity)
	if int(entry["copies"]) < useful_cap:
		entry["copies"] = int(entry["copies"]) + 1
		return {"new": int(entry["copies"]) == 1, "dust": 0, "inscribed": inscribed}

	var dust := Currency.dust_for_duplicate(card.rarity)
	return {"new": false, "dust": dust, "inscribed": inscribed}


## The most copies that could ever be spent: one playset plus everything the
## upgrade path consumes.
func _useful_copy_cap(rarity: GameEnums.Rarity) -> int:
	return GameEnums.deck_limit_for(rarity) + int(Currency.total_upgrade_cost(rarity)["copies"])


## --- Upgrading -----------------------------------------------------------

## Can this card go up a star right now?
func can_upgrade(card: CardData, dust_available: int) -> bool:
	var stars := stars_of(str(card.id))
	if stars >= GameEnums.MAX_STARS:
		return false
	var cost := Currency.upgrade_cost(card.rarity, stars)
	if cost.is_empty():
		return false
	# Upgrading consumes duplicates on top of the playset you keep.
	var spare := copies_of(str(card.id)) - 1
	return spare >= int(cost["copies"]) and dust_available >= int(cost["dust"])


## Spends the copies and returns the dust cost, or -1 when it cannot be done.
func upgrade(card: CardData, dust_available: int) -> int:
	if not can_upgrade(card, dust_available):
		return -1
	var id := str(card.id)
	var stars := stars_of(id)
	var cost := Currency.upgrade_cost(card.rarity, stars)
	var entry := cards[id] as Dictionary
	entry["copies"] = int(entry["copies"]) - int(cost["copies"])
	entry["stars"] = stars + 1
	return int(cost["dust"])


## Star levels keyed by card id, in the shape Game.setup takes.
func star_map() -> Dictionary:
	var out := {}
	for id in cards:
		out[id] = int((cards[id] as Dictionary).get("stars", GameEnums.MIN_STARS))
	return out


## --- Deck legality -------------------------------------------------------

## Checks a deck list against ownership and rarity limits.
## Returns an empty array when the deck is legal, or the problems found.
func validate_deck(card_ids: Array, required_size: int = 40) -> Array[String]:
	var problems: Array[String] = []
	var counts := {}
	for id in card_ids:
		counts[str(id)] = int(counts.get(str(id), 0)) + 1

	if card_ids.size() != required_size:
		problems.append("Deck has %d cards, needs %d" % [card_ids.size(), required_size])

	for id in counts:
		var card: CardData = Cards.get_card(id)
		if card == null:
			problems.append("Unknown card: %s" % id)
			continue
		var used := int(counts[id])
		if card.is_basic_land():
			continue  # Basic lands are unlimited.
		var limit := card.deck_limit()
		if used > limit:
			problems.append("%s: %d copies, limit is %d" % [card.name, used, limit])
		if copies_of(str(id)) < used:
			problems.append("%s: you own %d, deck uses %d" % [card.name, copies_of(str(id)), used])
	return problems


## --- Cosmetics -----------------------------------------------------------

func owns_cosmetic(cosmetic_id: String) -> bool:
	return cosmetic_id in cosmetics or cosmetic_id == "default"

func grant_cosmetic(cosmetic_id: String) -> bool:
	if owns_cosmetic(cosmetic_id):
		return false
	cosmetics.append(cosmetic_id)
	return true

func equip(slot: String, cosmetic_id: String) -> bool:
	if not owns_cosmetic(cosmetic_id):
		return false
	equipped[slot] = cosmetic_id
	return true


## --- Progress ------------------------------------------------------------

## Fraction of the collectible pool owned, for the collection screen and for
## Codex unlocks that ask you to gather a faction.
func completion() -> Dictionary:
	var total := 0
	var owned := 0
	var by_faction := {}
	for card in Cards.collectible_cards():
		var c := card as CardData
		total += 1
		var faction_row := by_faction.get(c.faction, {"total": 0, "owned": 0}) as Dictionary
		faction_row["total"] = int(faction_row["total"]) + 1
		if has_card(str(c.id)):
			owned += 1
			faction_row["owned"] = int(faction_row["owned"]) + 1
		by_faction[c.faction] = faction_row
	return {"total": total, "owned": owned, "by_faction": by_faction}


## --- Serialization -------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"cards": cards.duplicate(true),
		"cosmetics": cosmetics.duplicate(),
		"equipped": equipped.duplicate(),
	}


static func from_dict(d: Dictionary) -> Collection:
	var c := Collection.new()
	c.cards = (d.get("cards", {}) as Dictionary).duplicate(true)
	for id in d.get("cosmetics", []) as Array:
		c.cosmetics.append(str(id))
	c.equipped = (d.get("equipped", {}) as Dictionary).duplicate()
	if c.equipped.is_empty():
		c.equipped = {"card_back": "default", "board": "default", "avatar": "default"}
	return c
