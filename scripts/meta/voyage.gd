## A Voyage run: descend through the regions, one fight at a time.
##
## Your life carries between stages and only partly heals, and the deck you
## brought grows as you pick rewards. Losing ends the run.
class_name Voyage
extends RefCounted

## Reward rarity odds by stage depth, from the first region to the last. Each
## row must sum to 1.0; deeper rows push the good stuff up.
const REWARD_ODDS: Array[Dictionary] = [
	{GameEnums.Rarity.DRIFTWOOD: 0.70, GameEnums.Rarity.CORAL: 0.25,
	 GameEnums.Rarity.PEARL: 0.049, GameEnums.Rarity.GOLD: 0.0009,
	 GameEnums.Rarity.RELIC: 0.0001},
	{GameEnums.Rarity.DRIFTWOOD: 0.45, GameEnums.Rarity.CORAL: 0.38,
	 GameEnums.Rarity.PEARL: 0.15, GameEnums.Rarity.GOLD: 0.019,
	 GameEnums.Rarity.RELIC: 0.001},
	{GameEnums.Rarity.DRIFTWOOD: 0.20, GameEnums.Rarity.CORAL: 0.42,
	 GameEnums.Rarity.PEARL: 0.32, GameEnums.Rarity.GOLD: 0.055,
	 GameEnums.Rarity.RELIC: 0.005},
	{GameEnums.Rarity.CORAL: 0.34, GameEnums.Rarity.PEARL: 0.45,
	 GameEnums.Rarity.GOLD: 0.19, GameEnums.Rarity.RELIC: 0.0195,
	 GameEnums.Rarity.LEVIATHAN: 0.0005},
	{GameEnums.Rarity.PEARL: 0.40, GameEnums.Rarity.GOLD: 0.47,
	 GameEnums.Rarity.RELIC: 0.128, GameEnums.Rarity.LEVIATHAN: 0.002},
]

## Cards offered after each win; you keep one.
const REWARD_CHOICES := 3

var definition: Dictionary = {}
var region_index: int = 0
var stage_index: int = 0
var life: int = 25
var max_life: int = 25
var deck_ids: Array[String] = []
var vault_ids: Array[String] = []
var finished: bool = false
var won_run: bool = false
var stages_cleared: int = 0
## Cards currently on offer, as card ids.
var pending_rewards: Array[String] = []

var rng := RandomNumberGenerator.new()


static func start(deck_id: String, seed_value: int = 0) -> Voyage:
	var v := Voyage.new()
	v.definition = _load_definition()
	v.rng.seed = seed_value if seed_value != 0 else randi()
	v.max_life = int(v.definition.get("starting_life", 25))
	v.life = v.max_life
	var built := Cards.build_deck(deck_id)
	for card in built["main"] as Array:
		v.deck_ids.append(str((card as CardData).id))
	for card in built["vault"] as Array:
		v.vault_ids.append(str((card as CardData).id))
	return v


static func _load_definition() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/voyage.json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


## --- Progress ------------------------------------------------------------

func regions() -> Array:
	return definition.get("regions", []) as Array

func current_region() -> Dictionary:
	var list := regions()
	if region_index < 0 or region_index >= list.size():
		return {}
	return list[region_index] as Dictionary

func current_stage() -> Dictionary:
	var region := current_region()
	if region.is_empty():
		return {}
	var stages := region.get("stages", []) as Array
	if stage_index < 0 or stage_index >= stages.size():
		return {}
	var stage := (stages[stage_index] as Dictionary).duplicate(true)
	stage["region"] = str(region.get("name", ""))
	stage["region_ko"] = str(region.get("name_ko", ""))
	stage["depth"] = region_index
	return stage

func total_stages() -> int:
	var n := 0
	for region in regions():
		n += ((region as Dictionary).get("stages", []) as Array).size()
	return n

func is_boss_stage() -> bool:
	return bool(current_stage().get("boss", false))


## --- Results -------------------------------------------------------------

## Records the outcome of a fight. On a win this rolls the reward choices;
## on a loss the run is over.
func finish_stage(won: bool, life_remaining: int) -> Dictionary:
	if won:
		stages_cleared += 1
		life = clampi(life_remaining, 1, max_life)
		var heal := int(definition.get("heal_after_boss" if is_boss_stage()
				else "heal_between_stages", 5))
		life = mini(max_life, life + heal)
		pending_rewards = _roll_rewards()
		return {
			"won": true, "life": life, "healed": heal,
			"rewards": pending_rewards, "run_complete": false,
		}

	finished = true
	won_run = false
	return {"won": false, "life": 0, "rewards": [], "run_complete": true}


## Takes one of the offered cards into the run deck.
func take_reward(choice_index: int) -> String:
	if choice_index < 0 or choice_index >= pending_rewards.size():
		return ""
	var card_id := pending_rewards[choice_index]
	deck_ids.append(card_id)
	pending_rewards.clear()
	_advance()
	return card_id


## Declining a reward is allowed; a tighter deck is sometimes better.
func skip_reward() -> void:
	pending_rewards.clear()
	_advance()


func _advance() -> void:
	var region := current_region()
	var stages := region.get("stages", []) as Array
	stage_index += 1
	if stage_index < stages.size():
		return
	stage_index = 0
	region_index += 1
	if region_index >= regions().size():
		finished = true
		won_run = true


## --- Rewards -------------------------------------------------------------

func _roll_rewards() -> Array[String]:
	var odds := REWARD_ODDS[clampi(region_index, 0, REWARD_ODDS.size() - 1)]
	var pool_by_rarity := {}
	for card in Cards.collectible_cards():
		var c := card as CardData
		var bucket := pool_by_rarity.get(c.rarity, []) as Array
		bucket.append(c)
		pool_by_rarity[c.rarity] = bucket

	var out: Array[String] = []
	var guard := 0
	while out.size() < REWARD_CHOICES and guard < 40:
		guard += 1
		var rarity := _roll_rarity(odds)
		var pool := pool_by_rarity.get(rarity, []) as Array
		if pool.is_empty():
			continue
		var card: CardData = pool[rng.randi_range(0, pool.size() - 1)]
		if str(card.id) in out:
			continue
		out.append(str(card.id))
	return out


func _roll_rarity(odds: Dictionary) -> GameEnums.Rarity:
	var roll := rng.randf()
	var cumulative := 0.0
	for rarity in odds:
		cumulative += float(odds[rarity])
		if roll < cumulative:
			return rarity
	return GameEnums.Rarity.DRIFTWOOD


## Coins paid out for the run so far.
func coins_earned() -> int:
	var coins := stages_cleared * Shop.COINS_PER_VOYAGE_STAGE
	if won_run:
		coins += Shop.COINS_PER_VOYAGE_CLEAR
	return coins


## --- Save ----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"region": region_index, "stage": stage_index,
		"life": life, "max_life": max_life,
		"deck": deck_ids.duplicate(), "vault": vault_ids.duplicate(),
		"finished": finished, "won": won_run, "cleared": stages_cleared,
		"pending": pending_rewards.duplicate(), "seed": rng.seed,
	}


static func from_dict(d: Dictionary) -> Voyage:
	var v := Voyage.new()
	v.definition = _load_definition()
	v.region_index = int(d.get("region", 0))
	v.stage_index = int(d.get("stage", 0))
	v.life = int(d.get("life", 25))
	v.max_life = int(d.get("max_life", 25))
	for id in d.get("deck", []) as Array:
		v.deck_ids.append(str(id))
	for id in d.get("vault", []) as Array:
		v.vault_ids.append(str(id))
	v.finished = bool(d.get("finished", false))
	v.won_run = bool(d.get("won", false))
	v.stages_cleared = int(d.get("cleared", 0))
	for id in d.get("pending", []) as Array:
		v.pending_rewards.append(str(id))
	v.rng.seed = int(d.get("seed", 0))
	return v


## Sanity check for the tests: every reward row must sum to 1.
static func odds_are_valid() -> bool:
	for row in REWARD_ODDS:
		var total := 0.0
		for rarity in row:
			total += float(row[rarity])
		if absf(total - 1.0) > 0.0001:
			return false
	return true
