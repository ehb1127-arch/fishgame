## Finds triggered abilities that should fire for a game event.
##
## A triggered ability looks like:
##   {"kind": "triggered", "trigger": "self_etb",
##    "targets": [...], "effects": [...], "condition": {...}}
##
## Events are emitted by the Game; whatever matches is put on the stack the
## next time a player would receive priority.
class_name Triggers
extends RefCounted

## Triggers that fire from a permanent that has already left the battlefield
## (it saw itself die), so the battlefield scan alone would miss them.
const LEAVE_TRIGGERS: Array[String] = ["self_dies"]


## Returns [{"source": CardInstance, "ability": Dictionary, "event": Dictionary}]
## for everything that fires. [param event] carries whatever the specific event
## provides, e.g. {"uid": 12, "player": 0}.
static func collect(game, event_name: String, event: Dictionary) -> Array:
	var fired: Array = []

	for p in game.players:
		for uid in p.battlefield.duplicate():
			var src: CardInstance = game.get_card(uid)
			if src == null:
				continue
			_check_card(game, src, event_name, event, fired)

	# Dies triggers come from the card as it existed on the battlefield, which
	# the Game passes in explicitly.
	if event_name == "dies" and event.has("uid"):
		var dying: CardInstance = game.get_card(int(event["uid"]))
		if dying != null:
			_check_card(game, dying, event_name, event, fired, true)

	return fired


static func _check_card(game, src: CardInstance, event_name: String, event: Dictionary,
		fired: Array, leaving: bool = false) -> void:
	for ability in src.data.abilities_of_kind("triggered"):
		var a := ability as Dictionary
		var trig := str(a.get("trigger", ""))
		if not _matches(game, src, a, trig, event_name, event, leaving):
			continue
		var ctx := {
			"controller": src.controller_index,
			"source": src,
			"targets": [],
			"target_specs": a.get("targets", []) as Array,
			"x": 0,
		}
		if a.has("condition") and not Effects.check_condition(game, a["condition"] as Dictionary, ctx):
			continue
		fired.append({"source": src, "ability": a, "event": event.duplicate()})


static func _matches(game, src: CardInstance, ability: Dictionary, trig: String,
		event_name: String, event: Dictionary, leaving: bool) -> bool:
	var subject_uid := int(event.get("uid", -1))
	var subject: CardInstance = game.get_card(subject_uid) if subject_uid >= 0 else null
	var event_player := int(event.get("player", -1))

	match trig:
		"self_etb":
			return event_name == "enters_battlefield" and subject_uid == src.uid
		"other_etb":
			if event_name != "enters_battlefield" or subject_uid == src.uid or subject == null:
				return false
			return subject_matches(game, ability, src, subject)
		"self_dies":
			return event_name == "dies" and subject_uid == src.uid and leaving
		"other_dies":
			if event_name != "dies" or subject_uid == src.uid or subject == null:
				return false
			return subject_matches(game, ability, src, subject)
		"self_attacks":
			return event_name == "attacks" and subject_uid == src.uid
		"self_blocks":
			return event_name == "blocks" and subject_uid == src.uid
		"self_deals_combat_damage_to_player":
			return event_name == "combat_damage_to_player" and subject_uid == src.uid
		"upkeep":
			return event_name == "upkeep" and event_player == src.controller_index
		"opponent_upkeep":
			return event_name == "upkeep" and event_player != src.controller_index
		"end_step":
			return event_name == "end_step" and event_player == src.controller_index
		"draw_step":
			return event_name == "draw_step" and event_player == src.controller_index
		"you_cast_spell":
			if event_name != "spell_cast" or event_player != src.controller_index:
				return false
			return subject == null or subject_matches(game, ability, src, subject)
		"opponent_cast_spell":
			if event_name != "spell_cast" or event_player == src.controller_index:
				return false
			return subject == null or subject_matches(game, ability, src, subject)
		"you_gain_life":
			return event_name == "life_gained" and event_player == src.controller_index
		_:
			return false


## Filter check used by triggers that name a filter on the triggering object.
static func subject_matches(game, ability: Dictionary, src: CardInstance, subject: CardInstance) -> bool:
	if subject == null:
		return true
	var f := ability.get("trigger_filter", {}) as Dictionary
	if f.is_empty():
		return true
	var scope := str(f.get("controller", "any"))
	if scope == "you" and subject.controller_index != src.controller_index:
		return false
	if scope == "opponent" and subject.controller_index == src.controller_index:
		return false
	return Targeting.matches_filter(game, f.get("filter", f) as Dictionary, subject)
