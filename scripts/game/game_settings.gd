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
	"orbit": {
		"name": "Orbit Field",
		"desc": "ดาวเคราะห์น้อยหลายดวง ทุกดวงมีแรงโน้มถ่วงของตัวเอง ยิงอ้อมดาวได้",
		"kind": "planets", "size": Vector2(1900, 1050),
	},
}
const STAGE_ORDER := ["drift", "titan", "orbit"]

## How much of the predicted flight path the human player sees, in seconds of flight.
const GUIDE_OPTIONS := [["ปิด", 0.0], ["สั้น", 0.35], ["กลาง", 0.9], ["ยาว", 2.0], ["เต็มเส้น", 12.0]]
const VERSION := "1.0.0"

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
