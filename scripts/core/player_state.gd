## Everything the rules track about one player.
##
## Zones hold card uids, not objects; the Game owns the uid -> CardInstance
## table. That keeps a player cheap to copy for AI search.
class_name PlayerState
extends RefCounted

var index: int = 0
var name: String = "Player"
var is_ai: bool = false
## Players sharing a team win and lose together and cannot attack each other.
## In a free-for-all every player has their own team.
var team: int = 0
## Position in the turn order.
var seat: int = 0

var life: int = 20
var starting_life: int = 20

var library: Array[int] = []
var hand: Array[int] = []
var battlefield: Array[int] = []
var graveyard: Array[int] = []
var exile: Array[int] = []
## The Abyssal Vault, a side deck fetched from by specific cards.
var vault: Array[int] = []

var mana_pool: Mana.Pool = null

var lands_played_this_turn: int = 0
var max_lands_per_turn: int = 1
## Only one creature may ride the current each turn; Diver ignores this.
var depth_moves_this_turn: int = 0
var extra_draws_this_turn: int = 0

var has_lost: bool = false
var loss_reason: String = ""
## Set when a draw is attempted from an empty library; the loss itself is a
## state-based action so that the rest of the turn still plays out first.
var tried_to_draw_from_empty: bool = false

## Mulligans taken during the opening hand.
var mulligans: int = 0


static func create(p_index: int, p_name: String, p_life: int = 20, p_team: int = -1) -> PlayerState:
	var p := PlayerState.new()
	p.index = p_index
	p.name = p_name
	p.team = p_team if p_team >= 0 else p_index
	p.seat = p_index
	p.life = p_life
	p.starting_life = p_life
	p.mana_pool = Mana.Pool.new()
	return p


func zone_array(zone: GameEnums.Zone) -> Array[int]:
	match zone:
		GameEnums.Zone.LIBRARY:
			return library
		GameEnums.Zone.HAND:
			return hand
		GameEnums.Zone.BATTLEFIELD:
			return battlefield
		GameEnums.Zone.GRAVEYARD:
			return graveyard
		GameEnums.Zone.EXILE:
			return exile
		GameEnums.Zone.VAULT:
			return vault
		_:
			return []


func can_play_land() -> bool:
	return lands_played_this_turn < max_lands_per_turn

func can_move_depth() -> bool:
	return depth_moves_this_turn < GameEnums.DEPTH_MOVES_PER_TURN


func gain_life(amount: int) -> void:
	if amount > 0:
		life += amount

func lose_life(amount: int) -> void:
	if amount > 0:
		life -= amount


func begin_turn() -> void:
	lands_played_this_turn = 0
	depth_moves_this_turn = 0
	extra_draws_this_turn = 0


## --- Snapshots -----------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"life": life, "library": library.duplicate(), "hand": hand.duplicate(),
		"battlefield": battlefield.duplicate(),
		"graveyard": graveyard.duplicate(), "exile": exile.duplicate(),
		"vault": vault.duplicate(),
		"lands": lands_played_this_turn, "moves": depth_moves_this_turn,
		"lost": has_lost, "reason": loss_reason,
		"decked": tried_to_draw_from_empty, "mulligans": mulligans,
		"pool": mana_pool.amounts.duplicate(),
	}


func restore(state: Dictionary) -> void:
	life = int(state["life"])
	library = _ints(state["library"])
	hand = _ints(state["hand"])
	battlefield = _ints(state["battlefield"])
	graveyard = _ints(state["graveyard"])
	exile = _ints(state["exile"])
	vault = _ints(state.get("vault", []))
	lands_played_this_turn = int(state["lands"])
	depth_moves_this_turn = int(state["moves"])
	has_lost = bool(state["lost"])
	loss_reason = str(state["reason"])
	tried_to_draw_from_empty = bool(state["decked"])
	mulligans = int(state["mulligans"])
	mana_pool.amounts = (state["pool"] as Dictionary).duplicate()


static func _ints(value: Variant) -> Array[int]:
	var out: Array[int] = []
	for v in value as Array:
		out.append(int(v))
	return out


func _to_string() -> String:
	return "%s (%d life, %d cards)" % [name, life, hand.size()]
