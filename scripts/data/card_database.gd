## Autoload singleton "Cards": loads every card definition from data/cards.
##
## Cards live in JSON so that adding or balancing one never means touching
## GDScript. See docs/card_schema.md.
extends Node

var _cards: Dictionary = {}
var _decks: Dictionary = {}

const CARD_DIR := "res://data/cards"
const DECK_DIR := "res://data/decks"


func _ready() -> void:
	load_all()


func load_all() -> void:
	_cards.clear()
	_decks.clear()
	_load_dir(CARD_DIR, _ingest_card_file)
	_load_dir(DECK_DIR, _ingest_deck_file)
	print("[Cards] loaded %d cards, %d decks" % [_cards.size(), _decks.size()])


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


func _ingest_card_file(path: String) -> void:
	var parsed: Variant = _read_json(path)
	if not (parsed is Array):
		return
	for entry in parsed as Array:
		if not (entry is Dictionary):
			continue
		var card := CardData.from_dict(entry as Dictionary)
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

func deck_ids() -> Array:
	return _decks.keys()

func get_deck_definition(deck_id: String) -> Dictionary:
	return _decks.get(deck_id, {}) as Dictionary


## Expands a deck definition into the full list of CardData to shuffle.
func build_deck(deck_id: String) -> Array:
	var out: Array = []
	var deck := get_deck_definition(deck_id)
	if deck.is_empty():
		push_error("Unknown deck: %s" % deck_id)
		return out
	for entry in deck.get("cards", []) as Array:
		var e := entry as Dictionary
		var card := get_card(str(e.get("id", "")))
		if card == null:
			push_warning("Deck %s references unknown card %s" % [deck_id, e.get("id", "")])
			continue
		for _i in int(e.get("count", 1)):
			out.append(card)
	return out


func deck_name(deck_id: String) -> String:
	return str(get_deck_definition(deck_id).get("name", deck_id))
