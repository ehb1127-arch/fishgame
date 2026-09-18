## Pack rarity odds, pity counters, and the disclosure table.
##
## Korean law requires published drop rates for paid random items, so the
## numbers live in one place and [method disclosure_rows] renders them
## straight from the tables the roller actually uses. If you change a rate,
## the published table changes with it — they cannot drift apart.
class_name PackOdds
extends RefCounted

const PACK_SIZE := 5

## Per-slot odds, as rarity -> probability. Each table must sum to 1.0.
## Slots 1-3 are the common slots, slot 4 is the uncommon slot, and slot 5 is
## the one people actually open the pack for.
const SLOT_COMMON := {
	GameEnums.Rarity.DRIFTWOOD: 0.84,
	GameEnums.Rarity.CORAL: 0.16,
}

const SLOT_UNCOMMON := {
	GameEnums.Rarity.CORAL: 0.88,
	GameEnums.Rarity.PEARL: 0.12,
}

const SLOT_RARE := {
	GameEnums.Rarity.PEARL: 0.794,
	GameEnums.Rarity.GOLD: 0.18,
	GameEnums.Rarity.RELIC: 0.025,
	GameEnums.Rarity.LEVIATHAN: 0.001,
}

## Any card, of any rarity, can come out Inscribed: a cosmetic variant with
## different art and a foil treatment. Identical in play.
const INSCRIBED_CHANCE := 0.0001

## Pity: guaranteed floors if you have gone this long without one.
const PITY_GOLD := 30
const PITY_RELIC := 150
const PITY_LEVIATHAN := 1000


## A fresh pity record, stored on the player profile.
static func new_pity() -> Dictionary:
	return {"since_gold": 0, "since_relic": 0, "since_leviathan": 0, "packs": 0}


## Opens one pack. [param pity] is updated in place.
## Returns PACK_SIZE entries of {"rarity": Rarity, "inscribed": bool}.
static func roll_pack(rng: RandomNumberGenerator, pity: Dictionary) -> Array:
	var out: Array = []
	for i in PACK_SIZE:
		var table := SLOT_COMMON
		if i == PACK_SIZE - 2:
			table = SLOT_UNCOMMON
		elif i == PACK_SIZE - 1:
			table = SLOT_RARE
		var rarity := _roll_rarity(rng, table)
		if i == PACK_SIZE - 1:
			rarity = _apply_pity(rarity, pity)
		out.append({
			"rarity": rarity,
			"inscribed": rng.randf() < INSCRIBED_CHANCE,
		})
	_update_pity(out, pity)
	pity["packs"] = int(pity.get("packs", 0)) + 1
	return out


static func _roll_rarity(rng: RandomNumberGenerator, table: Dictionary) -> GameEnums.Rarity:
	var roll := rng.randf()
	var cumulative := 0.0
	for rarity in table:
		cumulative += float(table[rarity])
		if roll < cumulative:
			return rarity
	# Floating point can leave a sliver at the top; give it to the last entry.
	return table.keys()[table.size() - 1]


## Raises a roll to the guaranteed floor when a counter has run out.
static func _apply_pity(rarity: GameEnums.Rarity, pity: Dictionary) -> GameEnums.Rarity:
	if int(pity.get("since_leviathan", 0)) + 1 >= PITY_LEVIATHAN:
		return GameEnums.Rarity.LEVIATHAN
	if int(pity.get("since_relic", 0)) + 1 >= PITY_RELIC and rarity < GameEnums.Rarity.RELIC:
		return GameEnums.Rarity.RELIC
	if int(pity.get("since_gold", 0)) + 1 >= PITY_GOLD and rarity < GameEnums.Rarity.GOLD:
		return GameEnums.Rarity.GOLD
	return rarity


static func _update_pity(results: Array, pity: Dictionary) -> void:
	var best := GameEnums.Rarity.DRIFTWOOD
	for entry in results:
		var r: GameEnums.Rarity = (entry as Dictionary)["rarity"]
		if r > best:
			best = r

	pity["since_gold"] = 0 if best >= GameEnums.Rarity.GOLD \
		else int(pity.get("since_gold", 0)) + 1
	pity["since_relic"] = 0 if best >= GameEnums.Rarity.RELIC \
		else int(pity.get("since_relic", 0)) + 1
	pity["since_leviathan"] = 0 if best >= GameEnums.Rarity.LEVIATHAN \
		else int(pity.get("since_leviathan", 0)) + 1


## --- Disclosure ----------------------------------------------------------

## The published odds table, generated from the same constants the roller
## uses. Each row is {rarity, per_pack, label}.
##
## [param per_pack] is the chance that a pack contains at least one card of
## that rarity, which is the figure players care about and the one the law
## asks to be shown.
static func disclosure_rows() -> Array:
	var rows: Array = []
	for rarity in [
		GameEnums.Rarity.DRIFTWOOD, GameEnums.Rarity.CORAL,
		GameEnums.Rarity.PEARL, GameEnums.Rarity.GOLD,
		GameEnums.Rarity.RELIC, GameEnums.Rarity.LEVIATHAN,
	]:
		var miss := 1.0
		for i in PACK_SIZE:
			var table := SLOT_COMMON
			if i == PACK_SIZE - 2:
				table = SLOT_UNCOMMON
			elif i == PACK_SIZE - 1:
				table = SLOT_RARE
			miss *= 1.0 - float(table.get(rarity, 0.0))
		rows.append({
			"rarity": rarity,
			"label": GameEnums.rarity_name(rarity),
			"label_ko": GameEnums.rarity_name_ko(rarity),
			"per_pack": 1.0 - miss,
		})
	rows.append({
		"rarity": -1,
		"label": "Inscribed variant (any rarity)",
		"label_ko": "각인 변형 (모든 등급)",
		"per_pack": 1.0 - pow(1.0 - INSCRIBED_CHANCE, PACK_SIZE),
	})
	return rows


## Human-readable disclosure text for the shop screen.
static func disclosure_text(korean: bool = true) -> String:
	var lines: Array[String] = []
	lines.append("한 팩 %d장 기준 등급별 출현 확률" if korean else "Chance per %d-card pack")
	lines[0] = lines[0] % PACK_SIZE
	for row in disclosure_rows():
		var label := str(row["label_ko"] if korean else row["label"])
		lines.append("  %s: %.4f%%" % [label, float(row["per_pack"]) * 100.0])
	if korean:
		lines.append("천장: %d팩 내 황금 이상, %d팩 내 심연유물 이상, %d팩 내 리바이어던 확정"
			% [PITY_GOLD, PITY_RELIC, PITY_LEVIATHAN])
	else:
		lines.append("Guaranteed: Gold or better within %d packs, Relic within %d, Leviathan within %d"
			% [PITY_GOLD, PITY_RELIC, PITY_LEVIATHAN])
	return "\n".join(lines)


## Sanity check used by the tests: every slot table must sum to 1.
static func tables_are_valid() -> bool:
	for table in [SLOT_COMMON, SLOT_UNCOMMON, SLOT_RARE]:
		var total := 0.0
		for rarity in table:
			total += float(table[rarity])
		if absf(total - 1.0) > 0.0001:
			return false
	return true
