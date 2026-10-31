extends RefCounted
## Choices carried from the menu into a match.

const STAGES := {
	"drift": {
		"name": "Asteroid Drift",
		"desc": "เกาะหินลอยกลางอวกาศ แรงโน้มถ่วงดึงลงล่าง ตกลงไปในชั้นบรรยากาศดาวแก๊สยักษ์ = ตาย",
	},
	"orbit": {
		"name": "Orbit Field",
		"desc": "ดาวเคราะห์น้อยหลายดวง ทุกดวงมีแรงโน้มถ่วงของตัวเอง ยิงอ้อมดาวได้",
	},
}
const STAGE_ORDER := ["drift", "orbit"]

static var stage := "drift"
