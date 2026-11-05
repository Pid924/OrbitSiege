extends Node2D
## Title screen with stage select.

const Starfield := preload("res://scripts/world/starfield.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")
const HowToPlay := preload("res://scripts/ui/how_to_play.gd")
const L := preload("res://scripts/game/i18n.gd")

var guide_button: Button
var bot_button: Button
var charge_button: Button
var aim_button: Button
var touch_button: Button
var ui: CanvasLayer
var help_open := false

## Flag taps in this order switch debug mode on or off: Thai Dutch Thai German, twice.
const DEBUG_CODE := ["th", "nl", "th", "de", "th", "nl", "th", "de"]
static var flag_taps: Array = []


func _ready() -> void:
	ThemeDB.fallback_font = preload("res://assets/fonts/ui_font.tres")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var stars := Starfield.new()
	add_child(stars)
	stars.generate(rng)

	ui = CanvasLayer.new()
	add_child(ui)
	var title := _label("ORBIT SIEGE", Vector2(0, 70), 84)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	ui.add_child(title)
	ui.add_child(_label(L.t("เกมยิงปืนใหญ่ผลัดตาในอวกาศ  ·  ตั้งค่าแล้วเลือกด่านเพื่อเริ่ม"), Vector2(0, 185), 22))
	_build_flags()

	guide_button = _option_button(Vector2(299, 236))
	guide_button.pressed.connect(func():
		GameSettings.guide = (GameSettings.guide + 1) % GameSettings.GUIDE_OPTIONS.size()
		_refresh_options())
	ui.add_child(guide_button)
	aim_button = _option_button(Vector2(501, 236))
	aim_button.pressed.connect(func():
		GameSettings.aim_speed = (GameSettings.aim_speed + 1) % GameSettings.AIM_OPTIONS.size()
		_refresh_options())
	ui.add_child(aim_button)
	charge_button = _option_button(Vector2(703, 236))
	charge_button.pressed.connect(func():
		GameSettings.charge_speed = (GameSettings.charge_speed + 1) % GameSettings.CHARGE_OPTIONS.size()
		_refresh_options())
	ui.add_child(charge_button)
	bot_button = _option_button(Vector2(905, 236))
	bot_button.pressed.connect(func():
		GameSettings.bot_level = (GameSettings.bot_level + 1) % GameSettings.BOT_LEVELS.size()
		_refresh_options())
	ui.add_child(bot_button)
	touch_button = _option_button(Vector2(1107, 236))
	touch_button.pressed.connect(func():
		GameSettings.touch_ui = (GameSettings.touch_ui + 1) % GameSettings.TOUCH_OPTIONS.size()
		_refresh_options())
	ui.add_child(touch_button)
	_refresh_options()

	var help := Button.new()
	help.text = L.t("วิธีเล่น / อาวุธ")
	help.position = Vector2(24, 24)
	help.size = Vector2(220, 60)
	help.focus_mode = Control.FOCUS_NONE
	help.add_theme_font_size_override("font_size", 22)
	help.pressed.connect(func(): _show_help("@close", ""))
	ui.add_child(help)

	if OS.has_feature("web"):
		# Phones: full screen hides the browser bars; Android also locks to landscape.
		var full := Button.new()
		full.text = L.t("เต็มจอ")
		full.position = Vector2(1400, 24)
		full.size = Vector2(176, 60)
		full.focus_mode = Control.FOCUS_NONE
		full.add_theme_font_size_override("font_size", 22)
		full.pressed.connect(func():
			JavaScriptBridge.eval("(function(){var d=document.documentElement;var p=d.requestFullscreen?d.requestFullscreen():(d.webkitRequestFullscreen?d.webkitRequestFullscreen():null);if(p&&p.then){p.then(function(){if(screen.orientation&&screen.orientation.lock){screen.orientation.lock('landscape').catch(function(){});}}).catch(function(){});}})()", true))
		ui.add_child(full)

	for i in GameSettings.STAGE_ORDER.size():
		var id: String = GameSettings.STAGE_ORDER[i]
		var stage: Dictionary = GameSettings.STAGES[id]
		var b := Button.new()
		b.position = Vector2(400, 312 + i * 84)
		b.size = Vector2(800, 78)
		b.pressed.connect(_start.bind(id))
		var heading := Label.new()
		heading.text = L.t("ด่าน %d: %s") % [i + 1, stage.name]
		heading.position = Vector2(24, 2)
		heading.add_theme_font_size_override("font_size", 26)
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(heading)
		var desc := Label.new()
		desc.text = L.t(stage.desc)
		desc.position = Vector2(24, 40)
		desc.size = Vector2(752, 40)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 16)
		desc.modulate = Color(1, 1, 1, 0.8)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(desc)
		ui.add_child(b)
		if i == 0:
			b.grab_focus()
	ui.add_child(_label(L.t("แตะ/คลิกด่าน หรือกดเลข 1-%d เพื่อเริ่ม") % GameSettings.STAGE_ORDER.size(), Vector2(0, 738), 16))
	var version := _label("v%s" % GameSettings.VERSION + ("  ·  DEBUG" if GameSettings.debug else ""), Vector2(0, 860), 14)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.size.x = 1580
	version.modulate = Color(1, 1, 1, 0.6)
	ui.add_child(version)


## One flag per language; the chosen one is lit and framed. Picking another reloads the menu.
func _build_flags() -> void:
	var gap := 8.0
	var flag_size := Vector2(72, 48)
	var x := (1600.0 - L.LANGS.size() * (flag_size.x + gap) + gap) / 2.0
	for code in L.LANGS:
		var b := Button.new()
		b.position = Vector2(x, 18)
		b.size = flag_size + Vector2(8, 8)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = code.to_upper()
		var on: bool = code == L.lang
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.08)
		box.border_color = Color(1.0, 0.85, 0.3) if on else Color(1, 1, 1, 0.2)
		box.set_border_width_all(4 if on else 1)
		box.set_corner_radius_all(6)
		for state in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(state, box)
		var img := TextureRect.new()
		img.texture = load(L.FLAGS[code])
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_SCALE
		img.position = Vector2(4, 4)
		img.size = flag_size
		img.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(img)
		b.pressed.connect(func():
			flag_taps.append(code)
			if flag_taps.size() > DEBUG_CODE.size():
				flag_taps.pop_front()
			var toggled := flag_taps == DEBUG_CODE
			if toggled:
				GameSettings.debug = not GameSettings.debug
				flag_taps.clear()
			if toggled or code != L.lang:
				L.set_lang(code)
				get_tree().reload_current_scene())
		ui.add_child(b)
		x += flag_size.x + gap + 8


func _option_button(pos: Vector2) -> Button:
	var b := Button.new()
	b.position = pos
	b.size = Vector2(194, 60)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15 if L.lang == "th" else 14)
	return b


func _refresh_options() -> void:
	guide_button.text = L.t("เส้นนำวิถี: %s ›") % L.t(GameSettings.GUIDE_OPTIONS[GameSettings.guide][0])
	aim_button.text = L.t("หมุนปืน: %s ›") % L.t(GameSettings.AIM_OPTIONS[GameSettings.aim_speed][0])
	charge_button.text = L.t("แถบชาร์จ: %s ›") % L.t(GameSettings.CHARGE_OPTIONS[GameSettings.charge_speed][0])
	bot_button.text = L.t("บอท: %s ›") % L.t(GameSettings.BOT_LEVELS[GameSettings.bot_level][0])
	touch_button.text = L.t("ปุ่มบนจอ: %s ›") % L.t(GameSettings.TOUCH_OPTIONS[GameSettings.touch_ui])


func _label(text: String, pos: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = Vector2(1600, font_size + 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var index: int = event.physical_keycode - KEY_1
		if index >= 0 and index < GameSettings.STAGE_ORDER.size():
			_start(GameSettings.STAGE_ORDER[index])


func _start(stage_id: String) -> void:
	if help_open:
		return
	if not HowToPlay.seen():
		_show_help(L.t("เริ่มเกม"), stage_id)  # explain the game before the first match
		return
	_begin(stage_id)


func _show_help(button_text: String, stage_id: String) -> void:
	help_open = true
	var page := HowToPlay.new()
	ui.add_child(page)
	page.build(button_text)
	page.closed.connect(func():
		help_open = false
		if stage_id != "":
			_begin(stage_id))


func _begin(stage_id: String) -> void:
	GameSettings.stage = stage_id
	get_tree().change_scene_to_file("res://scenes/main.tscn")
