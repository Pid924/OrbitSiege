extends CanvasLayer
## Read-only view of the match state: turn info, solar wind, weapon picker, power and team HP.
## The weapon cards are clickable, but clicks still go through match commands.

const Weapons := preload("res://scripts/sim/weapons.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")
const TouchControls := preload("res://scripts/ui/touch_controls.gd")

const CARD_SIZE := Vector2(60, 60)
const PANEL_WIDTH := 1160.0

var game
var info: Label
var teams_label: Label
var stage_label: Label
var event_label: Label
var help: Label
var banner: Label
var power_bar: ProgressBar
var wind_gauge: WindGauge
var wind_title: Label
var weapon_cards: Array = []
var ammo_labels: Array = []
var weapon_name: Label
var weapon_stats: Label
var weapon_desc: Label
var _banner_time := 0.0
var touch := false
var touch_controls: Control
var current_card: Button
var replay_button: Button
var order_label: Label
var _round_text := ""


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
	game.round_started.connect(_on_round_started)
	game.turn_started.connect(_on_turn_started)
	game.game_over.connect(_on_game_over)
	stage_label.text = "ด่าน: %s   ·   v%s" % [GameSettings.STAGES[game.stage].name, GameSettings.VERSION]
	if touch:
		touch_controls = TouchControls.new()
		add_child(touch_controls)
		move_child(touch_controls, 0)
		var player = game.controllers[0] if not game.autoplay else null
		touch_controls.setup(game, player)
		touch_controls.visible = player != null


func _ready() -> void:
	touch = GameSettings.use_touch()
	info = _label(Vector2(16, 10), 20)
	teams_label = _label(Vector2(16, 44), 14)
	order_label = _label(Vector2(16, 88), 14)
	order_label.modulate = Color(1, 1, 1, 0.85)
	stage_label = _label(Vector2(640, 12), 14)
	stage_label.size = Vector2(320, 20)
	stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_label.modulate = Color(1, 1, 1, 0.7)
	event_label = _label(Vector2(500, 36), 18)
	event_label.size = Vector2(600, 26)
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	help = _label(Vector2(16, 872), 13)
	help.modulate = Color(1, 1, 1, 0.6)
	help.text = "ปุ่มซ้าย/ขวา = เดิน   ปุ่มขึ้น/ลง = เล็ง   กดค้างปุ่มยิง = ชาร์จ ปล่อย = ยิง   แตะรูปอาวุธ = เปลี่ยน   ลากจอ = เลื่อนกล้อง   สองนิ้วถ่าง = ซูม" if touch else "A/D เดิน   W/S เล็ง (Shift = ละเอียด)   SPACE ค้าง = ชาร์จ ปล่อย = ยิง   Q/E, 1-9, 0 หรือคลิก = อาวุธ   ล้อเมาส์ = ซูม   คลิกขวาลาก = เลื่อนกล้อง   Esc = เมนู"

	var menu_button := Button.new()
	menu_button.text = "กลับเมนู"
	menu_button.position = Vector2(1340, 30)
	menu_button.size = Vector2(110, 38)
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.add_theme_font_size_override("font_size", 16)
	if touch:
		menu_button.position = Vector2(1300, 24)
		menu_button.size = Vector2(150, 64)
		menu_button.add_theme_font_size_override("font_size", 22)
	menu_button.pressed.connect(func(): game.go_to_menu())
	add_child(menu_button)

	wind_title = _label(Vector2(1470, 14), 13)
	wind_gauge = WindGauge.new()
	wind_gauge.position = Vector2(1500, 36)
	wind_gauge.size = Vector2(64, 64)
	add_child(wind_gauge)

	_build_weapon_panel()

	banner = Label.new()
	banner.position = Vector2(0, 330)
	banner.size = Vector2(1600, 200)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 44)
	banner.add_theme_color_override("font_outline_color", Color.BLACK)
	banner.add_theme_constant_override("outline_size", 8)
	add_child(banner)

	replay_button = Button.new()
	replay_button.text = "เล่นอีกครั้ง"
	replay_button.position = Vector2(640, 540)
	replay_button.size = Vector2(320, 90)
	replay_button.focus_mode = Control.FOCUS_NONE
	replay_button.add_theme_font_size_override("font_size", 32)
	replay_button.visible = false
	replay_button.pressed.connect(func(): get_tree().reload_current_scene())
	add_child(replay_button)


func _build_weapon_panel() -> void:
	var panel := Panel.new()
	panel.position = Vector2(10, 756)
	panel.size = Vector2(PANEL_WIDTH, 110)
	if touch:
		# Phones: one big card for the current weapon; tapping it opens the full picker.
		panel.position = Vector2(300, 756)
		panel.size = Vector2(946, 110)
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
		card.position = Vector2(8 + i * (CARD_SIZE.x + 5), 10)
		card.size = CARD_SIZE
		card.icon = load(w.icon)
		card.expand_icon = true
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.focus_mode = Control.FOCUS_NONE  # keep SPACE for firing
		card.tooltip_text = w.name
		card.pressed.connect(_on_card_pressed.bind(i))
		panel.add_child(card)
		card.visible = not touch
		var key := Label.new()
		key.text = str((i + 1) % 10)
		key.position = Vector2(6, 2)
		key.add_theme_font_size_override("font_size", 12)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(key)
		var ammo := Label.new()
		ammo.position = Vector2(0, CARD_SIZE.y - 18)
		ammo.size = Vector2(CARD_SIZE.x - 5, 16)
		ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ammo.add_theme_font_size_override("font_size", 12)
		ammo.add_theme_color_override("font_outline_color", Color.BLACK)
		ammo.add_theme_constant_override("outline_size", 3)
		ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(ammo)
		ammo_labels.append(ammo)
		weapon_cards.append(card)

	var text_x := 8 + Weapons.LIST.size() * (CARD_SIZE.x + 5) + 6
	if touch:
		current_card = Button.new()
		current_card.position = Vector2(8, 8)
		current_card.size = Vector2(94, 94)
		current_card.expand_icon = true
		current_card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		current_card.focus_mode = Control.FOCUS_NONE
		current_card.add_theme_stylebox_override("normal", _card_style(true))
		current_card.add_theme_stylebox_override("hover", _card_style(true))
		current_card.pressed.connect(func(): touch_controls.open_picker())
		panel.add_child(current_card)
		var swap := Label.new()
		swap.text = "แตะเปลี่ยน"
		swap.position = Vector2(0, 74)
		swap.size = Vector2(94, 18)
		swap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		swap.add_theme_font_size_override("font_size", 12)
		swap.add_theme_color_override("font_outline_color", Color.BLACK)
		swap.add_theme_constant_override("outline_size", 3)
		swap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		current_card.add_child(swap)
		text_x = 114
	weapon_name = Label.new()
	weapon_name.position = Vector2(text_x, 2)
	weapon_name.add_theme_font_size_override("font_size", 20)
	panel.add_child(weapon_name)
	weapon_stats = Label.new()
	weapon_stats.position = Vector2(text_x, 28)
	weapon_stats.add_theme_font_size_override("font_size", 13)
	weapon_stats.modulate = Color(1, 0.85, 0.5)
	panel.add_child(weapon_stats)
	weapon_desc = Label.new()
	weapon_desc.position = Vector2(text_x, 46)
	weapon_desc.size = Vector2(panel.size.x - text_x - 10, 40)
	weapon_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_desc.add_theme_font_size_override("font_size", 13)
	panel.add_child(weapon_desc)

	power_bar = ProgressBar.new()
	power_bar.position = Vector2(8, 82)
	power_bar.size = Vector2(PANEL_WIDTH - 16, 14)
	if touch:
		power_bar.position = Vector2(text_x, 86)
		power_bar.size = Vector2(panel.size.x - text_x - 10, 16)
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
		info.text = "รอบ %d  ·  ตาที่ %d  -  %s: %s   %ds" % [game.round_number, game.turn_number, who, u.unit_name, ceili(maxf(game.turn_time_left, 0.0))]
		var next: Array = game.upcoming_units().map(func(x): return "%s(%s)" % [x.unit_name, game.TEAM_NAMES[x.team]])
		order_label.text = "ต่อไปในรอบนี้: " + ("  ›  ".join(next) if not next.is_empty() else "จบรอบแล้วขึ้นรอบใหม่")
		info.modulate = game.TEAM_COLORS[game.current_team]
		power_bar.value = u.charge
	var current: String = game.current_weapon_id()
	var w := Weapons.get_def(current)
	weapon_name.text = w.name
	weapon_stats.text = _stats_text(w)
	weapon_desc.text = w.desc
	if current_card:
		current_card.icon = load(w.icon)
	var view_team: int = 0 if not game.autoplay else game.current_team
	for i in weapon_cards.size():
		var id: String = Weapons.LIST[i]
		var selected: bool = id == current
		var left: int = game.ammo_left(view_team, id)
		var usable: bool = game.weapon_available(view_team, id) if game.current_team == view_team else left != 0
		ammo_labels[i].text = "ไม่อั้น" if left < 0 else "x%d" % left
		if Weapons.get_def(id).has("hp_ratio_max") and not usable and left != 0:
			ammo_labels[i].text = "HP<=40%"
		weapon_cards[i].modulate = Color(1, 1, 1) if selected else (Color(0.7, 0.7, 0.75) if usable else Color(0.3, 0.3, 0.35))
		weapon_cards[i].add_theme_stylebox_override("normal", _card_style(selected))
		weapon_cards[i].add_theme_stylebox_override("hover", _card_style(selected, true))
	var lines := []
	for team in 2:
		var hp := 0
		for unit in game.units:
			if unit.team == team:
				hp += unit.hp
		var line := "%s  เหลือ %d คน  %d HP" % [game.TEAM_NAMES[team], game.alive_count(team), hp]
		if game.team_boost[team] > 0.0:
			line += "   (+) นัดถัดไปแรงขึ้น %d%%" % int(game.team_boost[team] * 100)
		lines.append(line)
	teams_label.text = "\n".join(lines)
	wind_gauge.wind = game.physics.wind
	wind_gauge.queue_redraw()
	wind_title.text = "ลมสุริยะ %d" % roundi(game.physics.wind.length())
	if game.phase != game.Phase.GAME_OVER and _banner_time > 0.0:
		_banner_time -= delta
		banner.modulate.a = clampf(_banner_time, 0.0, 1.0)


func _stats_text(w: Dictionary) -> String:
	var parts := []
	if w.has("heal"):
		parts.append("ฮีล %d" % w.heal)
		parts.append("ดาเมจศัตรู %d" % w.damage)
		parts.append("รัศมี %d" % w.heal_radius)
	else:
		parts.append("ดาเมจ %d" % w.damage)
		parts.append("รัศมีระเบิด %d" % w.radius)
	if w.has("bomblets"):
		parts.append("ลูกย่อย %d" % w.bomblets)
	if w.has("shots"):
		parts.append("ยิง %d ครั้ง" % w.shots)
	if w.has("spread"):
		parts.append("%d นัดพร้อมกัน" % w.spread)
	if w.has("root_radius"):
		parts.append("วงตาข่าย %d" % w.root_radius)
	return "   ".join(parts)


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


func _on_round_started(round_number: int, first_team: int, coin_toss: bool) -> void:
	var who: String = game.TEAM_NAMES[first_team]
	if coin_toss:
		_round_text = "รอบ %d   ·   สุ่มแล้ว: %s เริ่มก่อน" % [round_number, who]
	else:
		_round_text = "รอบ %d   ·   %s เริ่มก่อน (ใช้เวลาน้อยสุด)" % [round_number, who]


func _on_turn_started(team: int, unit) -> void:
	banner.text = "%s  -  %s" % [game.TEAM_NAMES[team], unit.unit_name]
	var hold := 1.6
	if _round_text != "":
		banner.text = _round_text + "\n" + banner.text
		_round_text = ""
		hold = 2.8
	var ev: String = game.event_text()
	event_label.text = "เหตุการณ์: " + ev if ev != "" else ""
	if ev != "" and hold > 2.0:  # the event is announced once, when its round starts
		banner.text += "\n" + ev
	banner.modulate = Color(game.TEAM_COLORS[team], 1.0)
	_banner_time = hold


func _on_game_over(winner: int) -> void:
	replay_button.visible = true
	if touch_controls:
		touch_controls.visible = false
	if winner < 0:
		banner.text = "เสมอ!   กด R เพื่อเล่นอีกครั้ง"
	elif winner == 0:
		banner.text = "ชนะแล้ว!   กด R เพื่อเล่นอีกครั้ง"
	else:
		banner.text = "บอทชนะ   กด R เพื่อเล่นอีกครั้ง"
	if touch:
		banner.text = banner.text.split("   ")[0]
	banner.modulate = Color.WHITE
