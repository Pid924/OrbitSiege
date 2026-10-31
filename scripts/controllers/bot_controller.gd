extends Node
## Bot opponent. Searches shots with the same physics simulation the game uses, then
## aims and fires through ordinary match commands, exactly like a human would.

const SpacePhysics := preload("res://scripts/sim/space_physics.gd")
const Weapons := preload("res://scripts/sim/weapons.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")

const THINK_DELAY := 0.7
const FRAME_BUDGET_USEC := 6000
const AIM_SPEED := 1.6
const CHARGE_TIME := 1.6
const FRIENDLY_RADIUS := 60.0

## Shot error (standard deviation). Lower = harder bot.
@export var angle_error_deg := 0.8
@export var power_error := 0.01

enum State { IDLE, WAIT, SEARCH, AIM, CHARGE }

var game
var team := 1
var unit = null
var state := State.IDLE
var wait := 0.0
var candidates: Array = []  # [angle, power]
var refined := false
var best_angle := 0.0
var best_power := 0.6
var best_score := INF
var charge := 0.0
var rng := RandomNumberGenerator.new()


func setup(game_ref, team_id: int) -> void:
	game = game_ref
	team = team_id
	rng.randomize()
	var level: Array = GameSettings.BOT_LEVELS[GameSettings.bot_level]
	angle_error_deg = level[1]
	power_error = level[2]


func begin_turn(u) -> void:
	unit = u
	state = State.WAIT
	wait = THINK_DELAY
	best_score = INF
	refined = false
	charge = 0.0
	candidates.clear()
	for a in range(-150, 151, 5):
		for p in range(30, 101, 7):
			candidates.append([deg_to_rad(a), p / 100.0])
	game.submit_command({"type": "weapon", "team": team, "index": Weapons.LIST.find(_pick_weapon())})


## Mostly plasma; uses Last Stand when unlocked, and the special shells now and then.
## The bot never picks the healer, it only aims at enemies.
func _pick_weapon() -> String:
	if game.weapon_available(team, "rage") and rng.randf() < 0.8:
		return "rage"
	var weights := {"plasma": 5.0, "cluster": 1.0, "driller": 1.0, "double": 1.0, "triple": 1.0, "snare": 0.7}
	var total := 0.0
	for id in weights:
		if game.weapon_available(team, id):
			total += weights[id]
	var roll := rng.randf() * total
	for id in weights:
		if game.weapon_available(team, id):
			roll -= weights[id]
			if roll <= 0.0:
				return id
	return "plasma"


func end_turn() -> void:
	unit = null
	state = State.IDLE


func _physics_process(delta: float) -> void:
	if unit == null or not game.is_turn_of(team):
		return
	match state:
		State.WAIT:
			wait -= delta
			if wait <= 0.0:
				state = State.SEARCH
		State.SEARCH:
			_search_step()
		State.AIM:
			var diff: float = best_angle - unit.aim_angle
			var step := AIM_SPEED * delta
			if absf(diff) <= step:
				game.submit_command({"type": "aim", "team": team, "angle": best_angle})
				state = State.CHARGE
			else:
				game.submit_command({"type": "aim", "team": team, "angle": unit.aim_angle + signf(diff) * step})
		State.CHARGE:
			charge = minf(best_power, charge + delta / CHARGE_TIME)
			game.submit_command({"type": "charge", "team": team, "value": charge})
			if charge >= best_power:
				game.submit_command({"type": "fire", "team": team, "angle": best_angle, "power": best_power})
				state = State.IDLE


func _search_step() -> void:
	var start := Time.get_ticks_usec()
	var targets: PackedVector2Array = game.unit_hit_points()
	while not candidates.is_empty() and Time.get_ticks_usec() - start < FRAME_BUDGET_USEC:
		var c: Array = candidates.pop_back()
		var score := _score_shot(c[0], c[1], targets)
		if score < best_score:
			best_score = score
			best_angle = c[0]
			best_power = c[1]
	if not candidates.is_empty():
		return
	if not refined and best_score < INF:
		# Second pass: fine grid around the best coarse shot.
		refined = true
		for da in range(-4, 5):
			for dp in range(-5, 6):
				candidates.append([best_angle + deg_to_rad(da), clampf(best_power + dp * 0.01, 0.05, 1.0)])
		return
	if best_score == INF:
		# Nothing lands: lob something toward the nearest enemy.
		var enemy = _nearest_enemy()
		var to_enemy: Vector2 = (enemy.body_center() - unit.position) if enemy else unit.up
		best_angle = clampf(unit.up.angle_to(to_enemy.normalized() + unit.up), -2.6, 2.6)
		best_power = 0.6
	best_angle += deg_to_rad(rng.randfn(0.0, angle_error_deg))
	best_power = clampf(best_power + rng.randfn(0.0, power_error), 0.05, 1.0)
	state = State.AIM


func _score_shot(angle: float, power: float, targets: PackedVector2Array) -> float:
	var dir: Vector2 = unit.up.rotated(angle)
	var muzzle: Vector2 = unit.position + unit.up * 10.0 + dir * 14.0
	var impact = game.physics.simulate_shot(muzzle, dir * power * SpacePhysics.MAX_SPEED, game.terrain, targets)
	if impact == null:
		return INF
	var score := INF
	for u in game.units:
		if not u.alive:
			continue
		var d: float = impact.distance_to(u.body_center())
		if u.team == team:
			if d < FRIENDLY_RADIUS:
				score += 500.0
		else:
			score = minf(score, d)
	return score


func _nearest_enemy():
	var best = null
	var best_d := INF
	for u in game.units:
		if u.alive and u.team != team:
			var d: float = u.position.distance_to(unit.position)
			if d < best_d:
				best_d = d
				best = u
	return best
