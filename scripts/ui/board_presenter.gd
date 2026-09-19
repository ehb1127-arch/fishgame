extends Node

const DepthBoard := preload("res://scripts/ui/depth_board.gd")

var _host
var _view: AbyssDepthBoard


func _ready() -> void:
	call_deferred("_attach")


func _attach() -> void:
	_host = get_parent()
	if _host == null:
		return
	_host._ensure_layout()
	var text_board: RichTextLabel = _host._board
	if text_board == null or text_board.get_parent() == null:
		return

	var holder := text_board.get_parent()
	var index := text_board.get_index()
	text_board.hide()
	text_board.custom_minimum_size = Vector2.ZERO

	_view = DepthBoard.new()
	_view.name = "DepthBoard"
	holder.add_child(_view)
	holder.move_child(_view, index)

	_bind_game()


func _bind_game() -> void:
	if _host == null or _host.game == null:
		call_deferred("_bind_game")
		return
	if not _host.game.state_changed.is_connected(_render):
		_host.game.state_changed.connect(_render)
	_render()


func _render() -> void:
	if _view != null and _host != null and _host.game != null:
		_view.render(_host.game, _host.human_index, _host._chosen_attackers,
			_host._chosen_blocks, _on_card_action)


func _on_card_action(uid: int) -> void:
	if _host == null or _host.game == null:
		return
	match _host.game.awaiting:
		"attackers":
			if uid not in _host.game.possible_attackers(_host.human_index):
				return
			if uid in _host._chosen_attackers:
				_host._chosen_attackers.erase(uid)
			else:
				_host._chosen_attackers.append(uid)
		"blockers":
			var options: Dictionary = _host.game.possible_blocks(_host.human_index)
			if not options.has(uid):
				return
			var attackers := (options[uid] as Array).duplicate()
			var current := int(_host._chosen_blocks.get(uid, -1))
			var position := attackers.find(current)
			if position + 1 >= attackers.size():
				_host._chosen_blocks.erase(uid)
			else:
				_host._chosen_blocks[uid] = attackers[position + 1]
		_:
			return
	_host._refresh_actions()
	_render()

