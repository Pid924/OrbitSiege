extends Node2D
## Supply crate that drifts down under a parachute and waits to be picked up.
## Contents are rolled by the match when it is dropped; the crate only falls and draws.

const FALL_SCALE := 0.35
const MAX_FALL_SPEED := 110.0
const PICKUP_RADIUS := 24.0

var kind := "ammo"
var landed := false
var gone := false
var expire_turn := -1  # the crate vanishes at the start of this turn if nobody took it
var velocity := Vector2.ZERO
var physics
var terrain
var _time := 0.0


func setup(pos: Vector2, crate_kind: String, physics_ref, terrain_ref) -> void:
	position = pos
	kind = crate_kind
	physics = physics_ref
	terrain = terrain_ref


func tick(dt: float) -> void:
	if gone:
		return
	var down: Vector2 = -physics.up_at(position)
	if landed:
		if not terrain.is_solid(position + down * 2.0):
			landed = false  # ground blown away underneath
		return
	velocity += physics.gravity_at(position) * FALL_SCALE * dt
	velocity = velocity.limit_length(MAX_FALL_SPEED)
	var next: Vector2 = position + velocity * dt
	if terrain.is_solid(next + down):
		landed = true
		velocity = Vector2.ZERO
		return
	position = next
	if not physics.bounds.has_point(position):
		gone = true


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var up: Vector2 = physics.up_at(position)
	draw_set_transform(Vector2.ZERO, up.angle() + PI / 2.0)
	if not landed:
		# Parachute canopy and lines.
		var sway := sin(_time * 2.0) * 4.0
		draw_arc(Vector2(sway, -40), 22.0, PI, TAU, 16, Color(1, 0.6, 0.3), 6.0)
		for x in [-20.0, 0.0, 20.0]:
			draw_line(Vector2(sway + x, -40), Vector2(x * 0.4, -18), Color(1, 1, 1, 0.6), 1.0)
	# Supply crates are brown with "?"; buff crates are violet with "+" (they work on pickup).
	# Warp crates (Sky Tiers) are teal with a swirl.
	var buff := kind == "buff"
	var warp := kind == "warp"
	var fill := Color(0.42, 0.25, 0.62) if buff else Color(0.55, 0.42, 0.25)
	var trim := Color(0.85, 0.7, 1.0) if buff else Color(0.95, 0.8, 0.45)
	if warp:
		fill = Color(0.1, 0.45, 0.5)
		trim = Color(0.5, 1.0, 0.95)
	var body := Rect2(-12, -22, 24, 22)
	draw_rect(body, fill)
	draw_rect(body, trim, false, 2.0)
	if not warp:
		draw_line(Vector2(-12, -11), Vector2(12, -11), trim, 2.0)
	var glow := 0.6 + 0.4 * sin(_time * 4.0)
	var mark_color := Color(1, 0.85, 1.0, glow) if buff else Color(1, 1, 0.7, glow)
	if warp:
		draw_arc(Vector2(0, -11), 6.0, _time * 3.0, _time * 3.0 + PI * 1.5, 12, Color(0.7, 1.0, 1.0, glow), 2.0)
		draw_arc(Vector2(0, -11), 2.5, _time * 3.0 + PI, _time * 3.0 + PI * 2.2, 8, Color(0.7, 1.0, 1.0, glow), 1.5)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(-5, -6), "+" if buff else "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, mark_color)
