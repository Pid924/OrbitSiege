extends RefCounted
## Weapon definitions. Pure data, referenced by id so a network layer can send just the id.

const LIST := ["plasma", "cluster", "driller"]

const DATA := {
	"plasma": {
		"name": "Plasma Shell", "radius": 40.0, "damage": 45.0, "knockback": 260.0,
		"color": Color(0.4, 0.9, 1.0), "icon": "res://assets/weapons/plasma.png",
		"desc": "กระสุนพลาสมามาตรฐาน ระเบิดวงกว้าง ดาเมจสูง ใช้ได้ทุกสถานการณ์",
	},
	"cluster": {
		"name": "Star Cluster", "radius": 24.0, "damage": 20.0, "knockback": 150.0,
		"color": Color(1.0, 0.75, 0.3), "bomblets": 5, "icon": "res://assets/weapons/cluster.png",
		"desc": "กระทบแล้วแตกเป็นลูกย่อย 5 ลูกกระจายรอบจุดตก เหมาะกับศัตรูที่ยืนใกล้กัน",
	},
	"driller": {
		"name": "Void Driller", "radius": 34.0, "damage": 40.0, "knockback": 220.0,
		"color": Color(0.8, 0.45, 1.0), "drill_time": 0.45, "icon": "res://assets/weapons/driller.png",
		"desc": "เจาะทะลุพื้นเข้าไปเกือบครึ่งวินาทีแล้วค่อยระเบิด ใช้ขุดถึงศัตรูที่หลบหลังกำบัง",
	},
	# Spawned by the cluster shell, not selectable.
	"bomblet": {
		"name": "Bomblet", "radius": 20.0, "damage": 14.0, "knockback": 120.0,
		"color": Color(1.0, 0.55, 0.2),
	},
}


static func get_def(id: String) -> Dictionary:
	return DATA[id]
