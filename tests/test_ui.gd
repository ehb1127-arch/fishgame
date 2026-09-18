## Boots the real match screen and exercises every panel it builds.
##
## The UI creates its widgets in code and drives the engine through the same
## action API a player would, so instantiating it for real catches the class
## of bug where a screen still references something the engine renamed.
##
## Whole games are covered by the AI suite; this keeps the rendering work
## bounded, because laying out rich text headlessly is slow.
class_name TestUI
extends RefCounted

const MATCH_SCENE := "res://scenes/match.tscn"


static func run(t: TestFramework, tree: SceneTree) -> void:
	t.start("ui smoke")

	var scene: PackedScene = load(MATCH_SCENE)
	t.check(scene != null, "match scene loads")
	if scene == null:
		return

	var screen := scene.instantiate()
	screen.auto_play_ai = false
	tree.root.add_child(screen)
	t.check(screen.is_inside_tree(), "screen entered the scene tree")
	screen.start_match("corsair_fleet", "leviathan_brood",
		AIPlayer.Skill.NORMAL, MatchRules.standard(), 4242)

	t.check(screen.game != null, "match screen created a game")
	if screen.game == null:
		screen.queue_free()
		return

	# Redrawing on every state change is what the screen does in a real
	# match, but here it would dominate the runtime, so drive the engine
	# directly and refresh at chosen points instead.
	var game: Game = screen.game
	if game.state_changed.is_connected(screen._on_state_changed):
		game.state_changed.disconnect(screen._on_state_changed)

	# A fresh match opens on the mulligan decision, which is a panel too.
	t.eq(game.awaiting, "mulligan", "match opens on the mulligan decision")

	# Play until each of the decision panels has been reached, then
	# build that panel and confirm it produced widgets.
	var stand_in := AIPlayer.create(0, AIPlayer.Skill.NORMAL, 7)
	var opponent := AIPlayer.create(1, AIPlayer.Skill.NORMAL, 8)
	var panels_built := {}
	var steps := 0

	while not game.is_over() and steps < 400 and panels_built.size() < 4:
		steps += 1
		var index: int = game.awaiting_player()
		var phase: String = game.awaiting

		if index == 0 and phase in ["mulligan", "priority", "attackers", "blockers"] \
				and not panels_built.has(phase):
			screen._refresh_actions()
			t.gt(float(screen._actions.get_child_count()), 0.0,
				"%s panel built widgets" % phase)
			panels_built[phase] = true

		var ai: AIPlayer = stand_in if index == 0 else opponent
		var action := ai.decide(game)
		if action == null:
			break
		if not game.perform(action):
			game.perform(GameAction.pass_priority(index))

	t.check(panels_built.has("mulligan"), "mulligan panel was built")
	t.check(panels_built.has("priority"), "priority panel was reached")
	t.gt(float(game.turn_number), 0.0, "play started after the mulligan")
	t.gt(float(steps), 5.0, "the screen drove several decisions")

	# The read-only views must survive a live board too.
	screen._refresh_status()
	screen._refresh_board()
	t.check(not screen._board.text.is_empty(), "board renders")
	t.check(not screen._status.text.is_empty(), "status line renders")

	screen.queue_free()
