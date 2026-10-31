extends Node2D
## Static backdrop: stars, nebula haze and a distant sun that "blows" the solar wind.

var stars: Array = []  # [pos, size, brightness]
var nebulae: Array = []  # [pos, radius, color]
var sun_pos := Vector2.ZERO
var _time := 0.0


func generate(rng: RandomNumberGenerator) -> void:
	for i in 320:
		stars.append([Vector2(rng.randf() * 1600.0, rng.randf() * 900.0), rng.randf_range(0.6, 1.8), rng.randf_range(0.3, 1.0)])
	var tints := [Color(0.4, 0.2, 0.7), Color(0.1, 0.35, 0.6), Color(0.6, 0.15, 0.35)]
	for i in 4:
		nebulae.append([Vector2(rng.randf() * 1600.0, rng.randf() * 900.0), rng.randf_range(180.0, 380.0), tints[rng.randi() % tints.size()]])
	sun_pos = Vector2(rng.randf_range(-60.0, 1660.0), -80.0)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for n in nebulae:
		var c: Color = n[2]
		for k in 6:
			draw_circle(n[0], n[1] * (1.0 - k * 0.14), Color(c, 0.025))
	for k in 8:
		draw_circle(sun_pos, 260.0 - k * 30.0, Color(1.0, 0.8, 0.45, 0.03 + k * 0.012))
	for i in stars.size():
		var s: Array = stars[i]
		var twinkle := 0.75 + 0.25 * sin(_time * 2.0 + float(i))
		draw_circle(s[0], s[1], Color(1, 1, 1, s[2] * twinkle))
