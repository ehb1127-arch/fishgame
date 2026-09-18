## Per-match settings: life totals, deck size, and the clock.
##
## The engine itself never watches a clock. A controller (the UI) counts down
## and, when time runs out, feeds the engine a TIMEOUT action. That keeps the
## rules deterministic and the headless tests reproducible.
class_name MatchRules
extends RefCounted

enum Mode {
	STANDARD,
	BLITZ,
	RIPTIDE,
	CASTAWAY,
}

## What happens when a player's clock hits zero.
enum Timeout {
	END_TURN,        ## Current turn is forced to end.
	END_TURN_DAMAGE, ## Turn ends and the player loses life.
	LOSE_GAME,       ## The player loses outright (chess clock).
}

var mode: Mode = Mode.STANDARD
var display_name: String = "Standard"
var starting_life: int = 20
var starting_hand: int = 7
var max_hand_size: int = 7
var deck_size: int = 40

## Seconds a player gets per turn. 0 means no limit.
var turn_seconds: float = 90.0
## Total seconds per player for the whole match, chess-clock style. 0 = off.
var match_seconds: float = 0.0
var timeout_rule: Timeout = Timeout.END_TURN
var timeout_life_loss: int = 0
## Seconds added back at the start of each of your turns in chess-clock mode.
var increment_seconds: float = 0.0


static func standard() -> MatchRules:
	var r := MatchRules.new()
	r.mode = Mode.STANDARD
	r.display_name = "Standard"
	r.turn_seconds = 90.0
	r.timeout_rule = Timeout.END_TURN
	return r


## Short turns; the whole match is meant to fit in a bus ride.
static func blitz() -> MatchRules:
	var r := MatchRules.new()
	r.mode = Mode.BLITZ
	r.display_name = "Blitz"
	r.starting_life = 16
	r.turn_seconds = 20.0
	r.timeout_rule = Timeout.END_TURN
	return r


## Ten seconds a turn, and dithering costs life.
static func riptide() -> MatchRules:
	var r := MatchRules.new()
	r.mode = Mode.RIPTIDE
	r.display_name = "Riptide"
	r.starting_life = 14
	r.turn_seconds = 10.0
	r.timeout_rule = Timeout.END_TURN_DAMAGE
	r.timeout_life_loss = 2
	return r


## Chess clock: five minutes each for the entire match.
static func castaway() -> MatchRules:
	var r := MatchRules.new()
	r.mode = Mode.CASTAWAY
	r.display_name = "Castaway"
	r.turn_seconds = 0.0
	r.match_seconds = 300.0
	r.increment_seconds = 3.0
	r.timeout_rule = Timeout.LOSE_GAME
	return r


static func from_mode(mode_value: Mode) -> MatchRules:
	match mode_value:
		Mode.BLITZ:
			return blitz()
		Mode.RIPTIDE:
			return riptide()
		Mode.CASTAWAY:
			return castaway()
		_:
			return standard()


static func all_modes() -> Array[MatchRules]:
	return [standard(), blitz(), riptide(), castaway()]


func uses_turn_clock() -> bool:
	return turn_seconds > 0.0

func uses_match_clock() -> bool:
	return match_seconds > 0.0

func has_clock() -> bool:
	return uses_turn_clock() or uses_match_clock()
