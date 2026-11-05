extends RefCounted
## Weapon definitions. Pure data, referenced by id so a network layer can send just the id.
## Optional keys:
##   ammo         uses per team per match (missing = unlimited)
##   shots        fire again with the same aim after the previous shell lands
##   spread       number of shells fired at once in a fan, spread_deg apart
##   elev         Vector2(min, max) barrel angle in degrees above the ground (0 = flat, 90 = straight up)
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

const LIST := ["plasma", "cluster", "driller", "double", "triple", "rage", "snare", "mender", "seeker", "sky"]

const DATA := {
	"plasma": {
		"name": "Plasma Shell", "radius": 40.0, "damage": 45.0, "elev": Vector2(0, 45),
		"color": Color(0.4, 0.9, 1.0), "icon": "res://assets/weapons/plasma.png",
		"desc": "กระสุนพลาสมามาตรฐาน ระเบิดวงกว้าง ดาเมจสูง ใช้ได้ไม่จำกัด",
	},
	"cluster": {
		"name": "Star Cluster", "radius": 24.0, "carve": 38.0, "damage": 20.0, "ammo": 5, "elev": Vector2(20, 80),
		"color": Color(1.0, 0.75, 0.3), "bomblets": 5, "direct_bomblets": 8, "icon": "res://assets/weapons/cluster.png",
		"desc": "กระทบแล้วแตกเป็นลูกย่อย 5 ลูก ถ้าโดนตัวศัตรูจัง ๆ แตก 8 ลูก กินพื้นหายไปเยอะ ทำให้ศัตรูร่วงได้",
	},
	"driller": {
		"name": "Void Driller", "radius": 34.0, "carve": 78.0, "damage": 0.0, "ammo": 2, "min_round": 2, "elev": Vector2(-60, 45),
		"color": Color(0.8, 0.45, 1.0), "drill_time": 0.8, "drill_width": 22.0, "icon": "res://assets/weapons/driller.png",
		"desc": "ไม่มีดาเมจ เจาะทะลุพื้นเป็นอุโมงค์กว้าง แล้วทลายพื้นเป็นหลุมใหญ่ (รัศมี 78) ทำให้ศัตรูร่วง ใช้ได้ตั้งแต่รอบ 2",
	},
	"double": {
		"name": "Twin Strike", "radius": 30.0, "damage": 40.0, "ammo": 2, "shots": 2, "elev": Vector2(0, 60),
		"color": Color(0.5, 1.0, 0.7), "icon": "res://assets/weapons/double.png",
		"desc": "ยิงได้ 2 ครั้งในตาเดียว ด้วยมุมและแรงเดิม นัดที่สองซ้ำจุดเดิมให้หลุมลึกขึ้น",
	},
	"triple": {
		"name": "Trident", "radius": 26.0, "damage": 40.0, "ammo": 4, "spread": 3, "spread_deg": 6.0, "elev": Vector2(0, 50),
		"color": Color(1.0, 0.95, 0.45), "icon": "res://assets/weapons/triple.png",
		"desc": "ยิงออกเป็น 3 นัดพร้อมกันแบบพัด กระจายโดนศัตรูได้ถึง 3 ตัว",
	},
	"rage": {
		"name": "Last Stand", "radius": 60.0, "damage": 80.0, "ammo": 1, "hp_ratio_max": 0.4, "elev": Vector2(0, 60),
		"color": Color(1.0, 0.3, 0.2), "icon": "res://assets/weapons/rage.png",
		"desc": "ปลดล็อกเมื่อเลือดเหลือไม่เกิน 40% ระเบิดรุนแรงที่สุดในเกม ใช้ได้ครั้งเดียว",
	},
	"snare": {
		"name": "Stasis Net", "radius": 22.0, "damage": 10.0, "ammo": 2, "root_radius": 140.0, "elev": Vector2(10, 80),
		"color": Color(0.45, 0.75, 1.0), "icon": "res://assets/weapons/snare.png",
		"desc": "ปล่อยตาข่ายพลังงานวงกว้าง ศัตรูในวงจะเดินและหมุนปืนไม่ได้ในตาถัดไปของตัวเอง",
	},
	"mender": {
		"name": "Nano Mender", "radius": 0.0, "damage": 10.0, "ammo": 2, "heal": 25, "heal_radius": 130.0, "boost": 0.5, "elev": Vector2(10, 80),
		"color": Color(0.4, 1.0, 0.5), "icon": "res://assets/weapons/mender.png",
		"desc": "ฮีล 25 HP ให้เพื่อนทุกคนในวง และนัดถัดไปของทีม (อาวุธใดก็ได้) แรงขึ้น 50%",
	},
	"seeker": {
		"name": "Hunter Seeker", "radius": 34.0, "damage": 40.0, "ammo": 1, "elev": Vector2(0, 90),
		"homing": true, "homing_delay": 0.45, "turn_rate": 3.2, "lock_range": 300.0,
		"color": Color(1.0, 0.45, 0.85), "icon": "res://assets/weapons/seeker.png",
		"desc": "กระสุนติดตาม บินตามวิถีปกติจนมีศัตรูอยู่ในระยะ 300 แล้วล็อกเป้า เลี้ยวตามไปเองไม่สนแรงโน้มถ่วง ใช้ได้ครั้งเดียว",
	},
	"sky": {
		"name": "Sky Lance", "radius": 0.0, "damage": 40.0, "ammo": 1, "elev": Vector2(30, 90),
		"strike_width": 110.0, "strike_delay": 0.8, "strike_carve": 46.0,
		"color": Color(1.0, 0.92, 0.6), "icon": "res://assets/weapons/sky.png",
		"desc": "ยิงลูกบอกพิกัดไปตกตรงไหน ลำแสงจากฟ้าจะยิงลงมาถล่มพื้นตรงนั้นเป็นวงกว้าง ใช้ได้ครั้งเดียว",
	},
	# Spawned by the cluster shell, not selectable.
	"bomblet": {
		"name": "Bomblet", "radius": 20.0, "carve": 32.0, "damage": 14.0,
		"color": Color(1.0, 0.55, 0.2),
	},
}


static func get_def(id: String) -> Dictionary:
	return DATA[id]
