## The shop: packs, decks, and cosmetics.
##
## Design rule, enforced here rather than left to habit: **Abyss Gems (the
## paid currency) never buy a card that Pearl Coins cannot.** Gems buy
## cosmetics, and they buy packs faster. Anything that changes what you can
## play is reachable by playing.
class_name Shop
extends RefCounted

enum Category {
	PACK,
	DECK,
	COSMETIC,
	BUNDLE,
	PASS,
}

## Cosmetic slots. None of these touch the rules.
const SLOT_CARD_BACK := "card_back"
const SLOT_BOARD := "board"
const SLOT_AVATAR := "avatar"
const SLOT_EMOTE := "emote"

## Rewards for playing, which is where Pearl Coins come from.
const COINS_PER_RANKED_WIN := 50
const COINS_PER_RANKED_LOSS := 15
const COINS_PER_VOYAGE_STAGE := 30
const COINS_PER_VOYAGE_CLEAR := 300
const COINS_DAILY_FIRST_WIN := 100


## The catalogue. Kept as data so a live game can swap it out without a patch.
static func catalogue() -> Array:
	var items: Array = []

	items.append({
		"id": "pack_last_tide",
		"category": Category.PACK,
		"name": "The Last Tide pack",
		"name_ko": "마지막 조류 팩",
		"description": "Five cards. See the posted odds before you buy.",
		"description_ko": "카드 5장. 구매 전 공시된 확률을 확인하세요.",
		"set": "last_tide",
		"price": {"coin": 100, "gem": 80},
	})

	items.append({
		"id": "pack_last_tide_ten",
		"category": Category.PACK,
		"name": "The Last Tide, ten packs",
		"name_ko": "마지막 조류 10팩",
		"description": "Ten packs at a discount. Pity counters carry across them.",
		"description_ko": "10팩 묶음 할인. 천장 카운터는 이어집니다.",
		"set": "last_tide",
		"quantity": 10,
		"price": {"coin": 900, "gem": 700},
	})

	for deck_id in Cards.deck_ids():
		var deck := Cards.get_deck_definition(deck_id)
		items.append({
			"id": "deck_" + deck_id,
			"category": Category.DECK,
			"name": str(deck.get("name", deck_id)),
			"name_ko": str(deck.get("name_ko", deck_id)),
			"description": str(deck.get("description", "")),
			"description_ko": str(deck.get("description_ko", "")),
			"deck": deck_id,
			"price": {"coin": 1500, "gem": 0},
		})

	# Cosmetics: the paid side of the game, and deliberately the only side.
	for entry in _cosmetic_catalogue():
		items.append(entry)

	items.append({
		"id": "pass_voyage",
		"category": Category.PASS,
		"name": "Voyage Pass",
		"name_ko": "항해 통행증",
		"description": "Extra rewards along every Voyage for one season.",
		"description_ko": "한 시즌 동안 모든 항해에서 추가 보상을 받습니다.",
		"price": {"coin": 0, "gem": 900},
	})

	return items


static func _cosmetic_catalogue() -> Array:
	return [
		{"id": "back_drowned_charts", "category": Category.COSMETIC, "slot": SLOT_CARD_BACK,
		 "name": "Drowned Charts", "name_ko": "익사한 해도",
		 "description": "A card back of sea charts for coastlines that no longer exist.",
		 "description_ko": "더 이상 존재하지 않는 해안선의 해도로 만든 카드 뒷면.",
		 "price": {"coin": 0, "gem": 300}},
		{"id": "back_kraken_ink", "category": Category.COSMETIC, "slot": SLOT_CARD_BACK,
		 "name": "Kraken Ink", "name_ko": "크라켄의 먹물",
		 "description": "Ink that moves when you hold the card still.",
		 "description_ko": "카드를 가만히 들고 있으면 움직이는 먹물.",
		 "price": {"coin": 0, "gem": 400}},
		{"id": "board_spire", "category": Category.COSMETIC, "slot": SLOT_BOARD,
		 "name": "The Coral Spire", "name_ko": "산호의 첨탑",
		 "description": "Play on the terraces of Thalassa's spire.",
		 "description_ko": "탈라사의 첨탑 테라스 위에서 플레이합니다.",
		 "price": {"coin": 0, "gem": 600}},
		{"id": "board_wreckline", "category": Category.COSMETIC, "slot": SLOT_BOARD,
		 "name": "The Wreckline", "name_ko": "난파선 지대",
		 "description": "A board where the wreck pile is a real shipwreck.",
		 "description_ko": "난파선 더미가 실제 난파선으로 보이는 보드.",
		 "price": {"coin": 0, "gem": 600}},
		{"id": "avatar_kai", "category": Category.COSMETIC, "slot": SLOT_AVATAR,
		 "name": "Captain Kai", "name_ko": "케이 선장",
		 "description": "", "description_ko": "",
		 "price": {"coin": 0, "gem": 200}},
		{"id": "avatar_morgaine", "category": Category.COSMETIC, "slot": SLOT_AVATAR,
		 "name": "Morgaine", "name_ko": "모르간",
		 "description": "", "description_ko": "",
		 "price": {"coin": 0, "gem": 200}},
		{"id": "emote_no_rope", "category": Category.COSMETIC, "slot": SLOT_EMOTE,
		 "name": "\"There is no rope.\"", "name_ko": "\"밧줄은 없다.\"",
		 "description": "", "description_ko": "",
		 "price": {"coin": 0, "gem": 100}},
	]


static func find_item(item_id: String) -> Dictionary:
	for item in catalogue():
		if str((item as Dictionary)["id"]) == item_id:
			return item as Dictionary
	return {}


## Can this item be bought with [param currency]? An item priced at 0 in a
## currency is not for sale in it.
static func price_in(item: Dictionary, currency: Currency.Kind) -> int:
	var prices := item.get("price", {}) as Dictionary
	match currency:
		Currency.Kind.PEARL_COIN:
			return int(prices.get("coin", 0))
		Currency.Kind.ABYSS_GEM:
			return int(prices.get("gem", 0))
		_:
			return 0


static func is_purchasable_with(item: Dictionary, currency: Currency.Kind) -> bool:
	return price_in(item, currency) > 0


## Coins awarded for a finished match.
static func match_reward(won: bool, is_first_win_today: bool) -> int:
	var coins := COINS_PER_RANKED_WIN if won else COINS_PER_RANKED_LOSS
	if won and is_first_win_today:
		coins += COINS_DAILY_FIRST_WIN
	return coins
