extends CanvasLayer
## Read-only view of the match state: turn info, solar wind, weapon picker, power and team HP.
## The weapon cards are clickable, but clicks still go through match commands.

const Weapons := preload("res://scripts/sim/weapons.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")

const CARD_SIZE := Vector2(84, 84)

var game
var info: Label
var teams_label: Label
var stage_label: Label
var help: Label
var banner: Label
var power_bar: ProgressBar
var wind_gauge: WindGauge
var wind_title: Label
var weapon_cards: Array = []
var weapon_name: Label
var weapon_stats: Label
var weapon_desc: Label
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
	stage_label.text = "ด่าน: %s" % GameSettings.STAGES[game.stage].name


func _ready() -> void:
	info = _label(Vector2(16, 10), 20)
	teams_label = _label(Vector2(16, 44), 14)
	stage_label = _label(Vector2(640, 12), 14)
	stage_label.size = Vector2(320, 20)
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.modulate = Color(1, 1, 1, 0.7)
	help = _label(Vector2(16, 872), 13)
	help.modulate = Color(1, 1, 1, 0.6)
	help.text = "A/D เดิน   W/S เล็ง (Shift = ละเอียด)   กด SPACE ค้างเพื่อชาร์จ ปล่อยเพื่อยิง   Q/E หรือ 1-3 หรือคลิก = เปลี่ยนอาวุธ   Esc = เมนู"

	wind_title = _label(Vector2(1470, 14), 13)
	wind_gauge = WindGauge.new()
	wind_gauge.position = Vector2(1500, 36)
	wind_gauge.size = Vector2(64, 64)
	add_child(wind_gauge)

	_build_weapon_panel()

	banner = Label.new()
	banner.position = Vector2(0, 380)
	banner.size = Vector2(1600, 80)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 44)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	add_child(banner)


func _build_weapon_panel() -> void:
	var panel := Panel.new()
	panel.position = Vector2(10, 742)
	panel.size = Vector2(760, 124)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.1, 0.75)
	style.border_color = Color(1, 1, 1, 0.12)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	for i in Weapons.LIST.size():
		var w := Weapons.get_def(Weapons.LIST[i])
		var card := Button.new()
		card.position = Vector2(10 + i * (CARD_SIZE.x + 8), 8)
		card.size = CARD_SIZE
		card.icon = load(w.icon)
		card.expand_icon = true
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.focus_mode = Control.FOCUS_NONE  # keep SPACE for firing
		card.tooltip_text = w.name
		card.pressed.connect(_on_card_pressed.bind(i))
		panel.add_child(card)
		var key := Label.new()
		key.text = str(i + 1)
		key.position = Vector2(6, 2)
		key.add_theme_font_size_override("font_size", 12)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(key)
		weapon_cards.append(card)

	var text_x := 10 + Weapons.LIST.size() * (CARD_SIZE.x + 8) + 8
	weapon_name = Label.new()
	weapon_name.position = Vector2(text_x, 6)
	weapon_name.add_theme_font_size_override("font_size", 20)
	panel.add_child(weapon_name)
	weapon_stats = Label.new()
	weapon_stats.position = Vector2(text_x, 34)
	weapon_stats.add_theme_font_size_override("font_size", 13)
	weapon_stats.modulate = Color(1, 0.85, 0.5)
	panel.add_child(weapon_stats)
	weapon_desc = Label.new()
	weapon_desc.position = Vector2(text_x, 54)
	weapon_desc.size = Vector2(760 - text_x - 12, 40)
	weapon_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_desc.add_theme_font_size_override("font_size", 14)
	panel.add_child(weapon_desc)

	power_bar = ProgressBar.new()
	power_bar.position = Vector2(10, 100)
	power_bar.size = Vector2(740, 14)
	power_bar.max_value = 1.0
	power_bar.step = 0.0
	power_bar.show_percentage = false
	panel.add_child(power_bar)


func _label(pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	add_child(l)
	return l


func _on_card_pressed(index: int) -> void:
	# Only the local human team (team 0) picks weapons by mouse.
	if game.is_turn_of(0) and not game.autoplay:
		game.submit_command({"type": "weapon", "team": 0, "index": index})


func _process(delta: float) -> void:
	if game == null:
		return
	var u = game.active_unit
	if u:
		var who: String = game.TEAM_NAMES[game.current_team]
		info.text = "ตาที่ %d  -  %s: %s   %ds" % [game.turn_number, who, u.unit_name, ceili(maxf(game.turn_time_left, 0.0))]
		info.modulate = game.TEAM_COLORS[game.current_team]
		power_bar.value = u.charge
	var current: String = game.current_weapon_id()
	var w := Weapons.get_def(current)
	weapon_name.text = w.name
	weapon_stats.text = "ดาเมจ %d   รัศมีระเบิด %d" % [w.damage, w.radius]
	if w.has("bomblets"):
		weapon_stats.text += "   ลูกย่อย %d" % w.bomblets
	weapon_desc.text = w.desc
	for i in weapon_cards.size():
		var selected: bool = Weapons.LIST[i] == current
		weapon_cards[i].modulate = Color(1, 1, 1) if selected else Color(0.55, 0.55, 0.6)
		weapon_cards[i].add_theme_stylebox_override("normal", _card_style(selected))
		weapon_cards[i].add_theme_stylebox_override("hover", _card_style(selected, true))
	var lines := []
	for team in 2:
		var hp := 0
		for unit in game.units:
			if unit.team == team:
				hp += unit.hp
		lines.append("%s  เหลือ %d คน  %d HP" % [game.TEAM_NAMES[team], game.alive_count(team), hp])
	teams_label.text = "\n".join(lines)
	wind_gauge.wind = game.physics.wind
	wind_gauge.queue_redraw()
	wind_title.text = "ลมสุริยะ %d" % roundi(game.physics.wind.length())
	if game.phase != game.Phase.GAME_OVER and _banner_time > 0.0:
		_banner_time -= delta
		banner.modulate.a = clampf(_banner_time, 0.0, 1.0)


var _styles := {}
func _card_style(selected: bool, hover := false) -> StyleBoxFlat:
	var key := int(selected) * 2 + int(hover)
	if not _styles.has(key):
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.12, 0.16, 0.3) if selected else Color(0.08, 0.09, 0.15)
		if hover:
			s.bg_color = s.bg_color.lightened(0.1)
		s.border_color = Color(1, 0.85, 0.4) if selected else Color(1, 1, 1, 0.15)
		s.set_border_width_all(3 if selected else 1)
		s.set_corner_radius_all(8)
		_styles[key] = s
	return _styles[key]


func _on_turn_started(team: int, unit) -> void:
	banner.text = "%s  -  %s" % [game.TEAM_NAMES[team], unit.unit_name]
	banner.modulate = Color(game.TEAM_COLORS[team], 1.0)
	_banner_time = 1.6


func _on_game_over(winner: int) -> void:
	if winner < 0:
		banner.text = "เสมอ!   กด R เพื่อเล่นอีกครั้ง"
	elif winner == 0:
		banner.text = "ชนะแล้ว!   กด R เพื่อเล่นอีกครั้ง"
	else:
		banner.text = "บอทชนะ   กด R เพื่อเล่นอีกครั้ง"
	banner.modulate = Color.WHITE
