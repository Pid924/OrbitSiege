extends Node2D
## Pixel-based destructible terrain. The byte mask is the single source of truth for collisions;
## the image is only what gets drawn.

const WIDTH := 1600
const HEIGHT := 900

# [crust, mantle, core] colours for each planet type.
const PALETTES := [
	[Color(0.75, 0.78, 0.82), Color(0.42, 0.44, 0.5), Color(0.2, 0.2, 0.26)],  # grey moon
	[Color(0.95, 0.55, 0.35), Color(0.62, 0.28, 0.2), Color(0.3, 0.1, 0.1)],  # rust world
	[Color(0.7, 0.92, 1.0), Color(0.3, 0.55, 0.75), Color(0.12, 0.2, 0.4)],  # ice world
	[Color(0.75, 0.6, 1.0), Color(0.42, 0.28, 0.65), Color(0.18, 0.1, 0.32)],  # crystal world
	[Color(0.6, 0.9, 0.5), Color(0.3, 0.5, 0.3), Color(0.12, 0.22, 0.14)],  # moss world
]

var image: Image
var texture: ImageTexture
var mask := PackedByteArray()
var _dirty := false


func generate(physics, rng: RandomNumberGenerator) -> void:
	image = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	mask.resize(WIDTH * HEIGHT)
	mask.fill(0)
	var shape_noise := FastNoiseLite.new()
	shape_noise.seed = rng.randi()
	shape_noise.frequency = 0.9
	var speck := FastNoiseLite.new()
	speck.seed = rng.randi()
	speck.frequency = 0.06
	var first_palette := rng.randi() % PALETTES.size()
	for i in physics.planets.size():
		var palette: Array = PALETTES[(first_palette + i) % PALETTES.size()]
		_paint_planet(physics.planets[i], shape_noise, speck, palette, float(i) * 17.0)
	texture = ImageTexture.create_from_image(image)
	queue_redraw()


func _paint_planet(p: Dictionary, shape_noise: FastNoiseLite, speck: FastNoiseLite, palette: Array, offset: float) -> void:
	var center: Vector2 = p.center
	var radius: float = p.radius
	var reach := radius * 1.2
	var x0 := maxi(0, int(center.x - reach))
	var x1 := mini(WIDTH - 1, int(center.x + reach))
	var y0 := maxi(0, int(center.y - reach))
	var y1 := mini(HEIGHT - 1, int(center.y + reach))
	var crust: Color = palette[0]
	var mantle: Color = palette[1]
	var core: Color = palette[2]
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x, y) - center
			var dist := d.length()
			if dist > reach:
				continue
			var dir := d / maxf(dist, 0.001)
			var edge := radius * (1.0 + 0.12 * shape_noise.get_noise_2d(dir.x * 1.6 + offset, dir.y * 1.6))
			if dist > edge:
				continue
			var depth := edge - dist
			var n := speck.get_noise_2d(x, y)
			var c: Color
			if depth < 5.0:
				c = crust
			else:
				c = mantle.lerp(core, clampf(1.0 - dist / edge, 0.0, 1.0) * 1.2)
				# Old impact craters for a bit of texture.
				if n > 0.35:
					c = c.darkened(0.25)
			c = c.lightened(n * 0.08)
			image.set_pixel(x, y, c)
			mask[y * WIDTH + x] = 1


func is_solid(pos: Vector2) -> bool:
	var x := int(floor(pos.x))
	var y := int(floor(pos.y))
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return false
	return mask[y * WIDTH + x] != 0


func carve(center: Vector2, radius: float) -> void:
	var rim := radius + 4.0
	var r_sq := radius * radius
	var rim_sq := rim * rim
	var x0 := maxi(0, int(center.x - rim))
	var x1 := mini(WIDTH - 1, int(center.x + rim))
	var y0 := maxi(0, int(center.y - rim))
	var y1 := mini(HEIGHT - 1, int(center.y + rim))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var idx := y * WIDTH + x
			if mask[idx] == 0:
				continue
			var d_sq := center.distance_squared_to(Vector2(x, y))
			if d_sq <= r_sq:
				mask[idx] = 0
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d_sq <= rim_sq:
				image.set_pixel(x, y, image.get_pixel(x, y).darkened(0.3))
	_dirty = true


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		texture.update(image)
		queue_redraw()


func _draw() -> void:
	if texture:
		draw_texture(texture, Vector2.ZERO)
