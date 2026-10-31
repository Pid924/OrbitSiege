extends RefCounted
## Deterministic space physics, shared by live projectiles and the bot's shot simulator.
## Every planet pulls with point gravity; solar wind is a constant push that changes each turn.

const G := 320.0  # roughly the surface gravity (px/s^2) of any planet, since mass = radius^2
const SOFTENING := 30.0
const MAX_SPEED := 950.0
const SUBSTEPS := 2
const DT := 1.0 / (60.0 * SUBSTEPS)
const MAX_FLIGHT_TIME := 9.0
const UNIT_HIT_RADIUS := 12.0

var planets: Array = []  # {"center": Vector2, "radius": float, "mass": float}
var uniform_gravity := Vector2.ZERO  # constant pull, used by flat "fall = death" stages
var wind := Vector2.ZERO
var bounds := Rect2(-250, -250, 2100, 1400)


func add_planet(center: Vector2, radius: float) -> void:
	planets.append({"center": center, "radius": radius, "mass": radius * radius})


func gravity_at(pos: Vector2) -> Vector2:
	var g := uniform_gravity
	for p in planets:
		var d: Vector2 = p.center - pos
		var dist_sq := d.length_squared() + SOFTENING * SOFTENING
		g += d.normalized() * (G * p.mass / dist_sq)
	return g


func dominant_planet(pos: Vector2) -> Dictionary:
	var best := {}
	var best_pull := -1.0
	for p in planets:
		var pull: float = p.mass / (pos.distance_squared_to(p.center) + 1.0)
		if pull > best_pull:
			best_pull = pull
			best = p
	return best


## Local "up" for something standing near a planet: away from the planet that pulls hardest.
func up_at(pos: Vector2) -> Vector2:
	var p := dominant_planet(pos)
	if p.is_empty():
		return -uniform_gravity.normalized() if uniform_gravity != Vector2.ZERO else Vector2.UP
	var v: Vector2 = pos - p.center
	return v.normalized() if v.length_squared() > 0.01 else Vector2.UP


## Simulates a shot without side effects, using exactly the same integration as Projectile.
## Returns the impact point, or null when the shell is lost in space.
func simulate_shot(start: Vector2, vel: Vector2, terrain, targets: PackedVector2Array, ignore_time := 0.15) -> Variant:
	var pos := start
	var age := 0.0
	var hit_sq := UNIT_HIT_RADIUS * UNIT_HIT_RADIUS
	for i in int(MAX_FLIGHT_TIME / DT):
		age += DT
		vel += (gravity_at(pos) + wind) * DT
		pos += vel * DT
		if not bounds.has_point(pos):
			return null
		if terrain.is_solid(pos):
			return pos
		if age > ignore_time:
			for t in targets:
				if pos.distance_squared_to(t) < hit_sq:
					return pos
	return null
