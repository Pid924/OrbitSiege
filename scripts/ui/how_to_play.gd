extends Control
## "How to play" screen: rules, controls (keyboard or touch) and every weapon with its picture.
## The menu shows it before the first match; `closed` fires when the player is done reading.

const Weapons := preload("res://scripts/sim/weapons.gd")
const GameSettings := preload("res://scripts/game/game_settings.gd")
const L := preload("res://scripts/game/i18n.gd")
const SAVE_PATH := "user://settings.cfg"

signal closed

## One short line per weapon (the full text is on the weapon panel in game).
const TIPS := {
	"plasma": "กระสุนพื้นฐาน ระเบิดวงกว้าง ใช้ได้ตลอด",
	"cluster": "แตกเป็นลูกย่อย 5 ลูก โดนตัวจัง ๆ แตก 8 ลูก กินพื้นเยอะ",
	"driller": "ไม่มีดาเมจ เจาะพื้นเป็นหลุมใหญ่ ทำให้ศัตรูร่วง ใช้ได้ตั้งแต่รอบ 2",
	"double": "ยิง 2 นัดในตาเดียว มุมและแรงเดิม",
	"triple": "ยิง 3 นัดพร้อมกันแบบพัด ไม่โดนเพื่อน",
	"rage": "ใช้ได้เมื่อ HP ไม่เกิน 40% ระเบิดแรงที่สุด",
	"snare": "ตาข่ายวงกว้าง ศัตรูในวงเดินและหมุนปืนไม่ได้ 1 ตา",
	"mender": "ฮีลเพื่อน 25 HP และนัดถัดไปของทีมแรงขึ้น 50%",
	"seeker": "เมื่อศัตรูอยู่ในระยะ 300 จะล็อกแล้วเลี้ยวไล่เอง",
	"sky": "ยิงลูกบอกพิกัด ลำแสงจากฟ้าถล่มพื้นตรงนั้นเป็นวงกว้าง",
}

var dont_show: CheckBox


static func seen() -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(SAVE_PATH) == OK and cfg.get_value("help", "seen", false)


static func mark_seen(value: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("help", "seen", value)
	cfg.save(SAVE_PATH)


func build(button_text: String) -> void:
	size = Vector2(1600, 900)
	set_meta("fit_center", true)  # a dense page: keep it together, centred
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.08, 1.0)
	bg.size = size
	add_child(bg)

	var title := _text(L.t("วิธีเล่น Orbit Siege"), Vector2(40, 22), 34, Vector2(900, 50))
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))

	var touch := GameSettings.use_touch()
	# Thai has no spaces between words, so lines are broken by hand ("\n").
	var rules := [
		"ทำให้ศัตรูทั้ง 3 ตัวหมด HP หรือร่วงตกฉาก",
		"ผลัดกันยิงตาละ 30 วินาที กระสุนโดนแรงโน้มถ่วง\nและลมสุริยะ (ลูกศรมุมขวาบน)",
		"ทุกตัวเล่นครบ 1 ตา = 1 รอบ รอบแรกสุ่มทีมเริ่ม\nรอบต่อไปตัวที่ใช้เวลาน้อยสุดได้เริ่มก่อน",
		"ขยับไม่ได้หรือไม่อยากยิง กด \"ข้ามตา\"\nใช้เวลาน้อย รอบหน้าได้เล่นก่อน",
		"จบทุกรอบมีกล่องเสบียงตก เก็บได้กระสุนพิเศษ +1",
		"บางรอบมีเหตุการณ์สุ่ม: อาวุธแรงขึ้น/เบาลง\nเวลาเพิ่ม/ลด วงระเบิดกว้างขึ้น/แคบลง",
		"อาวุธแต่ละแบบเล็งได้ในช่วงองศาของตัวเอง\nเดินซ้าย/ขวาเพื่อหันปืนไปอีกฝั่ง",
		"ยิงพื้นใต้เท้าศัตรูให้ร่วงลงไปก็ชนะได้",
	]
	var controls := [
		"ลูกศรซ้าย/ขวา กดค้าง = เดิน",
		"ลูกศรขึ้น/ลง กดค้าง = หมุนปืน",
		"\"ยิง\" กดค้าง = ชาร์จ  ปล่อย = ยิง",
		"แตะรูปอาวุธตรงกลางล่าง = เลือกอาวุธ",
		"ลากนิ้ว = เลื่อนกล้อง  สองนิ้ว = ซูม",
	] if touch else [
		"A / D = เดิน   W / S = หมุนปืน (Shift = ละเอียด)",
		"Space กดค้าง = ชาร์จ  ปล่อย = ยิง",
		"1-9, 0, Q / E หรือคลิกการ์ด = เลือกอาวุธ",
		"Enter = ข้ามตา   P = หยุด   ล้อเมาส์ = ซูม",
	]
	var y := 84.0
	y = _section(L.t("กติกา"), rules, y)
	y = _section(L.t("การควบคุม (มือถือ)") if touch else L.t("การควบคุม (คีย์บอร์ด)"), controls, y + 8)

	_text(L.t("อาวุธทั้งหมด"), Vector2(680, 84), 24, Vector2(900, 34)).add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	for i in Weapons.LIST.size():
		var w := Weapons.get_def(Weapons.LIST[i])
		var row_y := 122.0 + i * 68.0
		var icon := TextureRect.new()
		icon.texture = load(w.icon)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(680, row_y)
		icon.size = Vector2(56, 56)
		add_child(icon)
		var uses := L.t("ใช้ได้ไม่จำกัด") if not w.has("ammo") else L.t("%d ครั้งต่อเกม") % int(w.ammo)
		var dmg := L.t("ไม่มีดาเมจ") if w.damage <= 0.0 else L.t("ดาเมจ %d") % int(w.damage)
		var angle := L.t("มุม %d°-%d°") % [int(w.elev.x), int(w.elev.y)] if w.has("elev") else ""
		var head := _text("%d. %s  ·  %s  ·  %s  ·  %s" % [(i + 1) % 10, w.name, dmg, uses, angle], Vector2(746, row_y - 4), 19, Vector2(830, 26))
		head.add_theme_color_override("font_color", w.color.lightened(0.3))
		var desc := _text(L.t(TIPS.get(Weapons.LIST[i], w.desc)), Vector2(746, row_y + 24), 16, Vector2(830, 26))
		desc.modulate = Color(1, 1, 1, 0.85)

	dont_show = CheckBox.new()
	dont_show.text = L.t("ไม่ต้องแสดงก่อนเริ่มเกมอีก")
	dont_show.position = Vector2(40, 836)
	dont_show.focus_mode = Control.FOCUS_NONE
	dont_show.add_theme_font_size_override("font_size", 18)
	dont_show.button_pressed = seen()
	add_child(dont_show)

	var go := Button.new()
	go.text = L.t(button_text)
	go.position = Vector2(1330, 820)
	go.size = Vector2(230, 66)
	go.focus_mode = Control.FOCUS_NONE
	go.add_theme_font_size_override("font_size", 26)
	go.pressed.connect(func():
		mark_seen(dont_show.button_pressed)
		closed.emit()
		queue_free())
	add_child(go)


func _section(heading: String, lines: Array, y: float) -> float:
	_text(heading, Vector2(40, y), 26, Vector2(580, 34)).add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	y += 36.0
	for raw in lines:
		var line: String = L.t(raw)
		var l := _text("•  " + line.replace("\n", "\n    "), Vector2(40, y), 20, Vector2(620, 30))
		y += 30.0 * (line.count("\n") + 1) + 6.0
	return y


func _text(text: String, pos: Vector2, font_size: int, box: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = box
	l.add_theme_font_size_override("font_size", font_size)
	add_child(l)
	return l
