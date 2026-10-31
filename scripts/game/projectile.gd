extends Node2D
## A shell in flight. Integration mirrors SpacePhysics.simulate_shot so the bot's predictions hold.

const SpacePhysics := preload("res://scripts/sim/space_physics.gd")
const Weapons := preload("res://scripts/sim/weapons.gd")

var game
var weapon_id := "plasma"
var vel := Vector2.ZERO
var age := 0.0
var done := false
var unit_ignore_time := 0.15
var drill_left := -1.0
var trail: Array = []


func setup(game_ref, start: Vector2, start_vel: Vector2, weapon: String, ignore_time := 0.15) -> void:
	game = game_ref
	position = start
	vel = start_vel
	weapon_id = weapon
	unit_ignore_time = ignore_time


func tick(dt: float) -> void:
	var w := Weapons.get_def(weapon_id)
	var h := dt / SpacePhysics.SUBSTEPS
	for i in SpacePhysics.SUBSTEPS:
		if done:
			break
		age += h
		if drill_left >= 0.0:
			drill_left -= h
			position += vel * h
			game.terrain.carve(position, 9.0)
			if drill_left <= 0.0 or game.unit_at(position) != null or not game.physics.bounds.has_point(position):
				_detonate()
			continue
		vel += (game.physics.gravity_at(position) + game.physics.wind) * h
		position += vel * h
		if not game.physics.bounds.has_point(position):
			done = true  # lost in space
		elif age > SpacePhysics.MAX_FLIGHT_TIME:
			_detonate()
		elif game.terrain.is_solid(position):
			if w.has("drill_time"):
				drill_left = w.drill_time
				vel = vel.normalized() * 170.0
			else:
				_detonate()
		elif age > unit_ignore_time and game.unit_at(position) != null:
			_detonate()
	trail.append(position)
	if trail.size() > 40:
		trail.pop_front()
	queue_redraw()


func _detonate() -> void:
	done = true
	game.on_detonation(position, weapon_id, vel)


func _draw() -> void:
	var w := Weapons.get_def(weapon_id)
	var c: Color = w.color
	for i in range(1, trail.size()):
		var a := float(i) / trail.size()
		draw_line(to_local(trail[i - 1]), to_local(trail[i]), Color(c, a * 0.7), 1.0 + a * 2.0)
	draw_circle(Vector2.ZERO, 6.0, Color(c, 0.3))
	draw_circle(Vector2.ZERO, 3.5, c.lightened(0.4))
