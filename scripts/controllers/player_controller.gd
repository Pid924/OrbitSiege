extends Node
## Local human input. Converts keys into match commands; never touches units directly.

const Weapons := preload("res://scripts/sim/weapons.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")

const AIM_SPEED := 1.4
const FINE_AIM_SPEED := 0.3

var game
var team := 0
var unit = null
var charging := false
var charge := 0.0


func setup(game_ref, team_id: int) -> void:
	game = game_ref
	team = team_id


func begin_turn(u) -> void:
	unit = u
	charging = false
	charge = 0.0


func end_turn() -> void:
	unit = null
	charging = false
	charge = 0.0


func _physics_process(delta: float) -> void:
	if unit == null or not game.is_turn_of(team):
		return
	var walk := 0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		walk -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		walk += 1
	if walk != 0 and not charging:
		game.submit_command({"type": "walk", "team": team, "dir": walk})

	var aim := 0.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		aim -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		aim += 1.0
	if aim != 0.0:
		var speed := FINE_AIM_SPEED if Input.is_physical_key_pressed(KEY_SHIFT) else AIM_SPEED
		game.submit_command({"type": "aim", "team": team, "angle": unit.aim_angle + aim * speed * delta})

	if Input.is_physical_key_pressed(KEY_SPACE):
		charging = true
		charge = minf(1.0, charge + delta / GameSettings.CHARGE_OPTIONS[GameSettings.charge_speed][1])
		game.submit_command({"type": "charge", "team": team, "value": charge})
	elif charging:
		charging = false
		game.submit_command({"type": "fire", "team": team, "angle": unit.aim_angle, "power": charge})


func _unhandled_input(event: InputEvent) -> void:
	if unit == null or not game.is_turn_of(team):
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var index: int = game.team_weapon[team]
	match event.physical_keycode:
		KEY_Q:
			index -= 1
		KEY_E, KEY_TAB:
			index += 1
		_:
			var n: int = 9 if event.physical_keycode == KEY_0 else event.physical_keycode - KEY_1
			if n < 0 or n >= Weapons.LIST.size():
				return
			index = n
	# Q/E skip weapons that cannot be used right now.
	var step := 1 if event.physical_keycode in [KEY_E, KEY_TAB] else (-1 if event.physical_keycode == KEY_Q else 0)
	for i in Weapons.LIST.size():
		if step == 0 or game.weapon_available(team, Weapons.LIST[posmod(index, Weapons.LIST.size())]):
			break
		index += step
	game.submit_command({"type": "weapon", "team": team, "index": index})
