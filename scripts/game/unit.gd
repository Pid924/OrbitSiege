extends Node2D
## An astronaut gunner. `position` is the feet; "up" always points away from the planet it stands on.

signal fell(unit)

const Weapons := preload("res://scripts/sim/weapons.gd")

const MAX_HP := 100
const WALK_SPEED := 45.0
const CLIMB := 12  # steepest step (px) a unit walks up
const SAFE_DROP := 28  # deeper than this, walking steps off the ledge and falls (unless safe)
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
var poison_turns := 0  # own turns left that start with poison damage
## Crate buffs for this unit's next shot: "dmg" (extra fraction), "double", "teleport", "poison".
var buffs := {}
var buff_keep := false  # picked up after firing this turn: keep through this turn's end
var barrier := false  # crate barrier: blocks the next shell damage, until this unit's next turn
var rooted_turns := 0  # own turns left during which this unit cannot walk
var skip_next := false  # netted again while netted: its next turn is skipped
var element := ""  # fire / water / wood: suit color, slot-1 shell, slot-0 power, walk speed
var suit := Color.WHITE
var walk_mult := 1.0
var special_used := false  # element power (slot 0) is once per unit per match
var power_bonus := 0.0  # damage change from element powers right now (drawn as an arrow)
var bloom_next := false  # Verdant Bloom heals this unit again when the next round starts
var order_num := 0  # place in this round's turn order (0 = none)
var order_done := false  # already had its turn this round
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


func set_element(e: String) -> void:
	element = e
	suit = Weapons.ELEMENT_INFO[e].color
	walk_mult = Weapons.ELEMENT_INFO[e].walk


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


## `safe` stops at a ledge instead of walking off it (bots, and the reachability scan).
func walk(dir: int, dt: float, safe := false) -> void:
	if not grounded or not alive or dir == 0 or rooted_turns > 0:
		return
	var start := position
	var tangent := Vector2(-up.y, up.x)
	var next := position + tangent * dir * WALK_SPEED * walk_mult * dt
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
	if safe:
		position = start  # no ground within a safe drop: stop at the edge
		return
	# Stepped off the ledge: fall from the edge (tick() takes over).
	position = next
	grounded = false
	velocity = Vector2.ZERO


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


## Team 0: the round-helmet astronaut. Suit and outline in the element color.
func _draw_astronaut(local_aim: Vector2) -> void:
	var edge := suit.lightened(0.35)
	draw_rect(Rect2(-6, -5, 4, 5), suit.darkened(0.45))
	draw_rect(Rect2(2, -5, 4, 5), suit.darkened(0.45))
	draw_line(Vector2(0, -10), Vector2(0, -10) + local_aim * 16.0, Color(0.85, 0.85, 0.9), 4.0)
	draw_circle(Vector2(0, -10), 8.0, suit)
	draw_arc(Vector2(0, -10), 8.5, 0, TAU, 24, edge, 2.0)
	draw_circle(Vector2(0, -11), 5.0, Color(0.1, 0.15, 0.25))
	draw_circle(Vector2(1.5, -12.5), 1.6, Color(0.7, 0.95, 1.0))
	draw_line(Vector2(0, -18), Vector2(0, -23), edge, 1.5)
	draw_circle(Vector2(0, -24), 1.8, edge.lightened(0.3))


## Team 1: a boxy tracked robot with a glowing visor. Dark metal body, outline and visor in the element color.
func _draw_robot(local_aim: Vector2) -> void:
	var metal := Color(0.2, 0.22, 0.28)
	var edge := suit.lightened(0.2)
	# tracks
	draw_rect(Rect2(-9, -5, 18, 5), Color(0.12, 0.12, 0.15))
	for x in [-6.0, 0.0, 6.0]:
		draw_circle(Vector2(x, -2.5), 2.0, Color(0.45, 0.45, 0.5))
	draw_line(Vector2(0, -11), Vector2(0, -11) + local_aim * 16.0, Color(0.7, 0.72, 0.78), 4.0)
	# body
	var body := Rect2(-8, -19, 16, 14)
	draw_rect(body, metal)
	draw_rect(body, edge, false, 2.0)
	# visor band and eye
	draw_rect(Rect2(-6, -16, 12, 4), suit)
	var blink := 1.0 if fmod(_bob, 3.0) > 0.12 else 0.2
	draw_circle(Vector2(2, -14), 1.5, Color(1, 1, 1, blink))
	# twin antennae
	draw_line(Vector2(-5, -19), Vector2(-6, -24), edge, 1.5)
	draw_line(Vector2(5, -19), Vector2(6, -24), edge, 1.5)
	draw_rect(Rect2(-7.5, -25.5, 3, 3), suit)
	draw_rect(Rect2(4.5, -25.5, 3, 3), suit)


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
	if team == 0:
		_draw_astronaut(local_aim)
	else:
		_draw_robot(local_aim)
	draw_set_transform(Vector2.ZERO, 0.0)
	if rooted_turns > 0:
		var c := up * 9.0
		draw_arc(c, 15.0, 0, TAU, 24, Color(0.5, 0.8, 1.0, 0.9), 2.0)
		if skip_next:
			draw_arc(c, 21.0, 0, TAU, 24, Color(0.5, 0.8, 1.0, 0.9), 2.0)  # double ring: turn will be skipped
		for k in 6:
			var a := float(k) / 6.0 * TAU + _bob
			draw_line(c + Vector2.from_angle(a) * 11.0, c + Vector2.from_angle(a) * 19.0, Color(0.6, 0.9, 1.0, 0.8), 1.5)
	# Screen-aligned label and HP bar above the head.
	var font := ThemeDB.fallback_font
	var head := up * 36.0
	var bar := Rect2(head + Vector2(-20, 0), Vector2(40, 6))
	var fill := float(hp) / MAX_HP
	var bar_color := suit  # HP bar in the element color
	draw_rect(bar, Color(0, 0, 0, 0.65))
	draw_rect(Rect2(bar.position, Vector2(40.0 * fill, 6)), bar_color)
	draw_rect(bar, Color(1, 1, 1, 0.4), false, 1.0)
	if barrier:
		var shield := up * 9.0
		draw_circle(shield, 18.0, Color(0.5, 0.85, 1.0, 0.12))
		draw_arc(shield, 18.0, 0, TAU, 32, Color(0.6, 0.9, 1.0, 0.7 + 0.2 * sin(_bob * 3.0)), 2.0)
	# Status dots left of the HP bar: green = poisoned, gold = has a crate buff.
	var dot := head + Vector2(-26, 3)
	if poison_turns > 0:
		draw_circle(dot, 3.5, Color(0.4, 1.0, 0.35))
		dot.x -= 9.0
	if not buffs.is_empty():
		draw_circle(dot, 3.5, Color(1.0, 0.8, 0.25))
		dot.x -= 9.0
	# Element powers: red up arrow = damage up, blue down arrow = damage down, green plus = heal next round.
	if power_bonus > 0.001:
		var c := Weapons.ELEMENT_INFO.fire.color
		draw_colored_polygon(PackedVector2Array([dot + Vector2(0, -5), dot + Vector2(-4.5, 2), dot + Vector2(4.5, 2)]), c)
		dot.x -= 10.0
	elif power_bonus < -0.001:
		var c := Weapons.ELEMENT_INFO.water.color
		draw_colored_polygon(PackedVector2Array([dot + Vector2(0, 5), dot + Vector2(-4.5, -2), dot + Vector2(4.5, -2)]), c)
		dot.x -= 10.0
	if bloom_next:
		var c := Weapons.ELEMENT_INFO.wood.color
		draw_rect(Rect2(dot + Vector2(-4, -1), Vector2(8, 2.5)), c)
		draw_rect(Rect2(dot + Vector2(-1.25, -4), Vector2(2.5, 8)), c)
	draw_string(font, head + Vector2(-30, -4), unit_name, HORIZONTAL_ALIGNMENT_CENTER, 60, 11, Color(1, 1, 1, 0.9))
	if order_num > 0 and alive:
		# This round's turn order, right of the HP bar (dim once the unit has played).
		var spot := head + Vector2(30, 3)
		var a := 0.35 if order_done and not is_active else 1.0
		draw_circle(spot, 7.5, Color(color, 0.9 * a))
		draw_string(font, spot + Vector2(-7.5, 4.5), str(order_num), HORIZONTAL_ALIGNMENT_CENTER, 15, 12, Color(0.05, 0.05, 0.1, a))
	if is_active:
		var y := -14.0 + sin(_bob * 5.0) * 3.0
		var tip := head + Vector2(0, y)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-6, -9), tip + Vector2(6, -9)]), Color(1, 1, 0.4))
