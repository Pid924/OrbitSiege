extends Node2D
## Match controller: owns the world, the turn order and the command queue.
##
## Every game-changing action goes through submit_command() as a plain Dictionary.
## Local players and bots already work this way, so online play can forward the same
## dictionaries over RPC (host validates and applies them) without touching game rules.

const SpacePhysics := preload("res://scripts/sim/space_physics.gd")
const Weapons := preload("res://scripts/sim/weapons.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const Starfield := preload("res://scripts/world/starfield.gd")
const Unit := preload("res://scripts/game/unit.gd")
const Projectile := preload("res://scripts/game/projectile.gd")
const Explosion := preload("res://scripts/game/explosion.gd")
const FloatingText := preload("res://scripts/game/floating_text.gd")
const PlayerController := preload("res://scripts/controllers/player_controller.gd")
const BotController := preload("res://scripts/controllers/bot_controller.gd")
const Hud := preload("res://scripts/ui/hud.gd")

enum Phase { AIMING, FLYING, SETTLING, GAME_OVER }

const TURN_TIME := 30.0
const UNITS_PER_TEAM := 3
const PLANET_COUNT := 5
const MAX_WIND := 55.0
const TEAM_COLORS := [Color(0.35, 0.8, 1.0), Color(1.0, 0.45, 0.4)]
const TEAM_NAMES := ["Player", "Bot"]
const UNIT_NAMES := [["Nova", "Orion", "Vega"], ["Zr-1", "Zr-2", "Zr-3"]]

signal turn_started(team: int, unit)
signal game_over(winner: int)

var match_seed := 0
var rng := RandomNumberGenerator.new()
var physics := SpacePhysics.new()
var terrain
var units: Array = []
var projectiles: Array = []
var controllers: Array = []
var command_queue: Array = []

var phase := Phase.AIMING
var current_team := 1  # flipped to 0 by the first turn
var team_cursor := [0, 0]
var team_weapon := [0, 0]
var active_unit = null
var turn_time_left := TURN_TIME
var settle_time := 0.0
var turn_number := 0
var winner := -1

var autoplay := false
var camera: Camera2D
var shake := 0.0


func _ready() -> void:
	match_seed = int(Time.get_unix_time_from_system()) ^ randi()
	rng.seed = match_seed
	_build_world()
	_start_turn()


func _build_world() -> void:
	var stars := Starfield.new()
	add_child(stars)
	stars.generate(rng)

	_generate_planets()
	terrain = Terrain.new()
	add_child(terrain)
	terrain.generate(physics, rng)
	_spawn_units()

	# `-- --autoplay` lets two bots play each other (demo / smoke test).
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	controllers = [BotController.new() if autoplay else PlayerController.new(), BotController.new()]
	for team in controllers.size():
		add_child(controllers[team])
		controllers[team].setup(self, team)

	camera = Camera2D.new()
	camera.position = Vector2(Terrain.WIDTH, Terrain.HEIGHT) / 2.0
	add_child(camera)

	var hud := Hud.new()
	add_child(hud)
	hud.setup(self)


func _generate_planets() -> void:
	var tries := 0
	while (physics.planets.size() < PLANET_COUNT and tries < 2000) or physics.planets.size() < 3:
		tries += 1
		var r := rng.randf_range(70.0, 140.0)
		var c := Vector2(rng.randf_range(r + 50.0, Terrain.WIDTH - r - 50.0), rng.randf_range(r + 90.0, Terrain.HEIGHT - r - 40.0))
		var ok := true
		for p in physics.planets:
			if c.distance_to(p.center) < r + p.radius + 110.0:
				ok = false
				break
		if ok:
			physics.add_planet(c, r)


func _spawn_units() -> void:
	# Team 0 lives on the left-most planets, team 1 on the right-most ones.
	var sorted := physics.planets.duplicate()
	sorted.sort_custom(func(a, b): return a.center.x < b.center.x)
	var half := maxi(1, sorted.size() / 2)
	var homes := [sorted.slice(0, half), sorted.slice(sorted.size() - half)]
	var id := 0
	for team in 2:
		for i in UNITS_PER_TEAM:
			var planet: Dictionary = homes[team][i % homes[team].size()]
			var unit := Unit.new()
			unit.position = _find_spawn_point(planet)
			add_child(unit)
			unit.setup(id, team, UNIT_NAMES[team][i], TEAM_COLORS[team], physics, terrain)
			unit.grounded = true
			units.append(unit)
			id += 1


func _find_spawn_point(planet: Dictionary) -> Vector2:
	var center: Vector2 = planet.center
	var radius: float = planet.radius
	var best := center + Vector2.UP * radius
	for attempt in 40:
		# Prefer the upper half of the planet, it reads better on screen.
		var angle := rng.randf_range(-PI * 0.9, -PI * 0.1) if attempt < 30 else rng.randf() * TAU
		var dir := Vector2.from_angle(angle)
		var pos := center + dir * radius * 1.4
		while not terrain.is_solid(pos - dir) and pos.distance_to(center) > 1.0:
			pos -= dir
		if not Rect2(10, 10, Terrain.WIDTH - 20, Terrain.HEIGHT - 20).has_point(pos):
			continue
		if physics.up_at(pos).dot(dir) < 0.9:
			continue  # another planet pulls harder here
		var clear := true
		for u in units:
			if u.position.distance_to(pos) < 70.0:
				clear = false
				break
		if clear:
			return pos
		best = pos
	return best


# --- Commands -------------------------------------------------------------

## Single entry point for controllers (local player, bot, and later network peers).
## Command shapes:
##   {"type": "walk", "team": t, "dir": -1|1}
##   {"type": "aim", "team": t, "angle": float}
##   {"type": "charge", "team": t, "value": 0..1}      (cosmetic)
##   {"type": "weapon", "team": t, "index": int}
##   {"type": "fire", "team": t, "angle": float, "power": 0..1}
func submit_command(cmd: Dictionary) -> void:
	command_queue.append(cmd)


func is_turn_of(team: int) -> bool:
	return phase == Phase.AIMING and current_team == team and active_unit != null


func current_weapon_id(team: int = -1) -> String:
	if team < 0:
		team = current_team
	return Weapons.LIST[team_weapon[team]]


func _apply_command(cmd: Dictionary) -> void:
	if not is_turn_of(cmd.get("team", -1)):
		return
	match cmd.get("type", ""):
		"walk":
			active_unit.walk(int(cmd.dir), 1.0 / 60.0)
		"aim":
			active_unit.aim_angle = clampf(cmd.angle, -Unit.AIM_LIMIT, Unit.AIM_LIMIT)
		"charge":
			active_unit.charge = clampf(cmd.value, 0.0, 1.0)
		"weapon":
			team_weapon[current_team] = posmod(int(cmd.index), Weapons.LIST.size())
		"fire":
			_fire(clampf(cmd.angle, -Unit.AIM_LIMIT, Unit.AIM_LIMIT), clampf(cmd.power, 0.05, 1.0))


func _fire(angle: float, power: float) -> void:
	active_unit.aim_angle = angle
	active_unit.charge = 0.0
	var vel: Vector2 = active_unit.aim_dir() * power * SpacePhysics.MAX_SPEED
	_spawn_projectile(active_unit.muzzle(), vel, current_weapon_id())
	phase = Phase.FLYING
	controllers[current_team].end_turn()


func _spawn_projectile(pos: Vector2, vel: Vector2, weapon: String, ignore_time := 0.15) -> void:
	var p := Projectile.new()
	p.setup(self, pos, vel, weapon, ignore_time)
	add_child(p)
	projectiles.append(p)


# --- Simulation -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	while not command_queue.is_empty():
		_apply_command(command_queue.pop_front())
	for u in units:
		u.tick(delta)
	match phase:
		Phase.AIMING:
			turn_time_left -= delta
			if turn_time_left <= 0.0 or not active_unit.alive:
				controllers[current_team].end_turn()
				_begin_settling()
		Phase.FLYING:
			for p in projectiles.duplicate():
				p.tick(delta)
				if p.done:
					projectiles.erase(p)
					p.queue_free()
			if projectiles.is_empty():
				_begin_settling()
		Phase.SETTLING:
			settle_time -= delta
			if (settle_time <= 0.0 and _all_grounded()) or settle_time < -4.0:
				_end_turn()


func _process(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 30.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		if phase == Phase.GAME_OVER or event.ctrl_pressed:
			get_tree().reload_current_scene()


func _begin_settling() -> void:
	phase = Phase.SETTLING
	settle_time = 0.8


func _all_grounded() -> bool:
	for u in units:
		if u.alive and not u.grounded:
			return false
	return true


func unit_at(pos: Vector2):
	var r_sq := SpacePhysics.UNIT_HIT_RADIUS * SpacePhysics.UNIT_HIT_RADIUS
	for u in units:
		if u.alive and u.body_center().distance_squared_to(pos) < r_sq:
			return u
	return null


func unit_hit_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for u in units:
		if u.alive:
			pts.append(u.body_center())
	return pts


func on_detonation(pos: Vector2, weapon_id: String, vel: Vector2) -> void:
	var w := Weapons.get_def(weapon_id)
	var radius: float = w.radius
	terrain.carve(pos, radius)
	var reach := radius * 1.5
	for u in units:
		if not u.alive:
			continue
		var c: Vector2 = u.body_center()
		var d := c.distance_to(pos)
		if d >= reach:
			continue
		var f := 1.0 - d / reach
		var dmg := int(round(w.damage * f))
		u.take_damage(dmg)
		_float_text(c + Vector2(0, -30), "-%d" % dmg, Color(1, 0.85, 0.4))
		var dir: Vector2 = (c - pos).normalized() if d > 0.5 else u.up
		u.knock((dir + u.up * 0.5).normalized() * w.knockback * f)
	if w.has("bomblets"):
		var back: Vector2 = -vel.normalized() if vel.length_squared() > 1.0 else physics.up_at(pos)
		for i in int(w.bomblets):
			var dir := back.rotated(rng.randf_range(-1.1, 1.1))
			_spawn_projectile(pos + dir * 6.0, dir * rng.randf_range(180.0, 300.0), "bomblet", 0.05)
	var fx := Explosion.new()
	fx.setup(pos, radius, w.color)
	add_child(fx)
	shake = maxf(shake, radius * 0.3)


func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var t := FloatingText.new()
	t.setup(pos, text, color)
	add_child(t)


# --- Turns ----------------------------------------------------------------

func alive_count(team: int) -> int:
	var n := 0
	for u in units:
		if u.alive and u.team == team:
			n += 1
	return n


func _end_turn() -> void:
	if active_unit:
		active_unit.is_active = false
		active_unit.charge = 0.0
	var a := alive_count(0)
	var b := alive_count(1)
	if a == 0 or b == 0:
		phase = Phase.GAME_OVER
		winner = -1 if a == b else (0 if a > 0 else 1)
		active_unit = null
		if autoplay:
			print("game over after %d turns, winner: %d" % [turn_number, winner])
		game_over.emit(winner)
		return
	_start_turn()


func _start_turn() -> void:
	turn_number += 1
	current_team = 1 - current_team
	var team_units := units.filter(func(u): return u.team == current_team)
	for i in team_units.size():
		var idx: int = (team_cursor[current_team] + i) % team_units.size()
		if team_units[idx].alive:
			active_unit = team_units[idx]
			team_cursor[current_team] = idx + 1
			break
	physics.wind = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, MAX_WIND)
	active_unit.is_active = true
	turn_time_left = TURN_TIME
	command_queue.clear()
	phase = Phase.AIMING
	controllers[current_team].begin_turn(active_unit)
	if autoplay:
		print("turn %d team %d %s hp=%d/%d" % [turn_number, current_team, active_unit.unit_name, alive_count(0), alive_count(1)])
	turn_started.emit(current_team, active_unit)
