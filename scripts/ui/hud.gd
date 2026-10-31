extends CanvasLayer
## Read-only view of the match state: turn info, solar wind, weapon, power and team HP.

const Weapons := preload("res://scripts/sim/weapons.gd")

var game
var info: Label
var teams_label: Label
var weapon_label: Label
var help: Label
var banner: Label
var power_bar: ProgressBar
var wind_gauge: WindGauge
var wind_title: Label
var _banner_time := 0.0


class WindGauge extends Control:
	var wind := Vector2.ZERO
	var max_wind := 55.0

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, 26.0, Color(0, 0, 0, 0.45))
		draw_arc(c, 26.0, 0, TAU, 32, Color(1, 0.85, 0.5, 0.6), 1.5)
		var v := wind / max_wind * 22.0
		if v.length() > 1.0:
			draw_line(c - v, c + v, Color(1, 0.85, 0.5), 3.0)
			var tip := c + v
			var n := v.normalized()
			draw_colored_polygon(PackedVector2Array([tip + n * 6.0, tip + n.rotated(2.5) * 8.0, tip + n.rotated(-2.5) * 8.0]), Color(1, 0.85, 0.5))


func setup(game_ref) -> void:
	game = game_ref
	game.turn_started.connect(_on_turn_started)
	game.game_over.connect(_on_game_over)


func _ready() -> void:
	info = _label(Vector2(16, 12), 20)
	teams_label = _label(Vector2(16, 44), 14)
	weapon_label = _label(Vector2(16, 820), 18)
	help = _label(Vector2(16, 870), 13)
	help.modulate = Color(1, 1, 1, 0.6)
	help.text = "A/D walk   W/S aim (Shift = fine)   hold SPACE to charge, release to fire   Q/E or 1-3 weapon   Ctrl+R new map"

	wind_title = _label(Vector2(1480, 16), 13)
	wind_gauge = WindGauge.new()
	wind_gauge.position = Vector2(1500, 36)
	wind_gauge.size = Vector2(64, 64)
	add_child(wind_gauge)

	power_bar = ProgressBar.new()
	power_bar.position = Vector2(16, 848)
	power_bar.size = Vector2(300, 16)
	power_bar.max_value = 1.0
	power_bar.step = 0.0
	power_bar.show_percentage = false
	add_child(power_bar)

	banner = Label.new()
	banner.position = Vector2(0, 380)
	banner.size = Vector2(1600, 80)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 44)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	add_child(banner)


func _label(pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _process(delta: float) -> void:
	if game == null:
		return
	var u = game.active_unit
	if u:
		var who: String = game.TEAM_NAMES[game.current_team]
		info.text = "Turn %d  -  %s: %s   %ds" % [game.turn_number, who, u.unit_name, ceili(maxf(game.turn_time_left, 0.0))]
		info.modulate = game.TEAM_COLORS[game.current_team]
		power_bar.value = u.charge
	var w := Weapons.get_def(game.current_weapon_id())
	weapon_label.text = "Weapon: %s" % w.name
	var lines := []
	for team in 2:
		var hp := 0
		for unit in game.units:
			if unit.team == team:
				hp += unit.hp
		lines.append("%s  %d alive  %d HP" % [game.TEAM_NAMES[team], game.alive_count(team), hp])
	teams_label.text = "\n".join(lines)
	wind_gauge.wind = game.physics.wind
	wind_title.text = "SOLAR WIND %d" % roundi(game.physics.wind.length())
	wind_gauge.queue_redraw()
	if game.phase != game.Phase.GAME_OVER and _banner_time > 0.0:
		_banner_time -= delta
		banner.modulate.a = clampf(_banner_time, 0.0, 1.0)


func _on_turn_started(team: int, unit) -> void:
	banner.text = "%s  -  %s" % [game.TEAM_NAMES[team], unit.unit_name]
	banner.modulate = Color(game.TEAM_COLORS[team], 1.0)
	_banner_time = 1.6


func _on_game_over(winner: int) -> void:
	if winner < 0:
		banner.text = "Draw!   Press R to play again"
	elif winner == 0:
		banner.text = "Victory!   Press R to play again"
	else:
		banner.text = "The bot wins.   Press R to play again"
	banner.modulate = Color.WHITE
