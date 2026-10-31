extends Node2D
## Static backdrop: stars, nebula haze and a distant sun that "blows" the solar wind.

var stars: Array = []  # [pos, size, brightness]
var nebulae: Array = []  # [pos, radius, color]
var sun_pos := Vector2.ZERO
var area := Rect2(0, 0, 1600, 900)
## Island stages: a gas giant fills the bottom of the world; falling into it is death.
var abyss := false
var abyss_y := 0.0
var _time := 0.0


func generate(rng: RandomNumberGenerator, world_size := Vector2(1600, 900)) -> void:
	# Cover more than the world so zooming out or panning never shows an empty edge.
	area = Rect2(-world_size * 0.5, world_size * 2.0)
	var count := int(320.0 * area.get_area() / (1600.0 * 900.0) / 2.5)
	for i in count:
		stars.append([area.position + Vector2(rng.randf(), rng.randf()) * area.size, rng.randf_range(0.6, 1.8), rng.randf_range(0.3, 1.0)])
	var tints := [Color(0.4, 0.2, 0.7), Color(0.1, 0.35, 0.6), Color(0.6, 0.15, 0.35)]
	for i in 4 + int(world_size.x / 800.0):
		nebulae.append([Vector2(rng.randf() * world_size.x, rng.randf() * world_size.y), rng.randf_range(180.0, 420.0), tints[rng.randi() % tints.size()]])
	sun_pos = Vector2(rng.randf_range(-60.0, world_size.x + 60.0), -80.0)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	# Twinkle is slow, so a redraw every few frames is plenty.
	if Engine.get_process_frames() % 4 == 0:
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
	if abyss:
		_draw_abyss()


func _draw_abyss() -> void:
	var radius := maxf(area.size.x, 3000.0)
	var center := Vector2(area.get_center().x, abyss_y - 35.0 + radius)
	var bands := [Color(0.55, 0.2, 0.45), Color(0.75, 0.3, 0.4), Color(0.9, 0.45, 0.35), Color(0.65, 0.22, 0.4), Color(0.45, 0.12, 0.35)]
	for k in 12:
		draw_circle(center, radius + 40.0 - k * 6.0, Color(1.0, 0.5, 0.6, 0.02 + k * 0.006))
	for k in bands.size():
		draw_circle(center, radius - k * 14.0, bands[k])
	# Swirling storm streaks on the surface.
	for k in 7:
		var y := abyss_y - 15.0 + k * 9.0
		var pts := PackedVector2Array()
		for x in range(int(area.position.x), int(area.end.x) + 1, 40):
			pts.append(Vector2(x, y + sin(x * 0.012 + _time * (0.6 + k * 0.1) + k) * 4.0))
		draw_polyline(pts, Color(1.0, 0.75, 0.6, 0.12), 2.0)
