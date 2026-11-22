extends RefCounted
## Weapon definitions. Pure data, referenced by id so a network layer can send just the id.
## Optional keys:
##   ammo         uses per team per match (missing = unlimited)
##   shots        fire again with the same aim after the previous shell lands
##   spread       number of shells fired at once in a fan, spread_deg apart
##   elev         Vector2(min, max) barrel angle in degrees above the ground (0 = flat, 90 = straight up)
##   element      fire / water / wood shell, see ELEMENT_INFO
##   elemental    takes the shooter's element (edge +/-25% like the element shells)
##   special      element power, used from slot 0 without ending the turn
##   friendly_safe  never hurts (or bursts on) the shooter's own team
##   min_round    first round in which it may be fired
##   hp_ratio_max only usable while the shooter's HP is at or below this ratio
##   root_radius  enemies inside cannot walk on their next turn
##   heal, heal_radius  heals teammates in range; no crater
##   boost        the team's next shot (any weapon) deals this much more damage
##   carve        crater radius when it differs from the damage radius
##   drill_time   keeps boring through the ground before detonating
##   drill_width  radius of the tunnel it bores (default 9)
##   homing       after homing_delay, locks on the nearest enemy and steers at turn_rate (rad/s)
##   strike_width marks a spot; a beam from the sky then hits a strip this wide (each side)
##   miss_carve   crater radius when it bursts in the ground without touching a unit
##   direct_bomblets  bomblet count when it bursts right on a unit

## Slot 1 "plasma" turns into the active unit's element shell (plasma_fire / _water / _wood);
## slot 0 "special" is the unit's once-per-match element power (special_fire / _water / _wood).
const LIST := ["plasma", "cluster", "driller", "double", "triple", "rage", "snare", "seeker", "sky", "special"]

## Each team has one unit of each element. Fire beats wood, wood beats water, water beats fire:
## an element shell deals ELEMENT_EDGE more to the element it beats and that much less to the one that beats it.
const ELEMENTS := ["fire", "water", "wood"]
const ELEMENT_EDGE := 0.25
const ELEMENT_INFO := {
	"fire": {"name": "ไฟ", "color": Color(1.0, 0.14, 0.1), "beats": "wood", "walk": 1.0},
	"water": {"name": "น้ำ", "color": Color(0.3, 0.62, 1.0), "beats": "fire", "walk": 1.25},
	"wood": {"name": "ไม้", "color": Color(0.36, 0.85, 0.32), "beats": "water", "walk": 0.75},
}
## Element powers (slot 0): how many rounds they last, counting the round they are used in.
const SPECIAL_ROUNDS := 2
const SPECIAL_DMG := 0.25
const SPECIAL_HEAL := 15

const DATA := {
	# Not in LIST: the shot a teleport crate turns your next shot into.
	"teleport": {
		"name": "Teleport", "radius": 0.0, "damage": 0.0, "teleport": true, "elev": Vector2(-70, 90),
		"color": Color(0.75, 0.55, 1.0), "icon": "res://assets/weapons/seeker.png",
		"desc": "วาร์ปไปจุดที่กระสุนตก ถ้าไปยืนตรงนั้นไม่ได้ถือว่าพลาด",
	},
	"plasma": {
		"name": "Plasma Shell", "radius": 40.0, "damage": 30.0, "elev": Vector2(0, 50),
		"color": Color(0.4, 0.9, 1.0), "icon": "res://assets/weapons/plasma.png",
		"desc": "กระสุนพลาสมา เปลี่ยนตามธาตุของตัวที่เล่น (ไฟ / น้ำ / ไม้) ใช้ได้ไม่จำกัด",
	},
	"plasma_fire": {
		"name": "Fire Plasma", "radius": 40.0, "damage": 40.0, "elev": Vector2(0, 30), "element": "fire",
		"color": Color(1.0, 0.25, 0.18), "icon": "res://assets/weapons/plasma_fire.png",
		"desc": "พลาสมาธาตุไฟ แรงสุดแต่ยิงได้แค่มุมต่ำ ใส่ธาตุไม้แรงขึ้น 25% ใส่ธาตุน้ำเบาลง 25%",
	},
	"plasma_water": {
		"name": "Water Plasma", "radius": 50.0, "damage": 30.0, "elev": Vector2(0, 50), "element": "water", "friendly_safe": true,
		"color": Color(0.35, 0.7, 1.0), "icon": "res://assets/weapons/plasma_water.png",
		"desc": "พลาสมาธาตุน้ำ ระเบิดกว้าง ไม่โดนพวกเดียวกัน ใส่ธาตุไฟแรงขึ้น 25% ใส่ธาตุไม้เบาลง 25%",
	},
	"plasma_wood": {
		"name": "Wood Plasma", "radius": 30.0, "damage": 20.0, "elev": Vector2(0, 90), "element": "wood",
		"color": Color(0.45, 0.9, 0.4), "icon": "res://assets/weapons/plasma_wood.png",
		"desc": "พลาสมาธาตุไม้ ยิงได้ทุกมุมถึงตั้งฉาก ใส่ธาตุน้ำแรงขึ้น 25% ใส่ธาตุไฟเบาลง 25%",
	},
	"special": {
		"name": "Element Power", "radius": 0.0, "damage": 0.0, "special": true,
		"color": Color(1.0, 0.9, 0.5), "icon": "res://assets/weapons/special.png",
		"desc": "ท่าพิเศษตามธาตุของตัวที่เล่น ตัวละครละ 1 ครั้งต่อเกม กดแล้วยังยิงต่อในตานั้นได้",
	},
	"special_fire": {
		"name": "Blaze Rally", "radius": 0.0, "damage": 0.0, "special": "rally",
		"color": Color(1.0, 0.25, 0.18), "icon": "res://assets/weapons/special_fire.png",
		"desc": "ทั้งทีมดาเมจ +25% เป็นเวลา 2 รอบ (นับรอบนี้) ใช้ได้ครั้งเดียว กดแล้วยังยิงต่อได้",
	},
	"special_water": {
		"name": "Tidal Curse", "radius": 0.0, "damage": 0.0, "special": "curse",
		"color": Color(0.35, 0.7, 1.0), "icon": "res://assets/weapons/special_water.png",
		"desc": "ทีมศัตรูดาเมจ -25% เป็นเวลา 2 รอบ (นับรอบนี้) ใช้ได้ครั้งเดียว กดแล้วยังยิงต่อได้",
	},
	"special_wood": {
		"name": "Verdant Bloom", "radius": 0.0, "damage": 0.0, "special": "bloom",
		"color": Color(0.45, 0.9, 0.4), "icon": "res://assets/weapons/special_wood.png",
		"desc": "ทั้งทีม +15 HP ทันที และอีก 15 ตอนเริ่มรอบหน้า (2 รอบ) ใช้ได้ครั้งเดียว กดแล้วยังยิงต่อได้",
	},
	"cluster": {
		"name": "Star Cluster", "radius": 24.0, "carve": 38.0, "damage": 20.0, "ammo": 3, "friendly_safe": true, "elev": Vector2(20, 80),
		"color": Color(1.0, 0.75, 0.3), "bomblets": 5, "direct_bomblets": 8, "direct_bomblet_speed": Vector2(60, 120), "icon": "res://assets/weapons/cluster.png",
		"desc": "กระทบแล้วแตกเป็นลูกย่อย 5 ลูก ถ้าโดนตัวศัตรูจัง ๆ แตก 8 ลูก กินพื้นหายไปเยอะ ทำให้ศัตรูร่วงได้",
	},
	"driller": {
		"name": "Void Driller", "radius": 34.0, "carve": 78.0, "damage": 10.0, "direct_bonus": 20.0, "ammo": 2, "min_round": 2, "elev": Vector2(-60, 45),
		"color": Color(0.8, 0.45, 1.0), "drill_time": 0.8, "drill_width": 30.0, "icon": "res://assets/weapons/driller.png",
		"desc": "เจาะทะลุพื้นเป็นอุโมงค์กว้าง แล้วทลายพื้นเป็นหลุมใหญ่ (รัศมี 78) ทำให้ศัตรูร่วง ดาเมจ 10 ถ้าโดนตัวก่อนเจาะพื้น +20 ใช้ได้ตั้งแต่รอบ 2",
	},
	"double": {
		"name": "Twin Strike", "radius": 30.0, "damage": 40.0, "ammo": 2, "shots": 2, "elev": Vector2(0, 60),
		"color": Color(0.5, 1.0, 0.7), "icon": "res://assets/weapons/double.png",
		"elemental": true,
		"desc": "ยิงได้ 2 ครั้งในตาเดียว ด้วยมุมและแรงเดิม นัดที่สองซ้ำจุดเดิมให้หลุมลึกขึ้น\nใช้ธาตุของคนยิง ชนะธาตุ +25% แพ้ธาตุ -25%",
	},
	"triple": {
		"name": "Trident", "radius": 26.0, "damage": 40.0, "ammo": 4, "spread": 3, "spread_deg": 6.0, "volley_gap": 0.5, "side_wind_mult": 2.5, "friendly_safe": true, "elev": Vector2(-70, 90),
		"color": Color(1.0, 0.95, 0.45), "icon": "res://assets/weapons/triple.png",
		"elemental": true,
		"desc": "ยิง 3 นัดแบบพัด ทีละนัดห่างกัน 0.5 วินาที เล็งได้ทุกมุม ลูกข้างโดนลมแรงกว่าลูกหลัก ไม่โดนเพื่อนร่วมทีม\nใช้ธาตุของคนยิง ชนะธาตุ +25% แพ้ธาตุ -25%",
	},
	"rage": {
		"name": "Last Stand", "radius": 60.0, "damage": 80.0, "ammo": 1, "hp_ratio_max": 0.4, "elev": Vector2(0, 60),
		"color": Color(1.0, 0.3, 0.2), "icon": "res://assets/weapons/rage.png",
		"desc": "ปลดล็อกเมื่อเลือดเหลือไม่เกิน 40% ระเบิดรุนแรงที่สุดในเกม ใช้ได้ครั้งเดียว",
	},
	"snare": {
		"name": "Stasis Net", "radius": 22.0, "damage": 10.0, "ammo": 2, "root_radius": 140.0, "elev": Vector2(10, 80),
		"color": Color(0.45, 0.75, 1.0), "icon": "res://assets/weapons/snare.png",
		"desc": "ปล่อยตาข่ายพลังงานวงกว้าง ศัตรูในวงโดนสุ่มมุมปืนใหม่ และจะเดินและหมุนปืนไม่ได้ในตาถัดไปของตัวเอง\nถ้าโดนซ้ำตอนติดตาข่ายอยู่ จะถูกข้ามตาไปเลย และได้คิวช้าสุดในรอบหน้า",
	},
	"seeker": {
		"name": "Hunter Seeker", "radius": 34.0, "damage": 40.0, "ammo": 1, "elev": Vector2(0, 90),
		"homing": true, "homing_delay": 0.45, "turn_rate": 3.2, "lock_range": 300.0,
		"color": Color(1.0, 0.45, 0.85), "icon": "res://assets/weapons/seeker.png",
		"desc": "กระสุนติดตาม บินตามวิถีปกติจนมีศัตรูอยู่ในระยะ 300 แล้วล็อกเป้า เลี้ยวตามไปเองไม่สนแรงโน้มถ่วง ใช้ได้ครั้งเดียว",
	},
	"sky": {
		"name": "Sky Lance", "radius": 0.0, "damage": 20.0, "ammo": 2, "elev": Vector2(30, 90),
		"strike_width": 110.0, "strike_delay": 0.8, "strike_carve": 46.0,
		"color": Color(1.0, 0.92, 0.6), "icon": "res://assets/weapons/sky.png",
		"desc": "ยิงลูกบอกพิกัดไปตกตรงไหน ลำแสงจากฟ้าจะยิงลงมาถล่มพื้นตรงนั้นเป็นวงกว้าง ใช้ได้ 2 ครั้ง",
	},
	# Spawned by the cluster shell, not selectable.
	"bomblet": {
		"name": "Bomblet", "radius": 20.0, "carve": 32.0, "damage": 14.0, "friendly_safe": true,  # Star Cluster spares teammates
		"color": Color(1.0, 0.55, 0.2),
	},
}


static func get_def(id: String) -> Dictionary:
	return DATA[id]


## The real weapon behind a slot for a unit of `element`: slot 1 and slot 0 depend on it.
static func for_element(id: String, element: String) -> String:
	if element != "" and (id == "plasma" or id == "special"):
		return id + "_" + element
	return id
