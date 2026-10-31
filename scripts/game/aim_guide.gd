extends Node2D
## Dotted predicted flight path for the human player, length set by the menu option.

var points := PackedVector2Array()
var color := Color(1, 1, 1)


func show_path(path: PackedVector2Array, c: Color) -> void:
	points = path
	color = c
	queue_redraw()


func clear() -> void:
	if not points.is_empty():
		points = PackedVector2Array()
		queue_redraw()


func _draw() -> void:
	var n := points.size()
	for i in n:
		var fade := 1.0 - float(i) / maxf(n, 1.0) * 0.7
		draw_circle(points[i], 2.2, Color(color, 0.85 * fade))
	if n > 1:
		draw_arc(points[n - 1], 6.0, 0, TAU, 16, Color(color, 0.6), 1.5)
