## The three currencies and what each one is for.
##
## The split matters for how the game feels: Pearl Coins come from playing,
## Nacre Dust comes from duplicates you already own, and Abyss Gems are the
## only thing bought with money. Gems never buy power directly — they buy
## cosmetics and convenience, and packs that Coins can also buy.
class_name Currency
extends RefCounted

enum Kind {
	PEARL_COIN,
	NACRE_DUST,
	ABYSS_GEM,
}

const LABELS := {
	Kind.PEARL_COIN: "Pearl Coin",
	Kind.NACRE_DUST: "Nacre Dust",
	Kind.ABYSS_GEM: "Abyss Gem",
}

const LABELS_KO := {
	Kind.PEARL_COIN: "진주 코인",
	Kind.NACRE_DUST: "진주가루",
	Kind.ABYSS_GEM: "심연 보석",
}

## Dust you get back for a duplicate you cannot use, by rarity.
const DUST_FOR_DUPLICATE := {
	GameEnums.Rarity.DRIFTWOOD: 5,
	GameEnums.Rarity.CORAL: 15,
	GameEnums.Rarity.PEARL: 50,
	GameEnums.Rarity.GOLD: 150,
	GameEnums.Rarity.RELIC: 600,
	GameEnums.Rarity.LEVIATHAN: 2000,
}

## Dust cost of each upgrade step, multiplied by the rarity factor below.
## Index 0 is the ★1 -> ★2 step.
const UPGRADE_DUST_STEPS: Array[int] = [20, 50, 120, 300]
## How many duplicate copies each step needs.
const UPGRADE_COPIES_STEPS: Array[int] = [1, 2, 3, 4]

const RARITY_UPGRADE_FACTOR := {
	GameEnums.Rarity.DRIFTWOOD: 1.0,
	GameEnums.Rarity.CORAL: 1.5,
	GameEnums.Rarity.PEARL: 2.5,
	GameEnums.Rarity.GOLD: 4.0,
	GameEnums.Rarity.RELIC: 7.0,
	GameEnums.Rarity.LEVIATHAN: 12.0,
}


static func label(kind: Kind, korean: bool = false) -> String:
	return str((LABELS_KO if korean else LABELS).get(kind, "?"))


static func dust_for_duplicate(rarity: GameEnums.Rarity) -> int:
	return int(DUST_FOR_DUPLICATE.get(rarity, 5))


## Cost to take a card from [param from_stars] to the next star.
## Returns {"dust": n, "copies": n}, or an empty dictionary at max stars.
static func upgrade_cost(rarity: GameEnums.Rarity, from_stars: int) -> Dictionary:
	if from_stars < GameEnums.MIN_STARS or from_stars >= GameEnums.MAX_STARS:
		return {}
	var step := from_stars - GameEnums.MIN_STARS
	var factor := float(RARITY_UPGRADE_FACTOR.get(rarity, 1.0))
	return {
		"dust": int(round(UPGRADE_DUST_STEPS[step] * factor)),
		"copies": UPGRADE_COPIES_STEPS[step],
	}


## Total cost of going from ★1 to ★5, for the collection screen.
static func total_upgrade_cost(rarity: GameEnums.Rarity) -> Dictionary:
	var dust := 0
	var copies := 0
	for stars in range(GameEnums.MIN_STARS, GameEnums.MAX_STARS):
		var cost := upgrade_cost(rarity, stars)
		dust += int(cost.get("dust", 0))
		copies += int(cost.get("copies", 0))
	return {"dust": dust, "copies": copies}
