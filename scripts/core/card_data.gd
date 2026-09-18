## A card's printed, immutable definition, loaded from JSON.
##
## One CardData exists per distinct card in the set. Copies in a deck or on the
## battlefield are CardInstance objects that point back here.
class_name CardData
extends RefCounted

var id: StringName = &""
var name: String = "Unnamed"
var mana_cost_text: String = "0"
var cost: Mana.Cost = null
var types: Array[String] = []
var subtypes: Array[String] = []
var supertypes: Array[String] = []
var colors: Array[String] = []
var power: int = 0
var toughness: int = 0
var keywords: Array[String] = []
var text: String = ""
## Rules constructs, see docs/card_schema.md for the shape of each entry.
var abilities: Array = []
## The band this creature enters play in.
var native_depth: GameEnums.Depth = GameEnums.Depth.MIDWATER
## Additional cost: exile this many cards from the shared wreck to cast it.
var salvage_cost: int = 0
var rarity: GameEnums.Rarity = GameEnums.Rarity.DRIFTWOOD
## Star milestones: {"3": {"keywords": ["Venomous"]}, "5": {...}}. A creature
## can gain a whole new ability by being upgraded, which is what makes
## collecting duplicates worth doing.
var star_milestones: Dictionary = {}
## Spell numbers scale by this much per star above the first.
var star_spell_bonus: int = 0
var art: String = ""
var flavor: String = ""


static func from_dict(d: Dictionary) -> CardData:
	var card := CardData.new()
	card.id = StringName(str(d.get("id", "")))
	card.name = str(d.get("name", "Unnamed"))
	card.mana_cost_text = str(d.get("cost", "0"))
	card.cost = Mana.Cost.parse(card.mana_cost_text)
	card.types = _string_array(d.get("types", []))
	card.subtypes = _string_array(d.get("subtypes", []))
	card.supertypes = _string_array(d.get("supertypes", []))
	card.power = int(d.get("power", 0))
	card.toughness = int(d.get("toughness", 0))
	card.keywords = _string_array(d.get("keywords", []))
	card.text = str(d.get("text", ""))
	card.flavor = str(d.get("flavor", ""))
	card.art = str(d.get("art", ""))
	card.abilities = d.get("abilities", []) as Array
	card.native_depth = GameEnums.parse_depth(str(d.get("depth", "midwater")))
	card.salvage_cost = int(d.get("salvage", 0))
	card.rarity = GameEnums.parse_rarity(str(d.get("rarity", "driftwood")))
	var upgrade := d.get("upgrade", {}) as Dictionary
	card.star_milestones = upgrade.get("milestones", {}) as Dictionary
	card.star_spell_bonus = int(upgrade.get("spell_bonus_per_star", 0))

	# Colors are taken from the mana cost unless the card states them, which
	# lands and colorless artifacts need to do.
	if d.has("colors"):
		card.colors = _string_array(d["colors"])
	else:
		for sym in GameEnums.COLORS:
			if card.cost.symbols.has(sym):
				card.colors.append(sym)

	if card.id == &"":
		card.id = StringName(card.name.to_snake_case())
	return card


static func _string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(str(v))
	elif value is String and not (value as String).is_empty():
		out.append(value)
	return out


func is_type(type_name: String) -> bool:
	return type_name in types

func is_permanent() -> bool:
	for t in types:
		if t in GameEnums.PERMANENT_TYPES:
			return true
	return false

func is_creature() -> bool:
	return is_type(GameEnums.TYPE_CREATURE)

func is_land() -> bool:
	return is_type(GameEnums.TYPE_LAND)

func is_basic_land() -> bool:
	return is_land() and "Basic" in supertypes

func is_instant_speed() -> bool:
	return is_type(GameEnums.TYPE_INSTANT)

func has_keyword(keyword: String) -> bool:
	return keyword in keywords

func mana_value() -> int:
	return cost.mana_value()

## Abilities of one kind: "spell", "triggered", "activated", "static", "mana".
func abilities_of_kind(kind: String) -> Array:
	var out: Array = []
	for a in abilities:
		if a is Dictionary and str(a.get("kind", "")) == kind:
			out.append(a)
	return out

func depth_label() -> String:
	return GameEnums.depth_name(native_depth)

## Keywords this card has gained by being upgraded to [param stars].
func milestone_keywords(stars: int) -> Array[String]:
	var out: Array[String] = []
	for level in star_milestones:
		if int(str(level)) > stars:
			continue
		var entry := star_milestones[level] as Dictionary
		for kw in entry.get("keywords", []) as Array:
			if str(kw) not in out:
				out.append(str(kw))
	return out


func rarity_label() -> String:
	return GameEnums.rarity_name(rarity)

func deck_limit() -> int:
	return GameEnums.deck_limit_for(rarity)

## A Relic is unique: only one may be on the battlefield at a time, the way
## legendary permanents work.
func is_unique() -> bool:
	return rarity == GameEnums.Rarity.RELIC

func type_line() -> String:
	var line := " ".join(supertypes + types)
	if not subtypes.is_empty():
		line += " - " + " ".join(subtypes)
	return line

func _to_string() -> String:
	return "%s (%s)" % [name, mana_cost_text]
