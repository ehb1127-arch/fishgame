## One decision a player can make. The engine only ever changes state through
## an action, which is what makes the AI and the replay log possible: the UI
## asks for legal actions, hands one back, and the engine advances.
class_name GameAction
extends RefCounted

enum Kind {
	PASS_PRIORITY,
	PLAY_LAND,
	CAST_SPELL,
	ACTIVATE_ABILITY,
	MOVE_DEPTH,
	DECLARE_ATTACKERS,
	DECLARE_BLOCKERS,
	MULLIGAN,
	KEEP_HAND,
	CONCEDE,
}

var kind: Kind = Kind.PASS_PRIORITY
var player_index: int = 0
## The card being played, cast, or whose ability is activated.
var card_uid: int = 0
## Index into the source card's ability list, for ACTIVATE_ABILITY.
var ability_index: int = -1
## One entry per target slot: {"type": "card", "uid": n} or
## {"type": "player", "index": n}.
var targets: Array = []
var x_value: int = 0
## For MOVE_DEPTH: how many bands to move, negative towards the surface.
var depth_delta: int = 0
## For DECLARE_ATTACKERS: the uids that attack.
var attackers: Array[int] = []
## For DECLARE_BLOCKERS: blocker uid -> attacker uid.
var blocks: Dictionary = {}
## Human-readable label, filled in by the engine for the UI and the log.
var description: String = ""


static func pass_priority(player: int) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.PASS_PRIORITY
	a.player_index = player
	a.description = "Pass"
	return a

static func play_land(player: int, uid: int) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.PLAY_LAND
	a.player_index = player
	a.card_uid = uid
	return a

static func cast_spell(player: int, uid: int, targets_in: Array = [], x: int = 0) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.CAST_SPELL
	a.player_index = player
	a.card_uid = uid
	a.targets = targets_in.duplicate(true)
	a.x_value = x
	return a

static func activate(player: int, uid: int, index: int, targets_in: Array = [], x: int = 0) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.ACTIVATE_ABILITY
	a.player_index = player
	a.card_uid = uid
	a.ability_index = index
	a.targets = targets_in.duplicate(true)
	a.x_value = x
	return a

static func move_depth(player: int, uid: int, delta: int) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.MOVE_DEPTH
	a.player_index = player
	a.card_uid = uid
	a.depth_delta = delta
	return a

static func declare_attackers(player: int, uids: Array[int]) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.DECLARE_ATTACKERS
	a.player_index = player
	a.attackers = uids.duplicate()
	return a

static func declare_blockers(player: int, assignment: Dictionary) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.DECLARE_BLOCKERS
	a.player_index = player
	a.blocks = assignment.duplicate()
	return a

static func mulligan(player: int) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.MULLIGAN
	a.player_index = player
	a.description = "Mulligan"
	return a

static func keep_hand(player: int) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.KEEP_HAND
	a.player_index = player
	a.description = "Keep"
	return a

static func concede(player: int) -> GameAction:
	var a := GameAction.new()
	a.kind = Kind.CONCEDE
	a.player_index = player
	a.description = "Concede"
	return a


static func card_target(uid: int) -> Dictionary:
	return {"type": "card", "uid": uid}

static func player_target(index: int) -> Dictionary:
	return {"type": "player", "index": index}


func _to_string() -> String:
	if not description.is_empty():
		return description
	return "%s(p%d, #%d)" % [Kind.keys()[kind], player_index, card_uid]
