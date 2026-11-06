extends Control
## On-screen buttons for phones and tablets. Holding a button sets the same state the keys
## would, on the local PlayerController, so every action still goes through match commands.

const Weapons := preload("res://scripts/sim/weapons.gd")
const L := preload("res://scripts/game/i18n.gd")

var game
var player  # PlayerController of the local team, or null in autoplay
var picker: Control
var picker_cards: Array = []
var picker_ammo: Array = []
var fine_button: Button
var held := 0  # how many on-screen buttons are held
var picker_opened := false  # this turn; the HUD stops nudging once the player has looked


## A drawn triangle, because the bundled fonts have no arrow glyphs.
class Arrow extends Control:
	var dir := Vector2.RIGHT

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.26
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([c + dir * r, c - dir * r * 0.7 + side * r, c - dir * r * 0.7 - side * r]), Color(1, 1, 1, 0.9))


func setup(game_ref, player_ref) -> void:
	game = game_ref
	player = player_ref
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_arrow_button(Vector2.LEFT, Vector2(24, 742), Vector2(124, 124), func(on): player.touch_walk = -1 if on else 0)
	_arrow_button(Vector2.RIGHT, Vector2(160, 742), Vector2(124, 124), func(on): player.touch_walk = 1 if on else 0)
	_arrow_button(Vector2.UP, Vector2(1262, 612), Vector2(120, 116), func(on): player.touch_aim = -1 if on else 0)
	_arrow_button(Vector2.DOWN, Vector2(1262, 750), Vector2(120, 116), func(on): player.touch_aim = 1 if on else 0)
	var fire := _hold_button(L.t("ยิง"), Vector2(1396, 684), Vector2(180, 180), func(on): player.touch_fire = on)
	fire.add_theme_font_size_override("font_size", 40)
	fire.add_theme_stylebox_override("normal", _style(Color(0.55, 0.16, 0.12, 0.8), 60))
	fire.add_theme_stylebox_override("pressed", _style(Color(0.85, 0.3, 0.15, 0.9), 60))
	fire.add_theme_stylebox_override("hover", _style(Color(0.55, 0.16, 0.12, 0.8), 60))

	fine_button = Button.new()
	fine_button.text = L.t("เล็งละเอียด")
	fine_button.toggle_mode = true
	fine_button.position = Vector2(1396, 612)
	fine_button.size = Vector2(180, 60)
	fine_button.focus_mode = Control.FOCUS_NONE
	fine_button.add_theme_font_size_override("font_size", 20)
	fine_button.add_theme_stylebox_override("normal", _style(Color(0.08, 0.1, 0.2, 0.7), 12))
	fine_button.add_theme_stylebox_override("hover", _style(Color(0.08, 0.1, 0.2, 0.7), 12))
	fine_button.add_theme_stylebox_override("pressed", _style(Color(0.2, 0.35, 0.6, 0.9), 12))
	fine_button.toggled.connect(func(on): player.touch_fine = on)
	add_child(fine_button)

	_build_picker()


func _arrow_button(dir: Vector2, pos: Vector2, button_size: Vector2, on_change: Callable) -> Button:
	var b := _hold_button("", pos, button_size, on_change)
	var arrow := Arrow.new()
	arrow.dir = dir
	arrow.size = button_size
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(arrow)
	return b


func _hold_button(text: String, pos: Vector2, button_size: Vector2, on_change: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = button_size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 44)
	b.add_theme_stylebox_override("normal", _style(Color(0.08, 0.1, 0.2, 0.6), 18))
	b.add_theme_stylebox_override("hover", _style(Color(0.08, 0.1, 0.2, 0.6), 18))
	b.add_theme_stylebox_override("pressed", _style(Color(0.25, 0.4, 0.7, 0.85), 18))
	b.button_down.connect(func():
		held += 1
		if player:
			on_change.call(true))
	b.button_up.connect(func():
		held = maxi(0, held - 1)
		if player:
			on_change.call(false))
	add_child(b)
	return b


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color(1, 1, 1, 0.25)
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	return s


## Full-screen weapon grid with names, big enough to tap.
func _build_picker() -> void:
	picker = ColorRect.new()
	picker.color = Color(0, 0, 0, 0.6)
	picker.size = Vector2(1600, 900)
	picker.set_meta("fit_center", true)  # keep the card grid together on wide screens
	picker.visible = false
	picker.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			picker.visible = false)
	add_child(picker)

	var title := Label.new()
	title.text = L.t("เลือกอาวุธ  (แตะที่ว่างเพื่อปิด)")
	title.position = Vector2(0, 150)
	title.size = Vector2(1600, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	picker.add_child(title)

	var card_size := Vector2(190, 200)
	for i in Weapons.LIST.size():
		var w := Weapons.get_def(Weapons.LIST[i])
		var b := Button.new()
		b.position = Vector2(305 + (i % 5) * (card_size.x + 8), 210 + (i / 5) * (card_size.y + 12))
		b.size = card_size
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pick.bind(i))
		var icon := TextureRect.new()
		icon.texture = load(w.icon)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(40, 12)
		icon.size = Vector2(110, 110)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		var name_label := Label.new()
		name_label.text = w.name
		name_label.position = Vector2(4, 126)
		name_label.size = Vector2(card_size.x - 8, 30)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name_label)
		var ammo := Label.new()
		ammo.position = Vector2(4, 160)
		ammo.size = Vector2(card_size.x - 8, 30)
		ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ammo.add_theme_font_size_override("font_size", 18)
		ammo.modulate = Color(1, 0.85, 0.5)
		ammo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ammo)
		picker.add_child(b)
		picker_cards.append(b)
		picker_ammo.append(ammo)


func open_picker() -> void:
	if player == null or not game.is_turn_of(player.team):
		return
	for i in picker_cards.size():
		var id: String = Weapons.LIST[i]
		var left: int = game.ammo_left(player.team, id)
		var usable: bool = game.weapon_available(player.team, id)
		picker_ammo[i].text = L.t("ไม่จำกัด") if left < 0 else L.t("เหลือ %d") % left
		if Weapons.get_def(id).has("hp_ratio_max") and not usable and left != 0:
			picker_ammo[i].text = L.t("ใช้ได้เมื่อ HP ไม่เกิน 40%")
		elif Weapons.get_def(id).has("min_round") and game.round_number < Weapons.get_def(id).min_round and left != 0:
			picker_ammo[i].text = L.t("ใช้ได้ตั้งแต่รอบ %d") % Weapons.get_def(id).min_round
		picker_cards[i].modulate = Color.WHITE if usable else Color(0.4, 0.4, 0.45)
	picker.visible = true
	picker_opened = true


func _pick(index: int) -> void:
	picker.visible = false
	if player:
		player.cycle_weapon(0, index)


func _process(_delta: float) -> void:
	# Release held buttons when the turn passes, so nothing keeps walking or charging.
	if player and not game.is_turn_of(player.team):
		picker.visible = false
		if fine_button.button_pressed:
			fine_button.button_pressed = false
