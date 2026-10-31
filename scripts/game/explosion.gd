extends Node2D
## Short-lived explosion flash with debris sparks. Purely cosmetic.

var radius := 30.0
var color := Color.WHITE
var life := 0.0
var sparks: Array = []  # [pos, vel]
const DURATION := 0.6


func setup(pos: Vector2, r: float, c: Color) -> void:
	position = pos
	radius = r
	color = c
	for i in 14:
		var dir := Vector2.from_angle(randf() * TAU)
		sparks.append([Vector2.ZERO, dir * randf_range(60.0, 220.0)])


func _process(delta: float) -> void:
	life += delta
	for s in sparks:
		s[0] += s[1] * delta
		s[1] *= 0.95
	if life >= DURATION:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var t := life / DURATION
	draw_circle(Vector2.ZERO, radius * (0.4 + t * 0.8), Color(1, 0.95, 0.8, (1.0 - t) * 0.8))
	draw_arc(Vector2.ZERO, radius * (0.6 + t), 0, TAU, 40, Color(color, 1.0 - t), 3.0)
	for s in sparks:
		draw_circle(s[0], 2.0 * (1.0 - t) + 0.5, Color(color.lightened(0.3), 1.0 - t))
