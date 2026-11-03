extends Node2D
## Match controller: owns the world, the turn order and the command queue.
##
## Every game-changing action goes through submit_command() as a plain Dictionary.
## Local players and bots already work this way, so online play can forward the same
## dictionaries over RPC (host validates and applies them) without touching game rules.

const SpacePhysics := preload("res://scripts/sim/space_physics.gd")
const Weapons := preload("res://scripts/sim/weapons.gd")
const L := preload("res://scripts/game/i18n.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const Starfield := preload("res://scripts/world/starfield.gd")
const Unit := preload("res://scripts/game/unit.gd")
const Projectile := preload("res://scripts/game/projectile.gd")
const Explosion := preload("res://scripts/game/explosion.gd")
const FloatingText := preload("res://scripts/game/floating_text.gd")
const PlayerController := preload("res://scripts/controllers/player_controller.gd")
const BotController := preload("res://scripts/controllers/bot_controller.gd")
const Hud := preload("res://scripts/ui/hud.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")
const AimGuide := preload("res://scripts/game/aim_guide.gd")
const CameraRig := preload("res://scripts/game/camera_rig.gd")
const SkyBeam := preload("res://scripts/game/sky_beam.gd")
const Crate := preload("res://scripts/game/crate.gd")

enum Phase { AIMING, FLYING, SETTLING, GAME_OVER }

const TURN_TIME := 30.0
const UNITS_PER_TEAM := 3
const PLANET_COUNT := 5
var planet_count := PLANET_COUNT
var planet_radius := Vector2(70, 140)
const DRIFT_GRAVITY := 260.0
const ABYSS_MARGIN := 70.0  # island stages: below world height minus this, a unit is lost in the gas giant
const REFIRE_DELAY := 0.35
const MAX_WIND := 55.0
const MAX_CRATES := 4
const EVENT_CHANCE := 0.4
## Round events last a whole round. Each has a random size: damage and blast -20%..+20%
## (steps of 5%), turn time -10..+10 s. Applied in _fire and _start_turn.
const EVENT_KINDS := ["dmg", "time", "blast"]
## Crates hold one extra use of any weapon except the unlimited Plasma Shell.
const AMMO_LOOT := ["cluster", "driller", "double", "triple", "rage", "snare", "mender", "seeker", "sky"]
const TEAM_COLORS := [Color(0.35, 0.8, 1.0), Color(1.0, 0.45, 0.4)]
const TEAM_NAMES := ["ผู้เล่น", "บอท"]
const UNIT_NAMES := [["Nova", "Orion", "Vega"], ["Zr-1", "Zr-2", "Zr-3"]]

signal turn_started(team: int, unit)
signal round_started(round_number: int, first_team: int, coin_toss: bool)
signal game_over(winner: int)

var stage := "drift"
var world_size := Vector2(1600, 900)
var abyss_y := INF
var match_seed := 0
var rng := RandomNumberGenerator.new()
var physics := SpacePhysics.new()
var terrain
var units: Array = []
var projectiles: Array = []
var controllers: Array = []
var carve_mult := 1.0  # stage-wide crater size (brittle ground on Shatter Reef)
## Units start at least this far apart, so no single blast (Sky Lance is the widest) hits two at once.
const MIN_SPAWN_GAP := 250.0
var spawn_gap := MIN_SPAWN_GAP  # per stage, see GameSettings "spawn_gap"
var command_queue: Array = []

var phase := Phase.AIMING
var current_team := 1  # flipped to 0 by the first turn
var team_weapon := [0, 0]
var team_ammo := [{}, {}]  # weapon id -> uses left, only for weapons with limited ammo
var shots_left := 0
var refire_timer := 0.0
var last_shot := {}
var crates: Array = []
## A round = every living unit plays once. Round 1 starts with a coin toss for the first team;
## later rounds start with whoever used the least time last round, teams still taking turns.
var round_number := 0
var round_queue: Array = []  # units still to play this round, in order
var time_used := {}  # unit_id -> seconds spent aiming this round
var last_round_time := {}  # time_used of the previous round, for the HUD
var turn_start_time := TURN_TIME
var round_event := {}  # {"kind": "dmg"|"time"|"blast", "value": int} or {} for a calm round
var team_boost := [0.0, 0.0]  # extra damage for the team's next shot, from Nano Mender
var shot_dmg_mult := 1.0
var shot_radius_mult := 1.0
var pending_strikes: Array = []  # {"pos", "axis", "weapon", "time"} for sky beams on their way down
var last_power := {}  # unit_id -> power of that unit's previous shot, for the aim guide
var active_unit = null
var turn_time_left := TURN_TIME
var settle_time := 0.0
var turn_number := 0
var winner := -1

var autoplay := false
var camera
var aim_guide


func _ready() -> void:
	ThemeDB.fallback_font = preload("res://assets/fonts/ui_font.tres")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			GameSettings.stage = arg.trim_prefix("--stage=")
	stage = GameSettings.stage if GameSettings.STAGES.has(GameSettings.stage) else "drift"
	match_seed = int(Time.get_unix_time_from_system()) ^ randi()
	rng.seed = match_seed
	_build_world()
	_start_turn()


func _build_world() -> void:
	var cfg: Dictionary = GameSettings.STAGES[stage]
	spawn_gap = cfg.get("spawn_gap", MIN_SPAWN_GAP)
	planet_radius = cfg.get("planet_radius", Vector2(70, 140))
	planet_count = cfg.get("planet_count", PLANET_COUNT)
	world_size = cfg.size
	carve_mult = cfg.get("carve_mult", 1.0)
	var stars := Starfield.new()
	add_child(stars)
	stars.generate(rng, world_size)

	terrain = Terrain.new()
	terrain.set_size(world_size)
	add_child(terrain)
	if cfg.kind == "islands":
		abyss_y = world_size.y - ABYSS_MARGIN
		stars.abyss = true
		stars.abyss_y = abyss_y
		physics.uniform_gravity = Vector2(0, DRIFT_GRAVITY)
		physics.bounds = Rect2(-400, -3000, world_size.x + 800, 3000 + abyss_y)
	else:
		physics.bounds = Rect2(Vector2(-250, -250), world_size + Vector2(500, 500))
	# Some maps leave no room to start everyone far enough apart; make a new map then.
	var spawns := []
	for map_try in 8:
		if cfg.kind == "islands":
			spawns = _choose_spawns(_island_homes(terrain.generate_islands(rng, cfg)))
		else:
			physics.planets.clear()
			_generate_planets()
			terrain.generate(physics, rng)
			spawns = _choose_spawns(_planet_homes())
		if _min_pair_gap(spawns) >= spawn_gap:
			break
	_create_units(spawns)

	for team in 2:
		for id in Weapons.LIST:
			var w := Weapons.get_def(id)
			if w.has("ammo") and not (GameSettings.debug and team == 0):
				team_ammo[team][id] = int(w.ammo)

	aim_guide = AimGuide.new()
	add_child(aim_guide)

	# `-- --autoplay` lets two bots play each other (demo / smoke test).
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	controllers = [BotController.new() if autoplay else PlayerController.new(), BotController.new()]
	for team in controllers.size():
		add_child(controllers[team])
		controllers[team].setup(self, team)

	camera = CameraRig.new()
	add_child(camera)
	camera.setup(Rect2(Vector2.ZERO, world_size), Vector2(0, 160) if abyss_y < INF else Vector2.ZERO)

	var hud := Hud.new()
	add_child(hud)
	hud.setup(self)


func _generate_planets() -> void:
	if planet_count == 1:
		# One giant world in the middle; shells curve around it.
		physics.add_planet(Vector2(world_size.x * 0.5, world_size.y * 0.56), rng.randf_range(planet_radius.x, planet_radius.y))
		return
	var tries := 0
	while (physics.planets.size() < planet_count and tries < 2000) or physics.planets.size() < mini(3, planet_count):
		tries += 1
		var r := rng.randf_range(planet_radius.x, planet_radius.y)
		var c := Vector2(rng.randf_range(r + 50.0, world_size.x - r - 50.0), rng.randf_range(r + 90.0, world_size.y - r - 40.0))
		var ok := true
		for p in physics.planets:
			if c.distance_to(p.center) < r + p.radius + 110.0:
				ok = false
				break
		if ok:
			physics.add_planet(c, r)


## Spawn spots per team: team 0 on the left-most planets, team 1 on the right-most ones.
func _planet_homes() -> Array:
	var sorted := physics.planets.duplicate()
	sorted.sort_custom(func(a, b): return a.center.x < b.center.x)
	# With an odd count both teams may use the middle planet, so each has room to spread out.
	var half := maxi(1, (sorted.size() + 1) / 2)
	var homes := [sorted.slice(0, half), sorted.slice(sorted.size() - half)]
	if sorted.size() == 1:
		# One planet: team 0 on its left side, team 1 on its right side.
		var center: Vector2 = sorted[0].center
		var spots := _planet_spots(sorted)
		return [spots.filter(func(s): return s.x < center.x - 60.0), spots.filter(func(s): return s.x > center.x + 60.0)]
	return homes.map(func(h): return _planet_spots(h))


## Spawn spots per team: team 0 on the left islands, team 1 on the right ones.
func _island_homes(islands: Array) -> Array:
	var half := maxi(1, islands.size() / 2)
	var homes := [islands.slice(0, half), islands.slice(islands.size() - half)]
	return homes.map(func(h): return _island_spots(h))


func _island_spots(islands: Array) -> Array:
	var spots := []
	for attempt in 160:
		var island: Dictionary = islands[rng.randi() % islands.size()]
		var x := rng.randf_range(lerpf(island.x0, island.x1, 0.08), lerpf(island.x0, island.x1, 0.92))
		var pos := Vector2(x, island.base - 80.0)  # island tops never rise above base - 70
		while pos.y < abyss_y and not terrain.is_solid(pos + Vector2.DOWN):
			pos.y += 1.0
		if pos.y < abyss_y:
			spots.append(pos)
	return spots


## Picks every unit's start. Each team takes UNITS_PER_TEAM spots from its own list. Random sets of all
## six are tried until every unit is at least MIN_SPAWN_GAP from every other (else the most spread set).
func _choose_spawns(team_spots: Array) -> Array:
	for team in 2:
		if team_spots[team].is_empty():
			team_spots[team] = [Vector2(world_size.x * (0.25 + 0.5 * team), 100)]
	# Start from a random set, then keep moving one unit of the closest pair to another of its
	# team's spots whenever that does not shrink the smallest gap.
	var best := []
	for team in 2:
		for i in UNITS_PER_TEAM:
			best.append(team_spots[team][rng.randi() % team_spots[team].size()])
	var best_gap := _min_pair_gap(best)
	for attempt in 3000:
		if best_gap >= spawn_gap:
			break
		var k := _closest_unit_index(best)
		var trial := best.duplicate()
		var team := k / UNITS_PER_TEAM
		trial[k] = team_spots[team][rng.randi() % team_spots[team].size()]
		var gap := _min_pair_gap(trial)
		if gap >= best_gap:
			best = trial
			best_gap = gap
	return best


func _create_units(spawns: Array) -> void:
	var id := 0
	for team in 2:
		for i in UNITS_PER_TEAM:
			var unit := Unit.new()
			unit.position = spawns[id]
			unit.fell.connect(_on_unit_fell)
			add_child(unit)
			unit.setup(id, team, UNIT_NAMES[team][i], TEAM_COLORS[team], physics, terrain)
			unit.grounded = true
			units.append(unit)
			id += 1


func _min_pair_gap(points: Array) -> float:
	var gap := INF
	for i in points.size():
		for j in range(i + 1, points.size()):
			gap = minf(gap, points[i].distance_to(points[j]))
	return gap


## One of the two points in the closest pair, picked at random.
func _closest_unit_index(points: Array) -> int:
	var pair := [0, 1]
	var gap := INF
	for i in points.size():
		for j in range(i + 1, points.size()):
			var d: float = points[i].distance_to(points[j])
			if d < gap:
				gap = d
				pair = [i, j]
	return pair[rng.randi() % 2]


func _planet_spots(planets: Array) -> Array:
	var spots := []
	for attempt in 150:
		var planet: Dictionary = planets[rng.randi() % planets.size()]
		var center: Vector2 = planet.center
		var radius: float = planet.radius
		# Prefer the upper half of the planet, it reads better on screen.
		var angle := rng.randf_range(-PI * 0.9, -PI * 0.1) if attempt < 60 else rng.randf() * TAU
		if planets.size() == 1 and planet_count == 1:
			angle = rng.randf_range(-PI, 0.0)  # giant planet: top half only, so nobody starts under the HUD
		var dir := Vector2.from_angle(angle)
		var pos := center + dir * radius * 1.4
		while not terrain.is_solid(pos - dir) and pos.distance_to(center) > 1.0:
			pos -= dir
		if not Rect2(Vector2(10, 10), world_size - Vector2(20, 20)).has_point(pos):
			continue
		if physics.up_at(pos).dot(dir) < 0.9:
			continue  # another planet pulls harder here
		spots.append(pos)
	return spots


# --- Commands -------------------------------------------------------------

## Single entry point for controllers (local player, bot, and later network peers).
## Command shapes:
##   {"type": "walk", "team": t, "dir": -1|1}
##   {"type": "aim", "team": t, "angle": float}
##   {"type": "charge", "team": t, "value": 0..1}      (cosmetic)
##   {"type": "weapon", "team": t, "index": int}
##   {"type": "fire", "team": t, "angle": float, "power": 0..1}
##   {"type": "skip", "team": t}                       (end the turn without firing)
func submit_command(cmd: Dictionary) -> void:
	command_queue.append(cmd)


func is_turn_of(team: int) -> bool:
	return phase == Phase.AIMING and current_team == team and active_unit != null


func current_weapon_id(team: int = -1) -> String:
	if team < 0:
		team = current_team
	return Weapons.LIST[team_weapon[team]]


## Uses left for a team, or -1 when unlimited.
func ammo_left(team: int, weapon_id: String) -> int:
	return team_ammo[team].get(weapon_id, -1)


## Whether `team` may fire this weapon now (ammo, and HP condition for the active unit).
func weapon_available(team: int, weapon_id: String) -> bool:
	if ammo_left(team, weapon_id) == 0:
		return false
	var w := Weapons.get_def(weapon_id)
	if round_number < w.get("min_round", 0) and not (GameSettings.debug and team == 0):
		return false  # e.g. Void Driller: no knocking someone off the map with the very first shot
	if w.has("hp_ratio_max") and not (GameSettings.debug and team == 0):
		if active_unit == null or active_unit.team != team:
			return false
		return float(active_unit.hp) / active_unit.MAX_HP <= w.hp_ratio_max
	return true


func is_over() -> bool:
	return phase == Phase.GAME_OVER


func go_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _apply_command(cmd: Dictionary) -> void:
	if not is_turn_of(cmd.get("team", -1)):
		return
	match cmd.get("type", ""):
		"walk":
			_face(int(cmd.dir))
			active_unit.walk(int(cmd.dir), 1.0 / 60.0)
		"face":
			_face(int(cmd.dir))
		"aim":
			if active_unit.rooted_turns == 0:  # Stasis Net also locks the barrel
				active_unit.aim_angle = clamp_aim(cmd.angle, aim_side(active_unit))
		"charge":
			active_unit.charge = clampf(cmd.value, 0.0, 1.0)
		"weapon":
			var index := posmod(int(cmd.index), Weapons.LIST.size())
			if weapon_available(current_team, Weapons.LIST[index]):
				team_weapon[current_team] = index
		"skip":
			# Ends the turn now. Less time used = an earlier turn next round.
			controllers[current_team].end_turn()
			aim_guide.clear()
			_begin_settling()
		"fire":
			var angle: float = active_unit.aim_angle if active_unit.rooted_turns > 0 else cmd.angle
			_fire(angle, clampf(cmd.power, 0.05, 1.0))


func _fire(angle: float, power: float) -> void:
	var weapon := current_weapon_id()
	if not weapon_available(current_team, weapon):
		weapon = Weapons.LIST[0]
		team_weapon[current_team] = 0
	if team_ammo[current_team].has(weapon):
		team_ammo[current_team][weapon] -= 1
	var w := Weapons.get_def(weapon)
	angle = clamp_aim(angle, aim_side(active_unit), weapon)
	active_unit.aim_angle = angle
	active_unit.charge = 0.0
	last_power[active_unit.unit_id] = power
	last_shot = {"angle": angle, "power": power, "weapon": weapon}
	shots_left = int(w.get("shots", 1)) - 1
	shot_dmg_mult = 1.0 + _event_value("dmg") / 100.0
	if team_boost[current_team] > 0.0 and not w.has("boost"):
		shot_dmg_mult *= 1.0 + team_boost[current_team]
		team_boost[current_team] = 0.0
	shot_radius_mult = 1.0 + _event_value("blast") / 100.0
	_launch(last_shot)
	# Special weapons are one-off picks: the next turn starts back on weapon 1.
	team_weapon[current_team] = 0
	phase = Phase.FLYING
	aim_guide.clear()
	controllers[current_team].end_turn()


func _launch(shot: Dictionary) -> void:
	var w := Weapons.get_def(shot.weapon)
	var count := int(w.get("spread", 1))
	var step := deg_to_rad(w.get("spread_deg", 0.0))
	for k in count:
		active_unit.aim_angle = shot.angle + (k - (count - 1) / 2.0) * step
		var vel: Vector2 = active_unit.aim_dir() * shot.power * SpacePhysics.MAX_SPEED
		_spawn_projectile(active_unit.muzzle(), vel, shot.weapon)
	active_unit.aim_angle = shot.angle


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
	_tick_crates(delta)
	if phase == Phase.AIMING and active_unit and active_unit.alive:
		# Weapon switches can change the allowed range; the barrel snaps into it.
		if active_unit.grounded:
			active_unit.tilt = active_unit.ground_tilt()
		active_unit.aim_range = level_range(aim_side(active_unit))
		if active_unit.rooted_turns == 0:
			active_unit.aim_angle = clamp_aim(active_unit.aim_angle, aim_side(active_unit))
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
			_tick_strikes(delta)
			if projectiles.is_empty() and pending_strikes.is_empty():
				if shots_left > 0 and active_unit.alive:
					refire_timer += delta
					if refire_timer >= REFIRE_DELAY:
						refire_timer = 0.0
						shots_left -= 1
						_launch(last_shot)
				else:
					_begin_settling()
		Phase.SETTLING:
			settle_time -= delta
			if (settle_time <= 0.0 and _all_grounded()) or settle_time < -4.0:
				_end_turn()


func _process(_delta: float) -> void:
	if phase == Phase.FLYING and not projectiles.is_empty():
		camera.follow(projectiles[0].position)
	elif phase == Phase.FLYING and not pending_strikes.is_empty():
		camera.follow(pending_strikes[0].pos)
	elif active_unit:
		camera.follow(active_unit.position)
	_update_aim_guide()


func _update_aim_guide() -> void:
	var guide_time: float = GameSettings.GUIDE_OPTIONS[GameSettings.guide][1]
	if guide_time <= 0.0 or autoplay or not is_turn_of(0):
		aim_guide.clear()
		return
	var power: float = active_unit.charge if active_unit.charge > 0.0 else last_power.get(active_unit.unit_id, 0.6)
	var vel: Vector2 = active_unit.aim_dir() * power * SpacePhysics.MAX_SPEED
	var color: Color = Weapons.get_def(current_weapon_id()).color
	aim_guide.show_path(physics.simulate_path(active_unit.muzzle(), vel, terrain, guide_time), color)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_R and (phase == Phase.GAME_OVER or event.ctrl_pressed):
		get_tree().reload_current_scene()
	elif event.physical_keycode == KEY_ESCAPE:
		go_to_menu()


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


func nearest_enemy(pos: Vector2, team: int):
	var best = null
	var best_d := INF
	for u in units:
		if u.alive and u.team != team:
			var d: float = u.body_center().distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = u
	return best


func unit_hit_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for u in units:
		if u.alive:
			pts.append(u.body_center())
	return pts


func on_detonation(pos: Vector2, weapon_id: String, vel: Vector2, direct := false) -> void:
	var w := Weapons.get_def(weapon_id)
	if w.has("strike_width"):
		_call_sky_strike(pos, weapon_id)
		return
	var radius: float = w.radius * shot_radius_mult
	var shooter_team: int = current_team
	if radius > 0.0:
		var crater: float = w.get("carve", w.radius)
		if not direct and w.has("miss_carve"):
			crater = w.miss_carve
		terrain.carve(pos, crater * shot_radius_mult * carve_mult)
	if w.has("boost"):
		team_boost[shooter_team] = w.boost
		_float_text(pos + Vector2(0, -60), L.t("นัดถัดไปแรงขึ้น %d%%") % int(w.boost * 100), Color(0.5, 1.0, 0.6))
	var reach: float = maxf(radius * 1.5, w.get("heal_radius", 0.0))
	for u in units:
		if not u.alive:
			continue
		var c: Vector2 = u.body_center()
		var d := c.distance_to(pos)
		if w.has("root_radius") and u.team != shooter_team and d < w.root_radius:
			u.rooted_turns = 1
			_float_text(c + Vector2(0, -46), L.t("ติดตาข่าย!"), Color(0.6, 0.85, 1.0))
		if d >= reach:
			continue
		if w.has("heal") and u.team == shooter_team:
			var healed: int = u.heal(int(w.heal))
			if healed > 0:
				_float_text(c + Vector2(0, -30), "+%d" % healed, Color(0.5, 1.0, 0.55))
			continue
		var f := 1.0 - d / reach
		var dmg := int(round(w.damage * f * shot_dmg_mult))
		if dmg <= 0:
			continue
		u.take_damage(dmg)
		_float_text(c + Vector2(0, -30), "-%d" % dmg, Color(1, 0.85, 0.4))
	if w.has("bomblets"):
		var back: Vector2 = -vel.normalized() if vel.length_squared() > 1.0 else physics.up_at(pos)
		var count: int = int(w.get("direct_bomblets", w.bomblets)) if direct else int(w.bomblets)
		for i in count:
			var dir := back.rotated(rng.randf_range(-1.1, 1.1))
			_spawn_projectile(pos + dir * 6.0, dir * rng.randf_range(180.0, 300.0), "bomblet", 0.05)
	var fx := Explosion.new()
	fx.setup(pos, maxf(radius, w.get("root_radius", w.get("heal_radius", 0.0)) * 0.7), w.color)
	add_child(fx)
	camera.shake = maxf(camera.shake, radius * 0.3)


func _call_sky_strike(pos: Vector2, weapon_id: String) -> void:
	var w := Weapons.get_def(weapon_id)
	var axis := physics.up_at(pos)
	pending_strikes.append({"pos": pos, "axis": axis, "weapon": weapon_id, "time": float(w.strike_delay)})
	var beam := SkyBeam.new()
	beam.setup(pos, axis, w.strike_width, w.strike_delay, w.color)
	add_child(beam)


func _tick_strikes(delta: float) -> void:
	for s in pending_strikes.duplicate():
		s.time -= delta
		if s.time <= 0.0:
			pending_strikes.erase(s)
			_sky_strike(s.pos, s.axis, Weapons.get_def(s.weapon))


## The beam hits a strip `strike_width` wide on each side, along the local "up" axis.
func _sky_strike(pos: Vector2, axis: Vector2, w: Dictionary) -> void:
	var width: float = w.strike_width * shot_radius_mult
	var perp := Vector2(-axis.y, axis.x)
	for k in range(-2, 3):
		terrain.carve(pos + perp * (k * width * 0.4) - axis * 10.0, w.strike_carve * shot_radius_mult * carve_mult)
	for u in units:
		if not u.alive:
			continue
		var rel: Vector2 = u.body_center() - pos
		var across := absf(rel.dot(perp))
		if across >= width or rel.dot(axis) < -90.0:
			continue
		var dmg := int(round(w.damage * (1.0 - 0.6 * across / width) * shot_dmg_mult))
		u.take_damage(dmg)
		_float_text(u.body_center() + Vector2(0, -30), "-%d" % dmg, Color(1, 0.9, 0.5))
	camera.shake = maxf(camera.shake, 22.0)


# --- Supply crates --------------------------------------------------------

func _drop_crate() -> void:
	crates = crates.filter(func(c): return not c.gone)
	if crates.size() >= MAX_CRATES:
		return
	var kind := "ammo"
	var pos: Vector2
	if physics.planets.is_empty():
		pos = Vector2(rng.randf_range(80.0, world_size.x - 80.0), -60.0)
	else:
		var p: Dictionary = physics.planets[rng.randi() % physics.planets.size()]
		pos = p.center + Vector2.from_angle(rng.randf() * TAU) * (p.radius + 260.0)
	var crate := Crate.new()
	crate.setup(pos, kind, physics, terrain)
	add_child(crate)
	crates.append(crate)
	_float_text(pos.clamp(Vector2(60, 60), world_size - Vector2(60, 60)), L.t("กล่องเสบียงกำลังตก!"), Color(1, 0.85, 0.5))


func _tick_crates(delta: float) -> void:
	for crate in crates.duplicate():
		crate.tick(delta)
		if crate.gone:
			crates.erase(crate)
			crate.queue_free()
			continue
		for u in units:
			if u.alive and u.body_center().distance_to(crate.position + Vector2(0, -10)) < Crate.PICKUP_RADIUS + 10.0:
				_collect(crate, u)
				break


func _collect(crate, unit) -> void:
	var id: String = AMMO_LOOT[rng.randi() % AMMO_LOOT.size()]
	if team_ammo[unit.team].has(id):  # unlimited (debug) stays unlimited
		team_ammo[unit.team][id] += 1
	var text := L.t("+1 นัด เบอร์ %d %s") % [(Weapons.LIST.find(id) + 1) % 10, Weapons.get_def(id).name]
	_float_text(unit.body_center() + Vector2(0, -50), text, Color(0.6, 1.0, 0.6))
	crates.erase(crate)
	crate.queue_free()


func _on_unit_fell(unit) -> void:
	var pos: Vector2 = unit.position.clamp(Vector2(40, 40), Vector2(world_size.x - 40, minf(abyss_y, world_size.y) - 30))
	var msg := L.t("%s ตกลงไปในแกนดาว!") if unit.fell_into_core else L.t("%s หายไปในอวกาศ!")
	_float_text(pos, msg % unit.unit_name, Color(1, 0.5, 0.5))


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
		active_unit.rooted_turns = maxi(0, active_unit.rooted_turns - 1)
		time_used[active_unit.unit_id] = turn_start_time - maxf(turn_time_left, 0.0)
	var a := alive_count(0)
	var b := alive_count(1)
	if a == 0 or b == 0:
		phase = Phase.GAME_OVER
		winner = -1 if a == b else (0 if a > 0 else 1)
		active_unit = null
		if autoplay:
			print("game over after %d turns (%d rounds), winner: %d" % [turn_number, round_number, winner])
		game_over.emit(winner)
		return
	_start_turn()


func _start_round() -> void:
	round_number += 1
	var coin_toss := round_number == 1
	var queues := [[], []]
	for u in units:
		if u.alive:
			queues[u.team].append(u)
	var first_team: int
	if coin_toss:
		first_team = rng.randi() % 2
	else:
		# Fastest unit of last round first; inside a team, faster units play earlier.
		for team in 2:
			queues[team].sort_custom(func(x, y): return _used(x) < _used(y) or (_used(x) == _used(y) and x.unit_id < y.unit_id))
		var t0: float = _used(queues[0][0])
		var t1: float = _used(queues[1][0])
		first_team = 0 if t0 < t1 else (1 if t1 < t0 else rng.randi() % 2)
	round_queue.clear()
	var team := first_team
	while not queues[0].is_empty() or not queues[1].is_empty():
		if not queues[team].is_empty():
			round_queue.append(queues[team].pop_front())
		team = 1 - team
	last_round_time = time_used.duplicate()
	time_used.clear()
	if round_number > 1:
		_drop_crate()  # a supply crate after every finished round
	round_event = {}
	if rng.randf() < EVENT_CHANCE:
		var kind: String = EVENT_KINDS[rng.randi() % EVENT_KINDS.size()]
		var value := 0
		while value == 0:
			value = rng.randi_range(-10, 10) if kind == "time" else rng.randi_range(-4, 4) * 5
		round_event = {"kind": kind, "value": value}
	if autoplay:
		print("round %d first team %d order %s event %s" % [round_number, first_team, round_queue.map(func(u): return u.unit_name), round_event])
	round_started.emit(round_number, first_team, coin_toss)


func _used(u) -> float:
	return time_used.get(u.unit_id, TURN_TIME)


func _event_value(kind: String) -> int:
	return int(round_event.value) if not round_event.is_empty() and round_event.kind == kind else 0


func _start_turn() -> void:
	turn_number += 1
	active_unit = null
	while active_unit == null:
		while round_queue.is_empty():
			_start_round()
		var u = round_queue.pop_front()
		if u.alive:
			active_unit = u
	current_team = active_unit.team
	physics.wind = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, MAX_WIND)
	active_unit.is_active = true
	active_unit.tilt = active_unit.ground_tilt()
	if active_unit.rooted_turns == 0:
		active_unit.aim_angle = clamp_aim(active_unit.aim_angle, aim_side(active_unit))
	if not weapon_available(current_team, current_weapon_id()):
		team_weapon[current_team] = 0
	shots_left = 0
	refire_timer = 0.0
	camera.follow(active_unit.position, true)
	turn_start_time = TURN_TIME + _event_value("time")
	turn_time_left = turn_start_time
	command_queue.clear()
	phase = Phase.AIMING
	controllers[current_team].begin_turn(active_unit)
	if autoplay:
		print("turn %d team %d %s hp=%d/%d" % [turn_number, current_team, active_unit.unit_name, alive_count(0), alive_count(1)])
	turn_started.emit(current_team, active_unit)


## Units still to play this round, after the active one.
func upcoming_units() -> Array:
	return round_queue.filter(func(u): return u.alive)


## Which way the barrel points: 1 = to the unit's right, -1 = to its left.
func aim_side(unit) -> int:
	if absf(unit.aim_angle) > 0.001:
		return 1 if unit.aim_angle > 0.0 else -1
	return 1 if unit.team == 0 else -1


## Elevation range of a weapon in degrees above the ground it stands on, see Weapons "elev".
func aim_range(weapon_id := "") -> Vector2:
	if weapon_id == "":
		weapon_id = current_weapon_id()
	return Weapons.get_def(weapon_id).get("elev", Vector2(-70, 90))


## The weapon's range measured from the ground the active unit stands on, turned into degrees
## above level for the side it faces: on a slope rising 20 degrees ahead, 0-45 becomes 20-65.
func level_range(side: int, weapon_id := "") -> Vector2:
	var r := aim_range(weapon_id)
	var t: float = active_unit.tilt * side if active_unit else 0.0
	return Vector2(maxf(r.x + t, -70.0), minf(r.y + t, 90.0))


## Keeps an aim angle (radians from local up) inside the weapon's range on `side`.
func clamp_aim(angle: float, side: int, weapon_id := "") -> float:
	var r := level_range(side, weapon_id)
	var from_up := clampf(rad_to_deg(absf(angle)), 90.0 - r.y, 90.0 - r.x)
	if (angle > 0.0) != (side > 0) and absf(angle) > 0.001:
		from_up = 90.0 - r.y  # crossed over the top: stay at the steepest allowed angle on this side
	return side * deg_to_rad(minf(from_up, rad_to_deg(Unit.AIM_LIMIT)))


## Walking (or the bot's "face" command) turns the barrel to that side, mirrored.
func _face(dir: int) -> void:
	if dir == 0 or active_unit.rooted_turns > 0:
		return
	if dir != aim_side(active_unit):
		active_unit.aim_angle = clamp_aim(-active_unit.aim_angle if absf(active_unit.aim_angle) > 0.001 else dir * 0.6, dir)


func team_name(team: int) -> String:
	return L.t(TEAM_NAMES[team])


func event_text() -> String:
	var v := absi(_event_value(round_event.get("kind", "")))
	match round_event.get("kind", ""):
		"dmg":
			return L.t("รอบนี้อาวุธแรงขึ้น %d%%" if round_event.value > 0 else "รอบนี้อาวุธเบาลง %d%%") % v
		"time":
			return L.t("รอบนี้เวลาต่อตาเพิ่มขึ้น %d วินาที" if round_event.value > 0 else "รอบนี้เวลาต่อตาลดลง %d วินาที") % v
		"blast":
			return L.t("รอบนี้วงระเบิดกว้างขึ้น %d%%" if round_event.value > 0 else "รอบนี้วงระเบิดแคบลง %d%%") % v
	return ""
