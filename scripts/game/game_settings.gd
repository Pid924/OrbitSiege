extends RefCounted
## Stage list and the options picked on the menu, carried into a match.

const STAGES := {
	"drift": {
		"name": "Asteroid Drift",
		"desc": "เกาะหินลอยกลางอวกาศ แรงโน้มถ่วงดึงลงล่าง ตกลงไปในชั้นบรรยากาศดาวแก๊สยักษ์ = ตาย",
		"kind": "islands", "size": Vector2(2200, 1100),
		"island_width": Vector2(380, 560), "gap": Vector2(50, 100), "depth": Vector2(180, 280),
	},
	"titan": {
		"name": "Titan Shelf",
		"desc": "ฉากใหญ่พิเศษ แผ่นดินลอยฟ้าผืนยักษ์ หลุมลึก ร่วงยาก ใช้ล้อเมาส์ซูมดูทั้งฉาก",
		"kind": "islands", "size": Vector2(3400, 1500),
		"island_width": Vector2(700, 1100), "gap": Vector2(60, 110), "depth": Vector2(320, 460),
	},
	"reef": {
		"name": "Shatter Reef",
		"desc": "แนวหินเปราะ พื้นบาง ระเบิดทะลุง่าย ใช้ Void Driller กับ Star Cluster ทำให้ศัตรูร่วง",
		"kind": "islands", "size": Vector2(2400, 1150),
		"island_width": Vector2(300, 440), "gap": Vector2(60, 110), "depth": Vector2(40, 70),
		"carve_mult": 1.25, "sky_rocks": 2, "spawn_gap": 300.0,
	},
	"orbit": {
		"name": "Orbit Field",
		"desc": "ดาวยักษ์ดวงเดียว แรงโน้มถ่วงดึงเข้าหาใจกลางดาว ยิงโค้งอ้อมดาวไปหาศัตรูอีกฝั่งได้",
		"kind": "planets", "size": Vector2(2400, 1650), "planet_count": 1, "planet_radius": Vector2(560, 560),
	},
}
const STAGE_ORDER := ["drift", "titan", "orbit", "reef"]

## How much of the predicted flight path the human player sees, in seconds of flight.
const GUIDE_OPTIONS := [["ปิด", 0.0], ["สั้น", 0.35], ["กลาง", 0.9], ["ยาว", 2.0], ["เต็มเส้น", 12.0]]
const VERSION := "1.5.4"

## [label, seconds to fill the charge bar] for the human player.
const CHARGE_OPTIONS := [["ช้ามาก", 5.0], ["ช้า", 3.6], ["ปกติ", 2.6], ["เร็ว", 1.6]]
## [label, barrel turn speed in rad/s] for the human player. Shift aims at a quarter of this.
const AIM_OPTIONS := [["ช้ามาก", 0.4], ["ช้า", 0.6], ["ปกติ", 0.8], ["เร็ว", 1.2]]
## [label, aim error (deg), power error]
const BOT_LEVELS := [["ง่าย", 3.0, 0.03], ["ปกติ", 0.8, 0.01], ["ยาก", 0.25, 0.004]]

static var stage := "drift"
static var guide := 4  # full line
static var bot_level := 0  # easy
static var charge_speed := 0  # slowest
static var aim_speed := 0  # slowest
## On-screen touch controls: auto (touchscreen detected), always on, off.
const TOUCH_OPTIONS := ["อัตโนมัติ", "เปิด", "ปิด"]
static var touch_ui := 0
## Secret test mode (flag code in the menu): the player team has unlimited ammo and Last Stand at any HP.
static var debug := false


static func use_touch() -> bool:
	if touch_ui == 1 or "--touch" in OS.get_cmdline_user_args():
		return true
	if touch_ui == 2:
		return false
	return DisplayServer.is_touchscreen_available()
