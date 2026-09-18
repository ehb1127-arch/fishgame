## One physical copy of a card inside a game: in a library, a hand, on the
## battlefield, or on the stack.
##
## Printed values live in [member data] and never change. Everything that the
## game can change lives here. Characteristics that other permanents can alter
## (an anthem pumping your team, say) are recomputed into the eff_* fields by
## ContinuousEffects whenever the board changes, so readers never have to walk
## the battlefield themselves.
class_name CardInstance
extends RefCounted

var uid: int = 0
var data: CardData = null

var owner_index: int = 0
var controller_index: int = 0
var zone: GameEnums.Zone = GameEnums.Zone.LIBRARY

# --- Permanent state ---
var tapped: bool = false
var damage: int = 0
var counters: Dictionary = {}
var is_token: bool = false
## Entered the battlefield this turn, so it cannot attack or tap without
## Surging.
var summoning_sick: bool = true
var entered_on_turn: int = -1

## Which depth band this permanent occupies. Only creatures use it.
var depth: GameEnums.Depth = GameEnums.Depth.MIDWATER
## Molt absorbs one lethal blow per turn; reset during cleanup.
var molt_spent: bool = false
## Upgrade level from the player's collection, 1 to 5.
var star_level: int = GameEnums.MIN_STARS

# --- Until-end-of-turn modifiers, wiped during cleanup ---
var temp_power: int = 0
var temp_toughness: int = 0
var temp_keywords: Array[String] = []
## Damage dealt by this source this turn is treated as deathtouch.
var temp_deathtouch: bool = false

# --- Combat state, wiped when combat ends ---
var attacking: bool = false
## uid of each creature this one is blocking, and vice versa.
var blocking: Array[int] = []
var blocked_by: Array[int] = []
## Set once a creature has been blocked, even if every blocker later leaves.
var was_blocked: bool = false
var dealt_first_strike_damage: bool = false

# --- Stack state (spells and abilities waiting to resolve) ---
## "spell" for a cast card, "ability" for an activated or triggered ability.
var stack_kind: String = ""
## The ability dictionary for a stacked ability, empty for a spell.
var stack_ability: Dictionary = {}
## Chosen targets, one entry per declared target slot.
var targets: Array = []
var chosen_x: int = 0
## The permanent an ability came from, for abilities on the stack.
var source_uid: int = 0

# --- Cached characteristics, rebuilt by ContinuousEffects ---
var eff_power: int = 0
var eff_toughness: int = 0
var eff_keywords: Array[String] = []
var eff_types: Array[String] = []
var eff_colors: Array[String] = []


static func create(p_uid: int, p_data: CardData, p_owner: int, p_stars: int = GameEnums.MIN_STARS) -> CardInstance:
	var c := CardInstance.new()
	c.uid = p_uid
	c.data = p_data
	c.owner_index = p_owner
	c.controller_index = p_owner
	c.depth = p_data.native_depth
	c.star_level = clampi(p_stars, GameEnums.MIN_STARS, GameEnums.MAX_STARS)
	c.refresh_base_characteristics()
	return c


## Resets the cached characteristics to the printed ones plus counters and
## until-end-of-turn effects. ContinuousEffects layers static effects on top.
func refresh_base_characteristics() -> void:
	var plus := counter_count("+1/+1")
	var minus := counter_count("-1/-1")
	var star_power := GameEnums.star_power_bonus(star_level)
	var star_toughness := GameEnums.star_toughness_bonus(star_level)
	eff_power = data.power + star_power + plus - minus + temp_power
	eff_toughness = data.toughness + star_toughness + plus - minus + temp_toughness
	eff_keywords = data.keywords.duplicate()
	for kw in data.milestone_keywords(star_level):
		if kw not in eff_keywords:
			eff_keywords.append(kw)
	for kw in temp_keywords:
		if kw not in eff_keywords:
			eff_keywords.append(kw)
	eff_types = data.types.duplicate()
	eff_colors = data.colors.duplicate()


func has_keyword(keyword: String) -> bool:
	return keyword in eff_keywords

func grant_keyword(keyword: String) -> void:
	if keyword not in eff_keywords:
		eff_keywords.append(keyword)

func is_type(type_name: String) -> bool:
	return type_name in eff_types

func is_creature() -> bool:
	return is_type(GameEnums.TYPE_CREATURE)

func is_land() -> bool:
	return is_type(GameEnums.TYPE_LAND)

func is_permanent() -> bool:
	for t in eff_types:
		if t in GameEnums.PERMANENT_TYPES:
			return true
	return false

func is_subtype(subtype: String) -> bool:
	return subtype in data.subtypes


func counter_count(kind: String) -> int:
	return int(counters.get(kind, 0))

func add_counters(kind: String, amount: int = 1) -> void:
	counters[kind] = counter_count(kind) + amount
	if int(counters[kind]) <= 0:
		counters.erase(kind)
	_annihilate_opposing_counters()

## +1/+1 and -1/-1 counters cancel each other out as a state-based action.
func _annihilate_opposing_counters() -> void:
	var plus := counter_count("+1/+1")
	var minus := counter_count("-1/-1")
	if plus > 0 and minus > 0:
		var both: int = min(plus, minus)
		counters["+1/+1"] = plus - both
		counters["-1/-1"] = minus - both
		if int(counters["+1/+1"]) <= 0:
			counters.erase("+1/+1")
		if int(counters["-1/-1"]) <= 0:
			counters.erase("-1/-1")


## A creature with damage at or above its toughness is destroyed by a
## state-based action, unless it is indestructible.
func is_lethally_damaged() -> bool:
	if not is_creature():
		return false
	return eff_toughness > 0 and damage >= eff_toughness

func has_zero_toughness() -> bool:
	return is_creature() and eff_toughness <= 0


## Can this creature be declared as an attacker right now?
func can_attack() -> bool:
	if not is_creature() or tapped:
		return false
	if has_keyword(GameEnums.KW_BREAKWATER):
		return false
	if summoning_sick and not has_keyword(GameEnums.KW_SURGING):
		return false
	return true

## Can this creature be declared as a blocker right now?
func can_block() -> bool:
	return is_creature() and not tapped

## Can it pay a tap symbol in an activation cost?
func can_tap_for_cost() -> bool:
	if tapped:
		return false
	if is_creature() and summoning_sick and not has_keyword(GameEnums.KW_SURGING):
		return false
	return true


## Clears state that only lasts through one combat.
func reset_combat_state() -> void:
	attacking = false
	blocking.clear()
	blocked_by.clear()
	was_blocked = false
	dealt_first_strike_damage = false

## Can this creature change depth band right now?
func can_change_depth() -> bool:
	return is_creature() and not has_keyword(GameEnums.KW_ANCHORED)

## Clears state that only lasts through one turn. Called during cleanup.
func reset_turn_state() -> void:
	damage = 0
	molt_spent = false
	temp_power = 0
	temp_toughness = 0
	temp_keywords.clear()
	temp_deathtouch = false
	reset_combat_state()


## Fresh copy for tokens and for cards returning to a zone as new objects.
func to_new_object(new_uid: int) -> CardInstance:
	var c := CardInstance.create(new_uid, data, owner_index, star_level)
	c.is_token = is_token
	return c


## --- Snapshots -----------------------------------------------------------
##
## Used by rewind effects, which restore the board to how it stood at the
## start of the turn. Only mutable state is stored; [member data] is shared.

func snapshot() -> Dictionary:
	return {
		"uid": uid, "owner": owner_index, "controller": controller_index,
		"zone": zone, "tapped": tapped, "damage": damage,
		"counters": counters.duplicate(), "is_token": is_token,
		"sick": summoning_sick, "entered": entered_on_turn, "depth": depth,
		"molt": molt_spent, "stars": star_level,
		"tp": temp_power, "tt": temp_toughness,
		"tk": temp_keywords.duplicate(), "td": temp_deathtouch,
		"attacking": attacking, "blocking": blocking.duplicate(),
		"blocked_by": blocked_by.duplicate(), "was_blocked": was_blocked,
		"fs": dealt_first_strike_damage, "stack_kind": stack_kind,
		"stack_ability": stack_ability.duplicate(true),
		"targets": targets.duplicate(true), "x": chosen_x,
		"source_uid": source_uid,
	}


func restore(state: Dictionary) -> void:
	owner_index = int(state["owner"])
	controller_index = int(state["controller"])
	zone = state["zone"]
	tapped = bool(state["tapped"])
	damage = int(state["damage"])
	counters = (state["counters"] as Dictionary).duplicate()
	is_token = bool(state["is_token"])
	summoning_sick = bool(state["sick"])
	entered_on_turn = int(state["entered"])
	depth = state["depth"]
	molt_spent = bool(state["molt"])
	star_level = int(state["stars"])
	temp_power = int(state["tp"])
	temp_toughness = int(state["tt"])
	temp_keywords = _to_string_array(state["tk"])
	temp_deathtouch = bool(state["td"])
	attacking = bool(state["attacking"])
	blocking = _to_int_array(state["blocking"])
	blocked_by = _to_int_array(state["blocked_by"])
	was_blocked = bool(state["was_blocked"])
	dealt_first_strike_damage = bool(state["fs"])
	stack_kind = str(state["stack_kind"])
	stack_ability = (state["stack_ability"] as Dictionary).duplicate(true)
	targets = (state["targets"] as Array).duplicate(true)
	chosen_x = int(state["x"])
	source_uid = int(state["source_uid"])
	refresh_base_characteristics()


static func _to_int_array(value: Variant) -> Array[int]:
	var out: Array[int] = []
	for v in value as Array:
		out.append(int(v))
	return out


static func _to_string_array(value: Variant) -> Array[String]:
	var out: Array[String] = []
	for v in value as Array:
		out.append(str(v))
	return out


func display_name() -> String:
	return data.name

func depth_label() -> String:
	return GameEnums.depth_name(depth)

func star_text() -> String:
	return "★".repeat(star_level)

func power_toughness_text() -> String:
	if not is_creature():
		return ""
	return "%d/%d" % [eff_power, eff_toughness]

func _to_string() -> String:
	var suffix := " [tapped]" if tapped else ""
	return "#%d %s%s" % [uid, data.name, suffix]
