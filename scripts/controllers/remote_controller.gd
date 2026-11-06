extends Node
## The other phone's team in an online match. Its commands arrive through the network
## (match.gd `_net_physics`), so this controller has nothing to do on its own.

var game
var team := 1


func setup(game_ref, team_id: int) -> void:
	game = game_ref
	team = team_id


func begin_turn(_u) -> void:
	pass


func end_turn() -> void:
	pass
