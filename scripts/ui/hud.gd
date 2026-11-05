extends CanvasLayer
## Read-only view of the match state: turn info, solar wind, weapon picker, power and team HP.
## The weapon cards are clickable, but clicks still go through match commands.

const Weapons := preload("res://scripts/sim/weapons.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")
const L := preload("res://scripts/game/i18n.gd")
const TouchControls := preload("res://scripts/ui/touch_controls.gd")
const PauseMenu := preload("res://scripts/ui/pause_menu.gd")

const CARD_SIZE := Vector2(60, 60)
const PANEL_WIDTH := 1160.0

var game
var info: Label
var teams_label: Label
var team_bars: TeamBars
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
var skip_button: Button
var pause_menu
var weapon_hint: Label
var _hint_pulse := 0.0
var _round_text := ""


## One HP bar per team, split into a segment per unit (empty segment = that unit is out).
class TeamBars extends Control:
	var game
	var line_height := 20.0

	func _draw() -> void:
		if game == null:
			return
		for team in 2:
			var team_units: Array = game.units.filter(func(u): return u.team == team)
			var y := team * line_height + line_height * 0.5 - 5.0
			var seg := 54.0
			for i in team_units.size():
				var u = team_units[i]
				var r := Rect2(i * (seg + 4.0), y, seg, 10.0)
				draw_rect(r, Color(0, 0, 0, 0.6))
				var fill: float = float(u.hp) / u.MAX_HP
				var c: Color = game.TEAM_COLORS[team]
				if fill <= 0.4:
					c = c.lerp(Color(1.0, 0.85, 0.3), 0.5)
				draw_rect(Rect2(r.position, Vector2(seg * fill, 10.0)), c)
				draw_rect(r, Color(1, 1, 1, 0.35), false, 1.0)


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
	stage_label.text = L.t("ด่าน: %s   ·   v%s") % [GameSettings.STAGES[game.stage].name, GameSettings.VERSION] + ("   ·   DEBUG" if GameSettings.debug else "")
	pause_menu.setup(game)
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
	team_bars = TeamBars.new()
	team_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(team_bars)
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
	help.text = L.t("ปุ่มซ้าย/ขวา = เดิน   ปุ่มขึ้น/ลง = เล็ง   กดค้างปุ่มยิง = ชาร์จ ปล่อย = ยิง   แตะรูปอาวุธ = เปลี่ยน   ลากจอ = เลื่อนกล้อง   สองนิ้วถ่าง / +- = ซูม") if touch else L.t("A/D เดิน   W/S เล็ง (Shift = ละเอียด)   SPACE ค้าง = ชาร์จ ปล่อย = ยิง   Q/E, 1-9, 0 หรือคลิก = อาวุธ   ล้อเมาส์ / +- = ซูม   คลิกขวาลาก = เลื่อนกล้อง   P = หยุด   Esc = เมนู")

	# Pause instead of a direct menu button: the menu is one tap away on the pause screen.
	var menu_button := Button.new()
	menu_button.text = L.t("หยุด") if touch else L.t("หยุด") + " (P)"
	menu_button.position = Vector2(1340, 30)
	menu_button.size = Vector2(110, 38)
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.add_theme_font_size_override("font_size", 16)
	if touch:
		menu_button.position = Vector2(1300, 24)
		menu_button.size = Vector2(150, 64)
		menu_button.add_theme_font_size_override("font_size", 22)
	menu_button.pressed.connect(func(): pause_menu.set_paused(true))
	add_child(menu_button)

	skip_button = Button.new()
	skip_button.text = L.t("ข้ามตา") if touch else L.t("ข้ามตา") + " (Enter)"
	skip_button.position = Vector2(1100, 24) if touch else Vector2(1130, 30)
	skip_button.size = Vector2(180, 64) if touch else Vector2(196, 38)
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.add_theme_font_size_override("font_size", 22 if touch else 16)
	skip_button.tooltip_text = L.t("จบตานี้เลย ใช้เวลาน้อย = รอบหน้าได้เล่นก่อน")
	skip_button.pressed.connect(func():
		if game.controllers[0].has_method("skip_turn"):
			game.controllers[0].skip_turn())
	add_child(skip_button)

	# Zoom buttons under the wind gauge (pinch and the mouse wheel work too).
	for k in 2:
		var zb := Button.new()
		zb.text = "+" if k == 0 else "-"
		zb.position = Vector2(1500, 116 + k * 86) if touch else Vector2(1516, 112 + k * 52)
		zb.size = Vector2(80, 76) if touch else Vector2(48, 44)
		zb.focus_mode = Control.FOCUS_NONE
		zb.add_theme_font_size_override("font_size", 40 if touch else 26)
		zb.tooltip_text = L.t("ซูม (+/-)")
		var factor := 1.25 if k == 0 else 0.8
		zb.pressed.connect(func(): game.camera.zoom_step(factor))
		add_child(zb)

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
	replay_button.text = L.t("เล่นอีกครั้ง")
	replay_button.position = Vector2(640, 540)
	replay_button.size = Vector2(320, 90)
	replay_button.focus_mode = Control.FOCUS_NONE
	replay_button.add_theme_font_size_override("font_size", 32)
	replay_button.visible = false
	replay_button.pressed.connect(func(): get_tree().reload_current_scene())
	add_child(replay_button)

	pause_menu = PauseMenu.new()
	add_child(pause_menu)


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
		swap.text = L.t("แตะเปลี่ยน")
		swap.position = Vector2(0, 74)
		swap.size = Vector2(94, 18)
		swap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		swap.add_theme_font_size_override("font_size", 12)
		swap.add_theme_color_override("font_outline_color", Color.BLACK)
		swap.add_theme_constant_override("outline_size", 3)
		swap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		current_card.add_child(swap)
		text_x = 114
		weapon_hint = _label(Vector2(304, 712), 20)
		weapon_hint.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
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
		var who: String = game.team_name(game.current_team)
		info.text = L.t("รอบ %d  ·  ตาที่ %d  -  %s: %s   %ds") % [game.round_number, game.turn_number, who, u.unit_name, ceili(maxf(game.turn_time_left, 0.0))]
		var next: Array = game.upcoming_units().map(func(x): return "%s(%s)" % [x.unit_name, game.team_name(x.team)])
		order_label.text = L.t("ต่อไปในรอบนี้: ") + ("  ›  ".join(next) if not next.is_empty() else L.t("จบรอบแล้วขึ้นรอบใหม่"))
		info.modulate = game.TEAM_COLORS[game.current_team]
		power_bar.value = u.charge
	var current: String = game.current_weapon_id()
	var w := Weapons.get_def(current)
	weapon_name.text = w.name
	weapon_stats.text = _stats_text(w)
	weapon_desc.text = L.t(w.desc)
	if current_card:
		current_card.icon = load(w.icon)
		_update_weapon_hint(delta)
	skip_button.visible = not game.autoplay and game.is_turn_of(0)
	var view_team: int = 0 if not game.autoplay else game.current_team
	for i in weapon_cards.size():
		var id: String = Weapons.LIST[i]
		var selected: bool = id == current
		var left: int = game.ammo_left(view_team, id)
		var usable: bool = game.weapon_available(view_team, id) if game.current_team == view_team else left != 0
		ammo_labels[i].text = L.t("ไม่อั้น") if left < 0 else "x%d" % left
		if Weapons.get_def(id).has("hp_ratio_max") and not usable and left != 0:
			ammo_labels[i].text = "HP<=40%"
		elif Weapons.get_def(id).has("min_round") and game.round_number < Weapons.get_def(id).min_round and left != 0:
			ammo_labels[i].text = L.t("รอบ %d+") % Weapons.get_def(id).min_round
		weapon_cards[i].modulate = Color(1, 1, 1) if selected else (Color(0.7, 0.7, 0.75) if usable else Color(0.3, 0.3, 0.35))
		weapon_cards[i].add_theme_stylebox_override("normal", _card_style(selected))
		weapon_cards[i].add_theme_stylebox_override("hover", _card_style(selected, true))
	var lines := []
	for team in 2:
		var hp := 0
		for unit in game.units:
			if unit.team == team:
				hp += unit.hp
		var line := L.t("%s  เหลือ %d คน") % [game.team_name(team), game.alive_count(team)]
		if game.team_boost[team] > 0.0:
			line += L.t("   (+) นัดถัดไปแรงขึ้น %d%%") % int(game.team_boost[team] * 100)
		lines.append(line)
	teams_label.text = "\n".join(lines)
	# Bars sit right of the longest team line (the text length depends on the language).
	var font := teams_label.get_theme_font("font")
	var widest := 0.0
	for line in lines:
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x)
	team_bars.game = game
	team_bars.line_height = teams_label.get_line_height()
	team_bars.position = teams_label.position + Vector2(widest + 14.0, 0)
	team_bars.queue_redraw()
	wind_gauge.wind = game.physics.wind
	wind_gauge.queue_redraw()
	wind_title.text = L.t("ลมสุริยะ %d") % roundi(game.physics.wind.length())
	if game.phase != game.Phase.GAME_OVER and _banner_time > 0.0:
		_banner_time -= delta
		banner.modulate.a = clampf(_banner_time, 0.0, 1.0)


## Phones show only the current weapon, so remind the player the others exist: a pulsing card
## and a line counting the special weapons ready to use, until they open the picker.
func _update_weapon_hint(delta: float) -> void:
	var ready := 0
	for i in range(1, Weapons.LIST.size()):
		if game.weapon_available(0, Weapons.LIST[i]):
			ready += 1
	var show: bool = game.is_turn_of(0) and not game.autoplay and ready > 0 and game.team_weapon[0] == 0 \
		and not touch_controls.picker_opened
	weapon_hint.visible = show
	weapon_hint.text = L.t("มีอาวุธพิเศษพร้อมใช้ %d แบบ  ·  แตะรูปอาวุธเพื่อเลือก") % ready
	_hint_pulse += delta
	var glow := 0.5 + 0.5 * sin(_hint_pulse * 5.0)
	current_card.modulate = Color(1, 1, 1).lerp(Color(1.6, 1.4, 0.7), glow) if show else Color.WHITE


func _stats_text(w: Dictionary) -> String:
	var parts := []
	if w.has("heal"):
		parts.append(L.t("ฮีล %d") % w.heal)
		parts.append(L.t("ดาเมจศัตรู %d") % w.damage)
		parts.append(L.t("รัศมี %d") % w.heal_radius)
	elif w.damage <= 0.0:
		parts.append(L.t("ไม่มีดาเมจ"))
		parts.append(L.t("หลุมกว้าง %d") % w.get("carve", w.radius))
	else:
		parts.append(L.t("ดาเมจ %d") % w.damage)
		parts.append(L.t("รัศมีระเบิด %d") % w.radius)
	if w.has("elev"):
		parts.append(L.t("มุม %d°-%d°") % [int(w.elev.x), int(w.elev.y)])
	if w.has("bomblets"):
		parts.append(L.t("ลูกย่อย %d") % w.bomblets)
	if w.has("shots"):
		parts.append(L.t("ยิง %d ครั้ง") % w.shots)
	if w.has("spread"):
		parts.append(L.t("%d นัดพร้อมกัน") % w.spread)
	if w.has("root_radius"):
		parts.append(L.t("วงตาข่าย %d") % w.root_radius)
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
	if touch_controls:
		touch_controls.picker_opened = false  # nudge again once per round
	var who: String = game.team_name(first_team)
	if coin_toss:
		_round_text = L.t("รอบ %d   ·   สุ่มแล้ว: %s เริ่มก่อน") % [round_number, who]
	else:
		_round_text = L.t("รอบ %d   ·   %s เริ่มก่อน (ใช้เวลาน้อยสุด)") % [round_number, who]


func _on_turn_started(team: int, unit) -> void:
	banner.text = "%s  -  %s" % [game.team_name(team), unit.unit_name]
	var hold := 1.6
	if _round_text != "":
		banner.text = _round_text + "\n" + banner.text
		_round_text = ""
		hold = 2.8
	var ev: String = game.event_text()
	event_label.text = L.t("เหตุการณ์: ") + ev if ev != "" else ""
	if ev != "" and hold > 2.0:  # the event is announced once, when its round starts
		banner.text += "\n" + ev
	banner.modulate = Color(game.TEAM_COLORS[team], 1.0)
	_banner_time = hold


func _on_game_over(winner: int) -> void:
	replay_button.visible = true
	if touch_controls:
		touch_controls.visible = false
	if winner < 0:
		banner.text = L.t("เสมอ!   กด R เพื่อเล่นอีกครั้ง")
	elif winner == 0:
		banner.text = L.t("ชนะแล้ว!   กด R เพื่อเล่นอีกครั้ง")
	else:
		banner.text = L.t("บอทชนะ   กด R เพื่อเล่นอีกครั้ง")
	if touch:
		banner.text = banner.text.split("   ")[0]
	banner.modulate = Color.WHITE
