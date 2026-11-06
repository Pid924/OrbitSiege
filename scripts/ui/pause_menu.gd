extends Control
## Pause screen. Pausing stops the whole match (turn timer, physics, bots); this node keeps
## running so it can resume. P (or the HUD button) toggles it.

const L := preload("res://scripts/game/i18n.gd")

var game


func setup(game_ref) -> void:
	game = game_ref
	process_mode = Node.PROCESS_MODE_ALWAYS
	size = Vector2(1600, 900)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.06, 0.92)
	dim.size = size
	add_child(dim)
	var title := Label.new()
	# Online the match cannot stop (the other phone keeps playing), so this is only a menu.
	title.text = L.t("หยุดเกมชั่วคราว") if game.net == null else L.t("เกมออนไลน์ไม่หยุดระหว่างเปิดเมนู")
	title.position = Vector2(0, 280)
	title.size = Vector2(1600, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	add_child(title)
	var resume := _button(L.t("เล่นต่อ"), Vector2(560, 400))
	resume.pressed.connect(func(): set_paused(false))
	var menu := _button(L.t("กลับเมนู"), Vector2(560, 520))
	menu.pressed.connect(func():
		set_paused(false)
		game.go_to_menu())


func _button(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(480, 96)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 34)
	add_child(b)
	return b


func set_paused(on: bool) -> void:
	if on and game.is_over():
		return
	if on:
		get_parent().move_child(self, -1)  # above banners and hints added later
	visible = on
	if game.net == null:
		get_tree().paused = on


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		set_paused(not visible)
		get_viewport().set_input_as_handled()
