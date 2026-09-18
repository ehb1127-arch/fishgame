## Shared enums and constants for the rules engine.
##
## Pure data: no scene tree, no rendering. Every other engine file depends on
## this one, and this one depends on nothing.
class_name GameEnums
extends RefCounted

enum Phase {
	BEGINNING,
	PRECOMBAT_MAIN,
	COMBAT,
	POSTCOMBAT_MAIN,
	ENDING,
}

enum Step {
	UNTAP,
	UPKEEP,
	DRAW,
	PRECOMBAT_MAIN,
	BEGIN_COMBAT,
	DECLARE_ATTACKERS,
	DECLARE_BLOCKERS,
	COMBAT_DAMAGE,
	END_COMBAT,
	POSTCOMBAT_MAIN,
	END_STEP,
	CLEANUP,
}

## The three depth bands the battlefield is split into. A creature can only
## be blocked by a creature in its own band (see Combat), which replaces
## evasion keywords with a positional game.
enum Depth {
	SURFACE,
	MIDWATER,
	ABYSS,
}

## The global tide, which flips every round and buffs one band at a time.
enum Tide {
	HIGH,
	LOW,
}

## Card rarity, themed as what the sea gives up: driftwood washes ashore
## constantly, relics almost never. Rarity is not a rules concept during a
## match; it drives deck limits and Voyage rewards.
enum Rarity {
	DRIFTWOOD,
	CORAL,
	PEARL,
	GOLD,
	RELIC,
	LEVIATHAN,
}

enum Zone {
	LIBRARY,
	HAND,
	BATTLEFIELD,
	GRAVEYARD,
	EXILE,
	STACK,
	## The Abyssal Vault: a small side deck of cards you did not shuffle in,
	## reachable only through cards that fetch from it.
	VAULT,
}

## How many cards a vault may hold.
const VAULT_SIZE := 5

## Card types. Permanents stay on the battlefield; instants and sorceries
## resolve and go to the graveyard.
const TYPE_LAND := "Land"
const TYPE_CREATURE := "Creature"
const TYPE_INSTANT := "Instant"
const TYPE_SORCERY := "Sorcery"
const TYPE_ENCHANTMENT := "Enchantment"
const TYPE_ARTIFACT := "Artifact"
## A Champion is a commander figure that sits on the battlefield, spends
## Fathom counters to use one ability per turn, and can be attacked directly.
const TYPE_CHAMPION := "Champion"

const PERMANENT_TYPES: Array[String] = [
	TYPE_LAND, TYPE_CREATURE, TYPE_ENCHANTMENT, TYPE_ARTIFACT, TYPE_CHAMPION,
]

## The counter a Champion spends to use its abilities.
const COUNTER_FATHOM := "fathom"

## Mana colors. "C" is colorless mana, which is not a color but is produced
## and spent like one.
const COLORS: Array[String] = ["W", "U", "B", "R", "G"]
const MANA_SYMBOLS: Array[String] = ["W", "U", "B", "R", "G", "C"]

## Sea-themed faction names for each color, used by the UI only.
const COLOR_FACTIONS := {
	"W": "Coral",
	"U": "Abyss",
	"B": "Sunken",
	"R": "Corsair",
	"G": "Kelp",
}

## Keyword abilities the engine understands. Every one is a sea creature's
## habit turned into a rule; anything not listed here is flavor text.
##
## Combat and evasion
const KW_RIPTIDE := "Riptide"            ## Deals combat damage first.
const KW_MAELSTROM := "Maelstrom"        ## Deals combat damage twice.
const KW_BREACH := "Breach"              ## Excess damage carries to the player.
const KW_SCHOOLING := "Schooling"        ## Cannot be blocked by exactly one creature.
const KW_INK := "Ink"                    ## Blockers of this creature deal no damage.
const KW_LURE := "Lure"                  ## Defenders must block this if they can.
const KW_BREAKWATER := "Breakwater"      ## Cannot attack.

## Survival and utility
const KW_VENOMOUS := "Venomous"          ## Any damage it deals is lethal.
const KW_SIPHON := "Siphon"              ## Damage it deals gains you that much life.
const KW_SLEEPLESS := "Sleepless"        ## Attacking does not tap it.
const KW_SURGING := "Surging"            ## Can attack the turn it arrives.
const KW_SLIPPERY := "Slippery"          ## Opponents cannot target it.
const KW_UNSINKABLE := "Unsinkable"      ## Cannot be destroyed.
const KW_MOLT := "Molt"                  ## Survives lethal damage once per turn.

## Depth band abilities
const KW_AMPHIBIOUS := "Amphibious"      ## Blocks adjacent bands as well.
const KW_DIVER := "Diver"                ## Ignores the one-move-per-turn limit.
const KW_ANCHORED := "Anchored"          ## Cannot change depth.
const KW_PRESSURE := "Pressure"          ## +2/+2 in the Abyss, -1/-1 at the Surface.
const KW_SWARM := "Swarm"                ## +1/+0 per other creature you control in its band.

## The shark's habit: every spell you cast in a turn feeds the next one.
const KW_FRENZY := "Frenzy"              ## Gets +1/+1 for each spell you cast this turn.

const ALL_KEYWORDS: Array[String] = [
	KW_RIPTIDE, KW_MAELSTROM, KW_BREACH, KW_SCHOOLING, KW_INK, KW_LURE,
	KW_BREAKWATER, KW_VENOMOUS, KW_SIPHON, KW_SLEEPLESS, KW_SURGING,
	KW_SLIPPERY, KW_UNSINKABLE, KW_MOLT, KW_AMPHIBIOUS, KW_DIVER, KW_ANCHORED,
	KW_PRESSURE, KW_SWARM, KW_FRENZY,
]

## Korean display names, used by the UI only; the rules always use the ids
## above so that renaming a keyword never touches game logic.
const KEYWORD_LABELS_KO := {
	KW_RIPTIDE: "격류", KW_MAELSTROM: "소용돌이", KW_BREACH: "돌파",
	KW_SCHOOLING: "무리", KW_INK: "먹물", KW_LURE: "유인",
	KW_BREAKWATER: "방파제", KW_VENOMOUS: "맹독", KW_SIPHON: "흡혈",
	KW_SLEEPLESS: "불면", KW_SURGING: "급류", KW_SLIPPERY: "미끄러움",
	KW_UNSINKABLE: "불침", KW_MOLT: "탈피", KW_AMPHIBIOUS: "양서",
	KW_DIVER: "잠행", KW_ANCHORED: "정박", KW_PRESSURE: "수압",
	KW_SWARM: "군체", KW_FRENZY: "광란",
}

## Depth bands, shallow to deep.
const DEPTH_ORDER: Array[Depth] = [Depth.SURFACE, Depth.MIDWATER, Depth.ABYSS]

const DEPTH_LABELS := {
	Depth.SURFACE: "Surface",
	Depth.MIDWATER: "Midwater",
	Depth.ABYSS: "Abyss",
}

## How many creatures a player may move between bands each turn. Creatures
## with Diver move on top of this budget.
const DEPTH_MOVES_PER_TURN := 1

## Steps in the order they are played, used by the turn loop.
const TURN_SEQUENCE: Array[Step] = [
	Step.UNTAP,
	Step.UPKEEP,
	Step.DRAW,
	Step.PRECOMBAT_MAIN,
	Step.BEGIN_COMBAT,
	Step.DECLARE_ATTACKERS,
	Step.DECLARE_BLOCKERS,
	Step.COMBAT_DAMAGE,
	Step.END_COMBAT,
	Step.POSTCOMBAT_MAIN,
	Step.END_STEP,
	Step.CLEANUP,
]

## Steps in which no player receives priority.
const NO_PRIORITY_STEPS: Array[Step] = [Step.UNTAP, Step.CLEANUP]

const RARITY_LABELS := {
	Rarity.DRIFTWOOD: "Driftwood",
	Rarity.CORAL: "Coral",
	Rarity.PEARL: "Pearl",
	Rarity.GOLD: "Gold",
	Rarity.RELIC: "Relic",
	Rarity.LEVIATHAN: "Leviathan",
}

const RARITY_LABELS_KO := {
	Rarity.DRIFTWOOD: "표류목",
	Rarity.CORAL: "산호",
	Rarity.PEARL: "진주",
	Rarity.GOLD: "황금",
	Rarity.RELIC: "심연유물",
	Rarity.LEVIATHAN: "리바이어던",
}

## Placeholder colors for the UI; the art pass will replace these.
const RARITY_COLORS := {
	Rarity.DRIFTWOOD: Color(0.62, 0.62, 0.60),
	Rarity.CORAL: Color(0.30, 0.60, 0.90),
	Rarity.PEARL: Color(0.65, 0.45, 0.85),
	Rarity.GOLD: Color(0.90, 0.72, 0.25),
	Rarity.RELIC: Color(0.95, 0.35, 0.45),
	Rarity.LEVIATHAN: Color(1.0, 0.85, 0.35),
}

## Upgrade stars. A card sits at one of these levels in the collection, and
## every copy in a deck is played at that level.
const MIN_STARS := 1
const MAX_STARS := 5

## Flat stat bonus per star for creatures, indexed by star - 1. Kept modest so
## that upgrading is a real gain without making an unupgraded card unplayable.
const STAR_POWER_BONUS: Array[int] = [0, 0, 1, 1, 2]
const STAR_TOUGHNESS_BONUS: Array[int] = [0, 1, 1, 2, 2]

static func star_power_bonus(stars: int) -> int:
	return STAR_POWER_BONUS[clampi(stars, MIN_STARS, MAX_STARS) - 1]

static func star_toughness_bonus(stars: int) -> int:
	return STAR_TOUGHNESS_BONUS[clampi(stars, MIN_STARS, MAX_STARS) - 1]

## How many copies of a card of each rarity a deck may hold.
const RARITY_DECK_LIMIT := {
	Rarity.DRIFTWOOD: 4,
	Rarity.CORAL: 4,
	Rarity.PEARL: 3,
	Rarity.GOLD: 2,
	Rarity.RELIC: 1,
	Rarity.LEVIATHAN: 1,
}

static func rarity_name(rarity: Rarity) -> String:
	return str(RARITY_LABELS.get(rarity, "?"))

static func rarity_name_ko(rarity: Rarity) -> String:
	return str(RARITY_LABELS_KO.get(rarity, "?"))

static func rarity_color(rarity: Rarity) -> Color:
	return RARITY_COLORS.get(rarity, Color.WHITE)

static func deck_limit_for(rarity: Rarity) -> int:
	return int(RARITY_DECK_LIMIT.get(rarity, 4))

static func parse_rarity(text: String) -> Rarity:
	match text.to_lower():
		"coral":
			return Rarity.CORAL
		"pearl":
			return Rarity.PEARL
		"gold":
			return Rarity.GOLD
		"relic", "unique":
			return Rarity.RELIC
		"leviathan", "mythic":
			return Rarity.LEVIATHAN
		_:
			return Rarity.DRIFTWOOD

static func depth_name(depth: Depth) -> String:
	return str(DEPTH_LABELS.get(depth, "?"))

static func parse_depth(text: String) -> Depth:
	match text.to_lower():
		"surface", "0":
			return Depth.SURFACE
		"abyss", "deep", "2":
			return Depth.ABYSS
		_:
			return Depth.MIDWATER

## The band the tide is currently favouring, or -1 for none.
static func favoured_band(tide: Tide) -> int:
	return Depth.SURFACE if tide == Tide.HIGH else Depth.ABYSS

## The tide flips every round, so both players see each state from the same
## side of the table: turns 1-2 are high, 3-4 are low, and so on.
static func tide_for_turn(turn_number: int) -> Tide:
	var round_index := int(float(max(turn_number - 1, 0)) / 2.0)
	return Tide.HIGH if round_index % 2 == 0 else Tide.LOW

static func tide_name(tide: Tide) -> String:
	return "High Tide" if tide == Tide.HIGH else "Low Tide"

static func step_name(step: Step) -> String:
	return Step.keys()[step].capitalize()

static func zone_name(zone: Zone) -> String:
	return Zone.keys()[zone].capitalize()

static func phase_of(step: Step) -> Phase:
	match step:
		Step.UNTAP, Step.UPKEEP, Step.DRAW:
			return Phase.BEGINNING
		Step.PRECOMBAT_MAIN:
			return Phase.PRECOMBAT_MAIN
		Step.BEGIN_COMBAT, Step.DECLARE_ATTACKERS, Step.DECLARE_BLOCKERS, \
		Step.COMBAT_DAMAGE, Step.END_COMBAT:
			return Phase.COMBAT
		Step.POSTCOMBAT_MAIN:
			return Phase.POSTCOMBAT_MAIN
		_:
			return Phase.ENDING

## True in a main phase with an empty stack, i.e. when sorcery-speed actions
## are allowed for the active player.
static func is_main_step(step: Step) -> bool:
	return step == Step.PRECOMBAT_MAIN or step == Step.POSTCOMBAT_MAIN
