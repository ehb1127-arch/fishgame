## Elo rating and the rank ladder.
##
## Ranks are named after how deep you can go, which is the same axis the game
## itself is built on.
class_name Rating
extends RefCounted

const STARTING_RATING := 1200
const K_FACTOR := 32
## New players move faster for their first games so placement is quick.
const PLACEMENT_GAMES := 10
const PLACEMENT_K := 64

const TIERS := [
	{"min": 0, "name": "Drifter", "name_ko": "표류자"},
	{"min": 1000, "name": "Shoalkeeper", "name_ko": "여울지기"},
	{"min": 1200, "name": "Diver", "name_ko": "잠수부"},
	{"min": 1400, "name": "Trencher", "name_ko": "해구 탐사자"},
	{"min": 1600, "name": "Abyssal", "name_ko": "심연 순찰자"},
	{"min": 1800, "name": "Leviathan", "name_ko": "리바이어던"},
]


## Expected score for [param rating] against [param opponent_rating].
static func expected_score(rating: int, opponent_rating: int) -> float:
	return 1.0 / (1.0 + pow(10.0, float(opponent_rating - rating) / 400.0))


## New rating after a match. [param score] is 1 for a win, 0.5 a draw, 0 a loss.
static func updated(rating: int, opponent_rating: int, score: float, games_played: int) -> int:
	var k := PLACEMENT_K if games_played < PLACEMENT_GAMES else K_FACTOR
	var change := k * (score - expected_score(rating, opponent_rating))
	return maxi(0, rating + int(round(change)))


## In a team game every member is rated against the average of the other team.
static func team_update(member_ratings: Array, opponent_ratings: Array, won: bool,
		games_played: Array) -> Array[int]:
	var opponent_average := 0
	for r in opponent_ratings:
		opponent_average += int(r)
	if not opponent_ratings.is_empty():
		opponent_average = int(float(opponent_average) / opponent_ratings.size())

	var out: Array[int] = []
	for i in member_ratings.size():
		var played := int(games_played[i]) if i < games_played.size() else PLACEMENT_GAMES
		out.append(updated(int(member_ratings[i]), opponent_average, 1.0 if won else 0.0, played))
	return out


static func tier_for(rating: int) -> Dictionary:
	var current: Dictionary = TIERS[0]
	for tier in TIERS:
		if rating >= int((tier as Dictionary)["min"]):
			current = tier
	return current


static func tier_name(rating: int, korean: bool = false) -> String:
	var tier := tier_for(rating)
	return str(tier["name_ko"] if korean else tier["name"])


## Rating still needed for the next tier, or 0 at the top.
static func to_next_tier(rating: int) -> int:
	for tier in TIERS:
		var floor_value := int((tier as Dictionary)["min"])
		if rating < floor_value:
			return floor_value - rating
	return 0
