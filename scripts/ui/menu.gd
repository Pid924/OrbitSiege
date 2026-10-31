extends Node2D
## Title screen with stage select.

const Starfield := preload("res://scripts/world/starfield.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")


func _ready() -> void:
	ThemeDB.fallback_font = preload("res://assets/fonts/ui_font.tres")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var stars := Starfield.new()
	add_child(stars)
	stars.generate(rng)

	var ui := CanvasLayer.new()
	add_child(ui)
	var title := _label("ORBIT SIEGE", Vector2(0, 150), 84)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	ui.add_child(title)
	ui.add_child(_label("เกมยิงปืนใหญ่ผลัดตาในอวกาศ  ·  เลือกด่าน", Vector2(0, 270), 22))

	for i in GameSettings.STAGE_ORDER.size():
		var id: String = GameSettings.STAGE_ORDER[i]
		var stage: Dictionary = GameSettings.STAGES[id]
		var b := Button.new()
		b.position = Vector2(400, 360 + i * 130)
		b.size = Vector2(800, 110)
		b.pressed.connect(_start.bind(id))
		var heading := Label.new()
		heading.text = "ด่าน %d: %s" % [i + 1, stage.name]
		heading.position = Vector2(24, 12)
		heading.add_theme_font_size_override("font_size", 26)
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(heading)
		var desc := Label.new()
		desc.text = stage.desc
		desc.position = Vector2(24, 54)
		desc.size = Vector2(752, 48)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 16)
		desc.modulate = Color(1, 1, 1, 0.8)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(desc)
		ui.add_child(b)
		if i == 0:
			b.grab_focus()
	ui.add_child(_label("กด 1 / 2 หรือคลิกเพื่อเริ่ม", Vector2(0, 640), 16))


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
	GameSettings.stage = stage_id
	get_tree().change_scene_to_file("res://scenes/main.tscn")
