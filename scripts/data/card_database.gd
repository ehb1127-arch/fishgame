## Autoload singleton "Cards": loads every card definition from data/cards.
##
## Cards live in JSON so that adding or balancing one never means touching
## GDScript. See docs/card_schema.md.
extends Node

var _cards: Dictionary = {}
var _decks: Dictionary = {}

const SET_DIR := "res://data/sets"
const DECK_DIR := "res://data/decks"
const STORY_DIR := "res://data/story"


func _ready() -> void:
	load_all()


var _sets: Dictionary = {}
var _story: Dictionary = {}


func load_all() -> void:
	_cards.clear()
	_decks.clear()
	_sets.clear()
	_story.clear()
	_load_sets()
	_load_dir(DECK_DIR, _ingest_deck_file)
	_load_dir(STORY_DIR, _ingest_story_file)
	print("[Cards] %d cards across %d sets, %d decks, %d story arcs" % [
		_cards.size(), _sets.size(), _decks.size(), _story.size()])


## Each set is a folder under data/sets with a set.json and a cards/ folder.
func _load_sets() -> void:
	var root := DirAccess.open(SET_DIR)
	if root == null:
		push_error("Cannot open %s" % SET_DIR)
		return
	for set_name in root.get_directories():
		var set_path := SET_DIR.path_join(set_name)
		var meta: Variant = _read_json(set_path.path_join("set.json"))
		if meta is Dictionary:
			_sets[set_name] = meta
		_load_dir(set_path.path_join("cards"), func(path: String) -> void:
			_ingest_card_file(path, set_name))


func _ingest_story_file(path: String) -> void:
	var parsed: Variant = _read_json(path)
	if parsed is Dictionary:
		var arc := parsed as Dictionary
		_story[str(arc.get("id", path.get_file().get_basename()))] = arc


func set_ids() -> Array:
	return _sets.keys()

func get_set(set_id: String) -> Dictionary:
	return _sets.get(set_id, {}) as Dictionary

func story_ids() -> Array:
	return _story.keys()

func get_story(arc_id: String) -> Dictionary:
	return _story.get(arc_id, {}) as Dictionary


func _load_dir(path: String, ingest: Callable) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("Cannot open %s" % path)
		return
	for file_name in dir.get_files():
		# Exported projects rename .json to .json.remap in some setups.
		var clean := file_name.replace(".remap", "")
		if not clean.ends_with(".json"):
			continue
		ingest.call(path.path_join(clean))


func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Empty or missing file: %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("Invalid JSON: %s" % path)
	return parsed


func _ingest_card_file(path: String, set_name: String = "") -> void:
	var parsed: Variant = _read_json(path)
	if not (parsed is Array):
		return
	for entry in parsed as Array:
		if not (entry is Dictionary):
			continue
		var d := entry as Dictionary
		if not set_name.is_empty() and not d.has("set"):
			d["set"] = set_name
		var card := CardData.from_dict(d)
		if _cards.has(card.id):
			push_warning("Duplicate card id: %s" % card.id)
		_cards[card.id] = card


func _ingest_deck_file(path: String) -> void:
	var parsed: Variant = _read_json(path)
	if not (parsed is Dictionary):
		return
	var deck := parsed as Dictionary
	var id := str(deck.get("id", path.get_file().get_basename()))
	_decks[id] = deck


## --- Queries -------------------------------------------------------------

func get_card(id: Variant) -> CardData:
	return _cards.get(StringName(str(id)), null)

func has_card(id: Variant) -> bool:
	return _cards.has(StringName(str(id)))

func all_cards() -> Array:
	return _cards.values()

## Every card matching a filter, used by the shop, the collection screen, and
## the Voyage reward roller.
func cards_where(predicate: Callable) -> Array:
	var out: Array = []
	for card in _cards.values():
		if predicate.call(card):
			out.append(card)
	return out

func cards_of_rarity(rarity: GameEnums.Rarity) -> Array:
	return cards_where(func(c: CardData) -> bool: return c.rarity == rarity)

func cards_of_faction(faction: String) -> Array:
	return cards_where(func(c: CardData) -> bool: return c.faction == faction)

## Cards that can appear as rewards: tokens and basic lands are excluded.
func collectible_cards() -> Array:
	return cards_where(func(c: CardData) -> bool:
		return not c.is_basic_land() and not c.id.begins_with(&"token_"))

func deck_ids() -> Array:
	return _decks.keys()

func get_deck_definition(deck_id: String) -> Dictionary:
	return _decks.get(deck_id, {}) as Dictionary


## Expands a deck definition into {"main": [CardData...], "vault": [...]},
## which is the shape Game.setup takes.
func build_deck(deck_id: String) -> Dictionary:
	var deck := get_deck_definition(deck_id)
	if deck.is_empty():
		push_error("Unknown deck: %s" % deck_id)
		return {"main": [], "vault": []}
	return {
		"main": _expand(deck.get("cards", []) as Array, deck_id),
		"vault": _expand(deck.get("vault", []) as Array, deck_id),
	}


## Just the shuffled pile, for callers that do not care about the vault.
func build_main_deck(deck_id: String) -> Array:
	return build_deck(deck_id)["main"] as Array


func _expand(entries: Array, deck_id: String) -> Array:
	var out: Array = []
	for entry in entries:
		var e := entry as Dictionary
		var card := get_card(str(e.get("id", "")))
		if card == null:
			push_warning("Deck %s references unknown card %s" % [deck_id, e.get("id", "")])
			continue
		for _i in int(e.get("count", 1)):
			out.append(card)
	return out


## Builds a deck from an explicit card list, used by the collection screen and
## by Voyage runs where the player's deck changes between stages.
func build_from_list(card_ids: Array, vault_ids: Array = []) -> Dictionary:
	var main: Array = []
	for id in card_ids:
		var card := get_card(str(id))
		if card != null:
			main.append(card)
	var vault: Array = []
	for id in vault_ids:
		var card := get_card(str(id))
		if card != null:
			vault.append(card)
	return {"main": main, "vault": vault}


func deck_name(deck_id: String) -> String:
	return str(get_deck_definition(deck_id).get("name", deck_id))
