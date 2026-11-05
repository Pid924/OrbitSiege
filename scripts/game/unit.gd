extends Node2D
## An astronaut gunner. `position` is the feet; "up" always points away from the planet it stands on.

signal fell(unit)

const MAX_HP := 100
const WALK_SPEED := 45.0
const CLIMB := 6
const SAFE_DROP := 28  # walking never steps off a ledge deeper than this
const AIM_LIMIT := 2.8

var unit_id := 0
var team := 0
var unit_name := ""
var color := Color.WHITE
var hp := MAX_HP
var alive := true
var aim_angle := 0.6  # radians, relative to local up; positive turns clockwise
var charge := 0.0  # 0..1, only for drawing the power gauge
var velocity := Vector2.ZERO
var grounded := false
var up := Vector2.UP
var is_active := false
var rooted_turns := 0  # own turns left during which this unit cannot walk
var fell_into_core := false
var aim_range := Vector2(-70, 90)  # allowed elevation above level (weapon range + ground tilt), for drawing
var tilt := 0.0  # degrees the ground rises toward the unit's local right, see ground_tilt()

var physics
var terrain
var _bob := 0.0


func setup(id: int, team_id: int, display_name: String, team_color: Color, physics_ref, terrain_ref) -> void:
	unit_id = id
	team = team_id
	unit_name = display_name
	color = team_color
	physics = physics_ref
	terrain = terrain_ref
	up = physics.up_at(position)
	aim_angle = 0.6 if team == 0 else -0.6


func body_center() -> Vector2:
	return position + up * 9.0


func muzzle() -> Vector2:
	return position + up * 10.0 + aim_dir() * 14.0


func aim_dir() -> Vector2:
	return up.rotated(aim_angle)


## Physics step, driven by the match so all simulation happens in one ordered place.
func tick(dt: float) -> void:
	if not alive:
		return
	up = physics.up_at(position)
	if grounded and not terrain.is_solid(position - up * 2.0):
		grounded = false
	if grounded:
		return
	velocity += physics.gravity_at(position) * dt
	var n := maxi(1, int(ceil(velocity.length() * dt / 3.0)))
	var step := velocity * dt / n
	for i in n:
		var next := position + step
		if terrain.is_solid(next):
			_land()
			break
		position = next
	if not physics.bounds.has_point(position):
		fell.emit(self)
		die()
		return
	# Falling through a hole all the way to a planet's core: nothing left to stand on, so it is out
	# (otherwise point gravity would keep it bobbing around the center forever).
	for p in physics.planets:
		if position.distance_to(p.center) < maxf(16.0, p.radius * 0.2):
			fell_into_core = true
			fell.emit(self)
			die()
			return


func _land() -> void:
	grounded = true
	velocity = Vector2.ZERO
	up = physics.up_at(position)
	for i in 12:
		if not terrain.is_solid(position):
			break
		position += up


func walk(dir: int, dt: float) -> void:
	if not grounded or not alive or dir == 0 or rooted_turns > 0:
		return
	var start := position
	var tangent := Vector2(-up.y, up.x)
	var next := position + tangent * dir * WALK_SPEED * dt
	var climbed := 0
	while terrain.is_solid(next) and climbed < CLIMB:
		next += up
		climbed += 1
	if terrain.is_solid(next):
		return  # wall too steep
	position = next
	for i in SAFE_DROP:
		if terrain.is_solid(position - up):
			return
		position -= up
	# No ground within a safe drop: stop at the edge instead of walking off.
	position = start


## Slope of the ground under the feet in degrees, relative to local level (perpendicular to "up").
## Positive when the ground rises toward the unit's right.
func ground_tilt() -> float:
	if not grounded:
		return 0.0
	var tangent := Vector2(-up.y, up.x)
	var reach := 16.0
	var heights := []
	for d in [-reach, reach]:
		var h := 0.0
		var found := false
		for k in range(24, -25, -1):  # scan down from above the feet
			if terrain.is_solid(position + tangent * d + up * (k - 1)):
				h = k
				found = true
				break
		heights.append(h if found else -24.0)
	return clampf(rad_to_deg(atan2(heights[1] - heights[0], reach * 2.0) ), -35.0, 35.0)


func heal(amount: int) -> int:
	if not alive:
		return 0
	var before := hp
	hp = mini(MAX_HP, hp + amount)
	return hp - before


func take_damage(amount: int) -> void:
	if not alive or amount <= 0:
		return
	hp = maxi(0, hp - amount)
	if hp == 0:
		die()


func die() -> void:
	if not alive:
		return
	alive = false
	hp = 0
	is_active = false
	queue_redraw()


func _process(delta: float) -> void:
	_bob += delta
	queue_redraw()


func _draw() -> void:
	var rot := up.angle() + PI / 2.0
	if not alive:
		draw_set_transform(Vector2.ZERO, rot)
		draw_rect(Rect2(-4, -14, 8, 14), Color(0.45, 0.45, 0.5))
		draw_rect(Rect2(-7, -11, 14, 3), Color(0.45, 0.45, 0.5))
		return
	draw_set_transform(Vector2.ZERO, rot)
	var local_aim := Vector2.UP.rotated(aim_angle)
	if is_active:
		# Aim guide grows with the charge so the player can read the power.
		# Faint fan showing the angles this weapon allows on the side the barrel faces.
		var side := 1.0 if aim_angle >= 0.0 else -1.0
		var a0 := deg_to_rad(90.0 - aim_range.y) * side
		var a1 := deg_to_rad(90.0 - aim_range.x) * side
		for a in [a0, a1]:
			draw_line(Vector2(0, -10), Vector2(0, -10) + Vector2.UP.rotated(a) * 30.0, Color(1, 1, 1, 0.3), 1.0)
		draw_arc(Vector2(0, -10), 26.0, minf(a0, a1) - PI / 2.0, maxf(a0, a1) - PI / 2.0, 16, Color(1, 1, 1, 0.22), 1.5)
		var guide_len := 30.0 + charge * 70.0
		for k in 6:
			var a := Vector2(0, -10) + local_aim * (16.0 + guide_len * k / 6.0)
			draw_circle(a, 2.0, Color(1, 1, 1, 0.8 - k * 0.1))
	# legs
	draw_rect(Rect2(-6, -5, 4, 5), color.darkened(0.4))
	draw_rect(Rect2(2, -5, 4, 5), color.darkened(0.4))
	# barrel
	draw_line(Vector2(0, -10), Vector2(0, -10) + local_aim * 16.0, Color(0.85, 0.85, 0.9), 4.0)
	# suit + helmet
	draw_circle(Vector2(0, -10), 8.0, color)
	draw_circle(Vector2(0, -11), 5.0, Color(0.1, 0.15, 0.25))
	draw_circle(Vector2(1.5, -12.5), 1.6, Color(0.7, 0.95, 1.0))
	draw_line(Vector2(0, -18), Vector2(0, -23), color.lightened(0.3), 1.5)
	draw_circle(Vector2(0, -24), 1.8, color.lightened(0.5))
	draw_set_transform(Vector2.ZERO, 0.0)
	if rooted_turns > 0:
		var c := up * 9.0
		draw_arc(c, 15.0, 0, TAU, 24, Color(0.5, 0.8, 1.0, 0.9), 2.0)
		for k in 6:
			var a := float(k) / 6.0 * TAU + _bob
			draw_line(c + Vector2.from_angle(a) * 11.0, c + Vector2.from_angle(a) * 19.0, Color(0.6, 0.9, 1.0, 0.8), 1.5)
	# Screen-aligned label and HP bar above the head.
	var font := ThemeDB.fallback_font
	var head := up * 36.0
	var bar := Rect2(head + Vector2(-20, 0), Vector2(40, 6))
	var fill := float(hp) / MAX_HP
	var bar_color := color if fill > 0.4 else color.lerp(Color(1.0, 0.85, 0.3), 0.5)
	draw_rect(bar, Color(0, 0, 0, 0.65))
	draw_rect(Rect2(bar.position, Vector2(40.0 * fill, 6)), bar_color)
	draw_rect(bar, Color(1, 1, 1, 0.4), false, 1.0)
	draw_string(font, head + Vector2(-30, -4), unit_name, HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color(1, 1, 1, 0.9))
	if is_active:
		var y := -14.0 + sin(_bob * 5.0) * 3.0
		var tip := head + Vector2(0, y)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-6, -9), tip + Vector2(6, -9)]), Color(1, 1, 0.4))
