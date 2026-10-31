extends Node2D
## Sky Lance visual: a flickering targeting line, then a wide beam slamming down. Damage is applied by the match.

const BEAM_TIME := 0.6
const LENGTH := 3000.0

var axis := Vector2.UP
var width := 100.0
var delay := 0.8
var color := Color.WHITE
var life := 0.0


func setup(pos: Vector2, up_axis: Vector2, strip_width: float, warmup: float, c: Color) -> void:
	position = pos
	axis = up_axis
	width = strip_width
	delay = warmup
	color = c


func _process(delta: float) -> void:
	life += delta
	if life > delay + BEAM_TIME:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var top := axis * LENGTH
	var perp := Vector2(-axis.y, axis.x)
	if life < delay:
		# Targeting: thin lines that close in on the strip.
		var t := life / delay
		var flicker := 0.5 + 0.5 * sin(life * 40.0)
		draw_line(top, Vector2.ZERO, Color(color, 0.4 + 0.4 * flicker), 2.0)
		for side in [-1.0, 1.0]:
			var off: Vector2 = perp * side * width * (1.6 - 0.6 * t)
			draw_line(top + off, off, Color(color, 0.25 * t), 1.5)
		draw_arc(Vector2.ZERO, width * (1.0 - 0.5 * t), 0, TAU, 32, Color(color, 0.6), 2.0)
		return
	var f := 1.0 - (life - delay) / BEAM_TIME
	for k in 4:
		var w := width * (1.0 - k * 0.22)
		var quad := PackedVector2Array([top + perp * w, perp * w, -perp * w, top - perp * w])
		draw_colored_polygon(quad, Color(color.lightened(k * 0.2), f * (0.18 + k * 0.15)))
	draw_circle(Vector2.ZERO, width * 1.1, Color(1, 1, 0.9, f * 0.5))
