extends Node2D
## Damage number that drifts up and fades.

var text := ""
var color := Color.WHITE
var life := 0.0


func setup(pos: Vector2, value: String, c: Color) -> void:
	position = pos
	text = value
	color = c


func _process(delta: float) -> void:
	life += delta
	position.y -= 30.0 * delta
	if life > 1.2:
		queue_free()
	queue_redraw()


func _draw() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(-120, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 240, 18, Color(color, 1.0 - life / 1.2))
